use IRC::Log:ver<0.0.19>:auth<zef:lizmat>;

class IRC::Log::Textual:ver<0.0.14>:auth<zef:lizmat> does IRC::Log {

    # Custom .new to handle fact that Textual stores files per date
    # in **LOCAL** time rather than in UTC.
    multi method new(IRC::Log::Textual:U:
      IO:D $path,
      Date() $Date = self.IO2Date($path)
    ) {
        my str $basename = $path.basename;
        my str $date     = $Date.Str;

        my $before :=
          $path.sibling($Date.earlier(:1day) ~ $basename.substr(10));
        my $after :=
          $path.sibling($Date.later(:1day) ~ $basename.substr(10));

        my $slurped :=
          ($before.slurp   if $before.e)
          ~ ($path.slurp   if $path.e)
          ~ ($after.slurp  if $after.e);

        self.new($slurped, $Date)
    }

    method !problem(Str:D $line, Int:D $linenr, Str:D $reason --> Nil) {
        $!problems.push: "Line $linenr: $reason" => $line;
    }

    method parse-log(IRC::Log::Textual:D:
      str $text,
          $last-hour               is raw,
          $last-minute             is raw,
          $ordinal                 is raw,
          $linenr                  is raw,
          $nr-control-entries      is raw,
          $nr-conversation-entries is raw,
    --> Nil) is implementation-detail {

        for $text.split("\n").grep({ ++$linenr; .chars }) -> $line {

            if $line.starts-with('[') && $line.substr-eq('] ',25)
              && $line.substr(1,24).DateTime -> $DateTime {
                my $utc := $DateTime.utc;
                next if $utc.Date ne $!date;

                # Textual session markers
                my $text := $line.substr(27);
                next
                  if $text eq ' '
                  || $text eq 'Disconnected'
                  || $text.starts-with('------------- ')
                  || $text.starts-with('Mode is ')
                  || $text.starts-with('Topic is ')
                  || $text.starts-with('Set by ');
                  || $text.starts-with("You're now known as ");

                my int $hour   = $utc.hour;
                my int $minute = $utc.minute;
                if $minute == $last-minute && $hour == $last-hour {
                    ++$ordinal;
                }
                else {
                    $last-hour   = $hour;
                    $last-minute = $minute;
                    $ordinal     = 0;
                }

                if $text.starts-with('<') {
                    with $text.index('> ') -> $index {
                        IRC::Log::Message.new:
                          :log(self), :$hour, :$minute, :$ordinal,
                          :nick($text.substr(1,$index - 1)),
                          :text($text.substr($index + 2));
                        ++$nr-conversation-entries;
                    }
                    orwith $text.index('> ', :ignoremark) -> $index {
                        IRC::Log::Message.new:
                          :log(self), :$hour, :$minute, :$ordinal,
                          :nick($text.substr(1,$index - 1)),
                          :text($text.substr($index + 2));
                        ++$nr-conversation-entries;
                    }
                    else {
                        self!problem($line, $linenr,
                          "could not find nick delimiter");
                    }
                }
                elsif $text.starts-with('• ') {
                    with $text.index(': ',2) -> $index {
                        IRC::Log::Self-Reference.new:
                          :log(self), :$hour, :$minute, :$ordinal,
                          :nick($text.substr(2,$index - 2)),
                          :text($text.substr($index + 2));
                        ++$nr-conversation-entries;
                    }
                    else {
                        self!problem($line, $linenr,
                          "self-reference nick");
                    }
                }

                # assume some type control message
                else {
                    with $text.index(' (') -> $par-open {
                        my $nick := $text.substr(0,$par-open);
                        with $text.index(') ',$par-open) -> $par-close {
                            my $message := $text.substr($par-close + 2);
                            if $message.starts-with('joined ') {
                                IRC::Log::Joined.new:
                                  :log(self), :$hour, :$minute, :$ordinal,
                                  :$nick;
                                ++$nr-control-entries;
                            }
                            elsif $message.starts-with('left ') {
                                IRC::Log::Left.new:
                                  :log(self), :$hour, :$minute, :$ordinal,
                                  :$nick;
                                ++$nr-control-entries;
                            }
                            else {
                                self!problem($line, $linenr,
                                  'unclear control message');
                            }
                            next;
                        }
                    }

                    # not a verbose control message
                    with $text.index(' is now known as ') -> $index {
                        IRC::Log::Nick-Change.new:
                          :log(self), :$hour, :$minute, :$ordinal,
                          :nick($text.substr(0,$index)),
                          :new-nick($text.substr($index + 17));
                        ++$nr-control-entries;
                    }
                    orwith $text.index(' sets mode ') -> $index {
                        my @nick-names = $text.substr($index + 11).words;
                        my $flags     := @nick-names.shift;
                        IRC::Log::Mode.new:
                          :log(self), :$hour, :$minute, :$ordinal,
                          :nick($text.substr(0,$index)),
                          :$flags, :@nick-names;
                        ++$nr-control-entries;
                    }
                    orwith $text.index(' changed the topic to ') -> $index {
                        self.last-topic-change = IRC::Log::Topic.new:
                          :log(self), :$hour, :$minute, :$ordinal,
                          :nick($text.substr(0,$index)),
                          :text($text.substr($index + 22));
                        ++$nr-control-entries;
                        ++$nr-conversation-entries;
                    }
                    orwith $text.index(' kicked ') -> $index {
                        with $text.index(
                          ' from the channel ', $index
                        ) -> $spec {
                            IRC::Log::Kick.new:
                              :log(self), :$hour, :$minute, :$ordinal,
                              :nick($text.substr(0,$index)),
                              :kickee($text.substr(
                                $index + 8, $spec - $index - 8
                              )),
                              :spec($text.substr($spec + 18));
                            ++$nr-control-entries;
                        }
                        else {
                            self!problem($line, $linenr,
                              "unclear kick message");
                        }
                    }
                    else {
                        self!problem($line, $linenr,
                          "unclear control message");
                    }
                }
            }
            elsif $line.trim.chars {
                self!problem($line, $linenr,
                  "no timestamp found");
            }
        }
    }
}

#-------------------------------------------------------------------------------
# Documentation

=begin pod

=head1 NAME

IRC::Log::Textual - interface to IRC logs from Textual

=head1 SYNOPSIS

=begin code :lang<raku>

use IRC::Log::Textual;

my $log = IRC::Log::Textual.new($filename.IO);

say "Logs from $log.date()";
.say for $log.entries.List;

my $log = IRC::Log::Textual.new($text, $date);

=end code

=head1 DESCRIPTION

IRC::Log::Textual provides an interface to the IRC logs that are generated by
the Textual application on MacOS.  Please see L<IRC::Log> for more information.

Since Textual stores its daily file in the local time zone, specifying a
path with C<.new> will B<also> read the files in the same directory that are
one day before it and one day after it to make sure all entries of the date
in UTC are captured.

=head1 AUTHOR

Elizabeth Mattijsen <liz@raku.rocks>

Source can be located at: https://github.com/lizmat/IRC-Log-Textual .
Comments and Pull Requests are welcome.

=head1 COPYRIGHT AND LICENSE

Copyright 2021 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod

# vim: expandtab shiftwidth=4
