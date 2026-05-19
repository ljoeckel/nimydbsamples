# Here we add stemming, stop words & ranking (like Py, but 1/8 time, 2/3 space).
when not declared(File): import std/syncio
#import sets, tables, math, strutils, algorithm, streams, parsexml, sugar, times
import math, strutils

# /usr/lib/x86_64-linux-gnu/libstemmer.so.0
# sudo apt install libstemmer-tools
{.passl: "/usr/lib/x86_64-linux-gnu/libstemmer.so.0d".}   # YOU MAY NEED TO ADJUST THIS!

type sb_stemmer {.bycopy.} = object
proc sb_stemmer_new(algo: cstring; charenc: cstring): ptr sb_stemmer
  {.importc: "sb_stemmer_new".}
proc sb_stemmer_stem(stm: ptr sb_stemmer; word: cstring; size: cint): cstring
  {.importc: "sb_stemmer_stem".}
proc sb_stemmer_length(stm:ptr sb_stemmer):cint {.importc: "sb_stemmer_length".}

let stmDE = sb_stemmer_new("german", "UTF_8")
let stmEN = sb_stemmer_new("english", "UTF_8")
let stmES = sb_stemmer_new("spanish", "UTF_8")

proc stem(wrd: string, stm: ptr sb_stemmer): string =       # wrap snowball stemmer
  let word = strip(tolower(wrd))
  let cs = stm.sb_stemmer_stem(cstring(word), word.len.cint)
  let cn = stm.sb_stemmer_length
  result.setLen int(cn)
  copyMem result[0].addr, cs, int(cn)


# TODO: create a lang/stemmer table
proc stem*(word: string, lang: string): string =
  if word.isEmptyOrWhitespace: return ""
  let ucLang = lang.toUpper()

  if ucLang == "DE":
      return stem(word, stmDE)
  elif ucLang == "EN":
      return stem(word, stmEN)
  elif ucLang == "ES":
      return stem(word, stmES)
  else:
    return ""
