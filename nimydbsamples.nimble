# Package

version       = "0.0.1"
author        = "Lothar Jöckel"
description   = "Samples how to use nim-yottadb"
license       = "MIT"
srcDir        = "src"

# Dependencies

requires "nim >= 2.2.4"
#requires "nimyottadb >= 0.4.5"
requires "https://github.com/ljoeckel/nim-yottadb.git"
#requires "file://home/ljoeckel/git/nim-yottadb/src"
requires "https://github.com/ljoeckel/mummyDS.git"

# Tasks
task demo, "formtx":
  exec "cd src/datastar && nim c -r -d:release --threads:on --hints:off --verbosity:0 formtx.nim"
