# Package

version       = "0.0.1"
author        = "Lothar Jöckel"
description   = "Samples how to use nim-yottadb"
license       = "MIT"
srcDir        = "src"

# Dependencies

requires "nim >= 2.2.6"
requires "datastar"
requires "nimyottadb"

# Tasks
task demo, "Run http server on http://localhost:8080 and fill out a form":
  exec "cd src/datastar && nim c -r -d:release --threads:off --hints:off --verbosity:0 form.nim"
