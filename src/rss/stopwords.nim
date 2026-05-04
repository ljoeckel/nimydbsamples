import std/[sequtils]
import std/[options, parseopt, strutils, strformat, typetraits, os]
import std/tables

import types
import yottadb
import stemmer

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

proc isStopword(word: string, lang: string): bool =
    result = false
    if word.len == 0: return false
    if ydb_data(STOPWORDS["ALL"], @[word]) > 0: return true
    if STOPWORDS.contains(lang):
        return ydb_data(STOPWORDS[lang], @[word]) > 0

proc splitWords(text: string, lang: string): seq[string] =
    # Replace with ' '
    var s: string
    for c in toLower(strip(text)):
        if c in {'\0'..'/', ':'..'@', '['..'`', '{'..'~'}: 
            s.add(' ')
            continue
        else:
            s.add(c)

    s = s.multiReplace(
        ("«"," "),
        ("“"," "),
        ("„"," "),
        ("†"," "),
        ("•"," "),
        ("…"," "),
        ("–"," "),
        (".", " "),
        ("?", " "),
        (",", " "),
        ("-", " "),
        ("—"," "),
        ("_", " "),
        ("'", " "),
        ("`", " "),
        ("\"", " "),
        ("‘", " "),
        ("‚", " "),
        (":", " "),
        ("‘"," "),
        ("”", " "),
        ("»", " "),
        (" ", " "), # C2A0
        (" ", " "), # E280AF
        ("►", " "),
        ("◄", " "),
        ("■", " "),
        ("’", " "),
        ("ß", "ss"),
        ("ä", "a"),
        ("ö", "o"),
        ("ü", "u"),
        ("\t", " "),
        ("\n", " "),
        ("https", " "),
        ("html", " "),
    )

    var spaces = s.find("  ")
    while spaces > 0:
        s = s.replace("  ", " ")
        spaces = s.find("  ")

    result = s.split(' ')
    result = result.filterIt(it.len > 2 and it.len < 40) # min 3, max 39
    result = result.filterIt(not it.isStopword(lang)) # No stopwords


proc createFTIndex*(item: RSSItem, lang: string): int =
    #var wordCount = 0
    let categories = item.category.join(" ")
    let keywords = item.keywords.join(" ")
    let topic = if item.topic.isSome: item.topic.get() else: ""
    let title = if item.title.isSome: item.title.get() else: ""
    let description = if item.description.isSome: item.description.get() else: ""
    let keys = item.idxref.split(',') # the db key rss,article
    let (k0, k1) = (keys[0], keys[1])

    let words = splitWords(categories & " " & keywords & " " & topic & " " & title & " " & description, lang)
    var wordtable = initCountTable[string]()
    #echo "words=", words
    for word in words: wordtable.inc(word)

    for word, cnt in wordtable.pairs:
        if word == " " or word.len == 0:
            echo "Empty or blank not valid word.  words=", words
        else:
            let stemWord = stem(word, lang)
            if stemWord.len > 0:
                Set: ^RSSItemFTI(stemWord, k0, k1) = cnt

    return wordtable.len

proc createFTI*(rss: RSS): int =
    var language = if rss.language.isSome: toUpper(rss.language.get()) else: DEFAULT_LANGUAGE
    if language.find('-') > 0: language = language.split('-')[0] # de-de -> de, en-US -> en
    for item in rss.items:
        inc(result, createFTIndex(item, language))


proc createRSSItemIndex() =
    var wordCount: int
    for rssId in OrderItr ^RSS:
        let rss = loadObject[RSS](rssId)
        var language = if rss.language.isSome: toUpper(rss.language.get()) else: "XX"
        if language.find('-') > 0: language = language.split('-')[0]
        for item in rss.items:
            inc(wordCount, createFTIndex(item, language))
    
    echo fmt"Indexed {wordCount} words"


proc main() =
    var lang: string

    var p = initOptParser()
    for kind, key, val in p.getopt():
        case kind
        # Ein normales Argument (z. B. "meinfile.txt")
        of cmdArgument: discard
        of cmdLongOption, cmdShortOption:
            if key == "h" or key == "help":
                echo "-l=<language> : Load stopwords into DB"
                echo "-c    : Create Fulltext Index"
                echo "-d    : Dump RSSItemFTI"
                echo "-i=id : Load a RSS into FTI"
                quit(0)
            if key == "l" or key == "language": 
                lang = val
                echo fmt"Loading stopwords for language '{lang}'"
                let words = setupStopwords(lang)
                echo fmt"Loaded {words} words"
            elif key == "c" or key == "create":
                Kill: ^RSSItemFTI
                createRSSItemIndex()
            elif key == "d" or key == "dump":
                for key in OrderItr ^RSSItemFTI:
                    echo key
            elif key == "i":
                let rss = loadObject[RSS](val)
                let rc = createFTI(rss)
                echo "rc=", rc
        of cmdEnd: discard

if isMainModule:
    Kill: ^RSSItemFTI
    main()
