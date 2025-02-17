[![Actions Status](https://github.com/lizmat/IRC-Log-Textual/actions/workflows/linux.yml/badge.svg)](https://github.com/lizmat/IRC-Log-Textual/actions) [![Actions Status](https://github.com/lizmat/IRC-Log-Textual/actions/workflows/macos.yml/badge.svg)](https://github.com/lizmat/IRC-Log-Textual/actions) [![Actions Status](https://github.com/lizmat/IRC-Log-Textual/actions/workflows/windows.yml/badge.svg)](https://github.com/lizmat/IRC-Log-Textual/actions)

NAME
====

IRC::Log::Textual - interface to IRC logs from Textual

SYNOPSIS
========

```raku
use IRC::Log::Textual;

my $log = IRC::Log::Textual.new($filename.IO);

say "Logs from $log.date()";
.say for $log.entries.List;

my $log = IRC::Log::Textual.new($text, $date);
```

DESCRIPTION
===========

The <IRC::Log::Textual> distrubution provides an interface to the IRC logs that are generated by the *Textual* application on MacOS. Please see [C<<IRC::Log>](https://raku.land/zef:lizmat/IRC::Log) for more information.

Since Textual stores its daily file in the local time zone, specifying a path with `.new` will **also** read the files in the same directory that are one day before it and one day after it to make sure all entries of the date in UTC are captured.

AUTHOR
======

Elizabeth Mattijsen <liz@raku.rocks>

Source can be located at: https://github.com/lizmat/IRC-Log-Textual . Comments and Pull Requests are welcome.

If you like this module, or what I'm doing more generally, committing to a [small sponsorship](https://github.com/sponsors/lizmat/) would mean a great deal to me!

COPYRIGHT AND LICENSE
=====================

Copyright 2021, 2025 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

