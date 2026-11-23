# begin Nimble config (version 2)
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config


const ydbDist =
  block:
    let fromEnv = getEnv("ydb_dist")
    if fromEnv.len > 0: fromEnv else: "/usr/local/lib/yottadb/r207"

{.passL: "-L" & ydbDist & " -lyottadb -Wl,-rpath," & ydbDist.}

# --- llama.cpp embedding backend (ydb-hnsw) ----------------------------------
# ydb-hnsw's llama_embed.nim compiles llama_shim.c against llama.h and links the
# shared llama/ggml libraries. Its own config.nims does not apply when the
# package is installed as a dependency, so the build tree has to be handed to
# the compiler here. LLAMA_CPP_DIR must be a llama.cpp *build* directory - the
# one holding bin/libllama.so; the headers are at ../include and
# ../ggml/include.
const llamaCppBuild =
  block:
    let fromEnv = getEnv("LLAMA_CPP_DIR")
    if fromEnv.len > 0: fromEnv else: "/home/ljoeckel/git/llama.cpp/build"

switch("define", "llamaCppDir=" & llamaCppBuild)

# hnsw.nim's distance kernels use the nimsimd intrinsics, which need -mavx.
if not defined(hnswNoSimd):
  switch("define", "hnswSimd")
  switch("passC", "-mavx")
