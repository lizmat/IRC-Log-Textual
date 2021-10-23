use v6.*;

use IRC::Log:ver<0.0.11>:auth<zef:lizmat>;

class IRC::Log::Textual:ver<0.0.7>:auth<zef:lizmat> does IRC::Log {

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

    method parse(IRC::Log::Textual:D:
      Str:D $slurped,
      Date:D $Date
    ) is implementation-detail {
        $!date = $Date;

        # assume spurious event without change that caused update
        return Empty if $!raw && $!raw eq $slurped;

        my $to-parse;
        my int $last-hour;
        my int $last-minute;
        my int $ordinal;
        my int $linenr;
        my int $pos;

        # done a parse before for this object
        if %!state -> %state {

            # adding new lines on log
            if $slurped.starts-with($!raw) {
                $last-hour   = %state<last-hour>;
                $last-minute = %state<last-minute>;
                $ordinal     = %state<ordinal>;
                $linenr      = %state<linenr>;
                $pos         = $!entries.elems;
                $to-parse   := $slurped.substr($!raw.chars);
            }

            # log appears to be altered, run it from scratch!
            else {
                $!entries.clear;
                %!nicks = @!problems = ();
                $!nr-control-entries = $!nr-conversation-entries = 0;
                $last-hour = $last-minute = $linenr = -1;
                $to-parse  = $slurped;
            }
        }

        # first parse
        else {
            $last-hour = $last-minute = $linenr = -1;
            $to-parse = $slurped;
        }

        # we need a "push" that does not containerize
        my int $initial-nr-entries = $!entries.elems;
        my int $accepted = $initial-nr-entries - 1;

        # accept an entry
        method !accept(\entry --> Nil) {
            with %!nicks{entry.nick} -> $entries-by-nick {
                $entries-by-nick.push($!entries.push(entry));
            }
            else {
                (%!nicks{entry.nick} := IterationBuffer.CREATE)
                  .push($!entries.push(entry));
            }
            ++$pos;
        }

        method !problem(Str:D $line, Str:D $reason --> Nil) {
            @!problems[@!problems.elems] := "Line $linenr: $reason" => $line;
        }

        for $to-parse.split("\n").grep({ ++$linenr; .chars }) -> $line {

            if $line.starts-with('[') && $line.substr-eq('] ',25)
              && $line.substr(1,24).DateTime -> $DateTime {
                my $utc := $DateTime.utc;
                next if $utc.Date ne $Date;

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
                        self!accept: IRC::Log::Message.new:
                          :log(self), :$hour, :$minute, :$ordinal, :$pos,
                          :nick($text.substr(1,$index - 1)),
                          :text($text.substr($index + 2));
                        ++$!nr-conversation-entries;
                    }
                    orwith $text.index('> ', :ignoremark) -> $index {
                        self!accept: IRC::Log::Message.new:
                          :log(self), :$hour, :$minute, :$ordinal, :$pos,
                          :nick($text.substr(1,$index - 1)),
                          :text($text.substr($index + 2));
                        ++$!nr-conversation-entries;
                    }
                    else {
                        self!problem($line,"could not find nick delimiter");
                    }
                }
                elsif $text.starts-with('• ') {
                    with $text.index(': ',2) -> $index {
                        self!accept: IRC::Log::Self-Reference.new:
                          :log(self), :$hour, :$minute, :$ordinal, :$pos,
                          :nick($text.substr(2,$index - 2)),
                          :text($text.substr($index + 2));
                        ++$!nr-conversation-entries;
                    }
                    else {
                        self!problem($line, "self-reference nick");
                    }
                }

                # assume some type control message
                else {
                    with $text.index(' (') -> $par-open {
                        my $nick := $text.substr(0,$par-open);
                        with $text.index(') ',$par-open) -> $par-close {
                            my $message := $text.substr($par-close + 2);
                            if $message.starts-with('joined ') {
                                self!accept: IRC::Log::Joined.new:
                                  :log(self), :$hour, :$minute, :$ordinal,
                                  :$pos, :$nick;
                                ++$!nr-control-entries;
                            }
                            elsif $message.starts-with('left ') {
                                self!accept: IRC::Log::Left.new:
                                  :log(self), :$hour, :$minute, :$ordinal,
                                  :$pos, :$nick;
                                ++$!nr-control-entries;
                            }
                            else {
                                self!problem($line, 'unclear control message');
                            }
                            next;
                        }
                    }

                    # not a verbose control message
                    with $text.index(' is now known as ') -> $index {
                        self!accept: IRC::Log::Nick-Change.new:
                          :log(self), :$hour, :$minute, :$ordinal, :$pos,
                          :nick($text.substr(0,$index)),
                          :new-nick($text.substr($index + 17));
                        ++$!nr-control-entries;
                    }
                    orwith $text.index(' sets mode ') -> $index {
                        my @nicks  = $text.substr($index + 11).words;
                        my $flags := @nicks.shift;
                        self!accept: IRC::Log::Mode.new:
                          :log(self), :$hour, :$minute, :$ordinal, :$pos,
                          :nick($text.substr(0,$index)),
                          :$flags, :@nicks;
                        ++$!nr-control-entries;
                    }
                    orwith $text.index(' changed the topic to ') -> $index {
                        my $topic := IRC::Log::Topic.new:
                          :log(self), :$hour, :$minute, :$ordinal, :$pos,
                          :nick($text.substr(0,$index)),
                          :text($text.substr($index + 22));
                        self!accept: $topic;
                        $!last-topic-change = $topic;
                        ++$!nr-conversation-entries;
                    }
                    orwith $text.index(' kicked ') -> $index {
                        with $text.index(
                          ' from the channel ', $index
                        ) -> $spec {
                            self!accept: IRC::Log::Kick.new:
                              :log(self), :$hour, :$minute, :$ordinal,
                              :$pos, :nick($text.substr(0,$index)),
                              :kickee($text.substr(
                                $index + 8, $spec - $index - 8
                              )),
                              :spec($text.substr($spec + 18));
                            ++$!nr-control-entries;
                        }
                        else {
                            self!problem($line, "unclear kick message");
                        }
                    }
                    else {
                        self!problem($line, "unclear control message");
                    }
                }
            }
            elsif $line.trim.chars {
                self!problem($line, "no timestamp found");
            }
        }

        # save current state in case of updates
        $!raw   = $slurped;
        %!state = :parsed($slurped.chars),
          :$last-hour, :$last-minute, :$ordinal, :$linenr;

        $!entries.Seq.skip($initial-nr-entries)
    }
}

#my $log = IRC::Log::Textual.new:
#  '/Users/liz/Documents/Textual/Libera (192C2)/Channels/#raku/2021-05-26.txt'.IO
#;
#.say for $log.entries;
#dd $_ for $log.problems;

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
