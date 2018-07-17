Auth Redux Mod v2.5b
By Leslie Krause

Auth Redux is a drop-in replacement for the builtin authentication handler of Minetest.
It is designed from the ground up to be robust and secure enough for use on high-traffic
Minetest servers, while also addressing a number of outstanding bugs (including #5334 
and #6783 and #4451).

Auth Redux is intended to be compatible with all versions of Minetest 0.4.14+.

https://forum.minetest.net/viewtopic.php?f=9&t=20393

Repository
----------------------

Browse source code:
  https://bitbucket.org/sorcerykid/auth_rx

Download archive:
  https://bitbucket.org/sorcerykid/auth_rx/get/master.zip
  https://bitbucket.org/sorcerykid/auth_rx/get/master.tar.gz

Revision History
----------------------

Version 2.1b (30-Jun-2018)
  - initial beta version
  - included code samples for basic login filtering
  - included a command-line database import script

Version 2.2b (04-Jul-2018)
  - added install option to database import script
  - improved exception handling by AuthFilter class
  - fixed parsing of number literals in rulesets
  - fixed type-checking of try statements in rulesets
  - included mod.conf and description.txt files

Version 2.3b (08-Jul-2018)
  - general code cleanup of AuthFilter class
  - moved datasets into separate directory of world
  - added two more comparison operators for rulesets
  - tweaked pattern matching behavior in rulesets
  - changed database search method to use Lua regexes
  - removed hard-coded file names from database methods

Version 2.4b (13-Jul-2018)
  - moved Journal and AuthDatabase classes into library
  - added rollback function to AuthDatabase class
  - reworked journal audit to support rollback option
  - better encapsulated database commit function
  - allowed for STOPPED opcode during database update
  - various changes to error and action messages
  - moved command-line scripts to separate directory
  - included script to rollback database via journal
  - included script to extract debug log into journal

Version 2.5b (17-Jul-2018)
  - implemented function parsing algorithm for rulesets
  - simplified operand matching logic in rulesets
  - improved transcoding of literals in rulesets
  - added some basic functions for use by rulesets
  - fixed validation of dataset names in rulesets

Installation
----------------------

  1) Unzip the archive into the mods directory of your game
  2) Rename the auth_rx-master directory to "auth_rx"
  3) Execute the "convert.awk" script (refer to instructions)

Source Code License
----------------------

The MIT License (MIT)

Copyright (c) 2016-2018, Leslie Krause (leslie@searstower.org)

Permission is hereby granted, free of charge, to any person obtaining a copy of this
software and associated documentation files (the "Software"), to deal in the Software
without restriction, including without limitation the rights to use, copy, modify, merge,
publish, distribute, sublicense, and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.

For more details:
https://opensource.org/licenses/MIT
