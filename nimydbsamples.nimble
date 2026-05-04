# Package

version       = "0.0.1"
author        = "Lothar Jöckel"
description   = "Samples how to use nim-yottadb"
license       = "MIT"
srcDir        = "src"

# Dependencies
requires "nim >= 2.2.4"
requires "https://github.com/ljoeckel/nim-yottadb.git"
requires "https://github.com/ljoeckel/mummyDS.git"
requires "checksums"

# Tasks
task demo, "formtx":
  exec "cd src/datastar && nim c -r -d:release --threads:on --hints:off --verbosity:0 formtx.nim"
