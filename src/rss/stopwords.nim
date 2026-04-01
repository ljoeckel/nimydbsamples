import std/[strformat, strutils]
import yottadb
import std/strformat
import std/strutils
import std/wordwrap
import std/[algorithm, sequtils]
import std/[options, strutils, strformat, typetraits, enumerate, os]
import std/[sha1, base64, parseopt, httpclient, times]
import std/tables
import rssatom
import ydbutils

const STOPWORDS = {
    "ALL": "^stopwordsALL",
    "DE": "^stopwordsDE",
    "EN": "^stopwordsEN",
    "XX": "^stopwordsALL"
  }.toTable


proc setupStopwords(lang: string): int =
    let path = fmt"stopwords_{lang}.txt"
    if not os.fileExists(path):
        echo fmt"ERROR: No stopword file '{path}' found"
        return

    let gbl = fmt"^stopwords{toUpper(lang)}"
    Kill: @gbl

    let stopwords = toLower(readFile(path))
    for word in stopwords.split('\n'):
        if word.startsWith(";") or word.len == 0: continue
        Set: @gbl(word) = ""
        inc result

proc splitWord(text: string): seq[string] =
  let trenner: set[char] = {' ', '<', '>', ':', '-', '/', '(', ')', '.', ','}
  result = text.split(trenner)
  result = result.filterIt(it.len > 2) # Minimum length 3 chars

proc normalizeWord(wrd: string): string =
    if wrd.startsWith("http"): return ""
    #„Buddenbrooks“
    var word = wrd.multiReplace(
        ("https://", ""), ("rss", ""), ("www", ""),
        (";", ""), ("_", ""), ("„", ""), ("“", ""),
        ("\"", ""), (" ", ""), (",", ""),
        ("–", ""), # Unicode seq
    )

    let words = splitWord(word)
    for word in words:
        if word.len > 30:
            echo "Ignored word: ", word
            return ""

        for c in strip(word):
            if c in {'\0'..'/', ':'..'@', '['..'`', '{'..'~'}: continue
            result.add(c)

proc isStopword(word: string, lang: string): bool =
    if word.len == 0: return false
    if ydb_data(STOPWORDS["ALL"], @[word]) > 0: return true
    return ydb_data(STOPWORDS[lang], @[word]) > 0

proc createFTIndex(item: RSSItem, lang: string) =
    let title = if item.title.isSome: toLower(item.title.get()) else: ""
    let description = if item.description.isSome: toLower(item.description.get()) else: ""
    let idxref = item.idxref

    let words = splitWord(title & description)
    for wrd in words:
        let word = normalizeWord(wrd)
        if word.len == 0: continue
        if word.find('-') > 0: 
            echo "-"
            quit(0)
        if isStopword(word, lang): continue
        let keys = idxref.split(',')
        let k0 = keys[0]
        let k1 = keys[1]
        Set: ^RSSItemFTI(word, k0, k1) = ""


proc createRSSItemIndex() =
    for rssId in OrderItr ^RSS:
        let rss = loadObject[RSS](rssId)
        var language = if rss.language.isSome: toUpper(rss.language.get()) else: "XX"
        if language.find('-') > 0: language = language.split('-')[0]
        for item in rss.items:
            createFTIndex(item, language)

proc main() =
    var lang: string

    var p = initOptParser()
    for kind, key, val in p.getopt():
        case kind
        # Ein normales Argument (z. B. "meinfile.txt")
        of cmdArgument: discard
        of cmdLongOption, cmdShortOption:
            if key == "h" or key == "help":
                echo "setup_stopwords -l=<language>"
                echo "-c : Create Fulltext Index"
                quit(0)
            if key == "l" or key == "language": 
                lang = val
                echo fmt"Loading stopwords for language '{lang}'"
                let words = setupStopwords(lang)
                echo fmt"Loaded {words} words"
            if key == "c" or key == "create":
                Kill: ^RSSItemFTI
                createRSSItemIndex()
            if key == "d" or key == "dump":
                for key in OrderItr ^RSSItemFTI:
                    echo key
        of cmdEnd: discard


if isMainModule:
    main()
    # let x = "–"
    # for c in x:
    #     echo c, ord(c)
