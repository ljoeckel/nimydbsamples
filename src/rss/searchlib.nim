import std/strformat
import std/wordwrap
import std/[algorithm, sequtils, tables]
import std/[options, strutils, typetraits]
import std/[sha1, base64, httpclient, times]
import rssatom
import yottadb
import types
import sugar

const TIME_FORMATS* = [
    "yyyy-MM-dd'T'HH:mm:sszzz",
    "ddd, d MMM yyyy HH:mm:ss ZZZ",
    "ddd, d MMM yyyy HH:mm:ss 'GMT'",
    "ddd, d MMM yyyy HH:mm:ss 'UTC'",
    "ddd, d MMM yyyy HH:mm:ss 'EDT'",
    "d MMM yyyy HH:mm:ss ZZZ",
  ]


template getOption*(option: Option): string =
    if option.isSome: option.get() else: ""


proc getRSSFeedConfiguration*(path: string): Table[string, seq[string]] =
    # Get the RSS feeds from feeds.rss
    # [Section] content content [Section2] content content
    var currentSection = ""
    result[currentSection] = @[]

    for line in lines(path):
        let trimmed = line.strip()
        if trimmed == "" or trimmed.startsWith("#"): continue
  
        if trimmed.startsWith("[") and trimmed.endsWith("]"):
            currentSection = trimmed[1 .. ^2]
            result[currentSection] = @[]
        else:
            result[currentSection].add(trimmed)

proc generateSHA1*(input: string, length: int = 16): string =
  let hash = secureHash(input) # calculate SHA1
  let bytes = cast[array[20, byte]](hash) # convert distinct type to byte array
  # 3. Bytes in einen String für den Encoder umwandeln
  var rawData = ""
  for b in bytes: 
    rawData.add(char(b))
  # 4. Base64-Encoding (URL-safe)
  let b64 = encode(rawData, safe = true)
  # 5. Kürzen auf die gewünschte Länge
  return b64[0 ..< min(length, b64.len)]

proc normalizeChannelTitle*(title: string): string =
    # result = result.multiReplace(
    #     ("RSS CHANNEL", ""), 
    #     ("AKTUELLE", ""), ("WWW", ""), ("ONLINE", ""),
    #     ("TICKER", ""), ("SCHLAGZEILEN", ""), ("NEUIGKEITEN", ""), ("NEWS", ""),
    #     ("DIE", ""), ("DER", ""), ("IM", ""), ("VON",""), ("UND",""), ("AUS",""),
    #     ("  "," "), ("-", ""), (",", ""),
    #     ("SECTION", ""),
    # )
    result = title
    let idx = result.toUpper().find(" VOM ")
    if idx > 0:
        result = result[0..idx-1] # Edgecase "Deutschlandfunk Nachrichten vom 01.01.2026"

    while find(result,"  ") > 0:
        result = result.replace("  "," ")
    while result.len > 60:
        let pos = result.rfind(" ")
        if pos > 0:
            result = result[0..pos-1]
    return result.strip


proc normalizeUrl*(url: string): string =
    result = url.multiReplace(
        ("https://", ""), ("rss", ""), ("www", ""),
        ("/", ""), (".", ""), ("-", ""), ("!", ""),
        (";", ""), ("_", "")
    )


proc getKeywords*(keyword: string = ""): seq[string] =
    let kw = toLower(keyword)
    var combined: seq[string]
    for indexName in @["category", "topic", "keywords"]:
        var global = fmt"^RSSItem{indexName.toUpper}"
        if kw.len > 0:
            global.add(fmt"({kw})")
        for key  in OrderItr @global:
            if key.startsWith(kw):
                combined.add(key)
    combined.sort()
    result = combined.deduplicate(isSorted = true)

proc getRSSItemKeys*(keyword: string = ""): seq[string] =
    let kw = toLower(keyword)
    var combined: seq[string]
    for indexName in @["category", "topic", "keywords"]:
        var global = fmt"^RSSItem{indexName.toUpper}"
        for key  in OrderItr @global(kw, ""):
            combined.add(key)
    combined.sort()
    result = combined.deduplicate(isSorted = true)

proc showRSS*(keys: string) =
    let key = if keys.contains(","): keys.split(",")[0] else: keys
    
    let items = @["id", "title", "description", "language", "link", "pubDate", "lastBuildDate", "copyright", "description", "generator"]
    for item in items:
        let gbl = fmt"^RSS({key}, {item})"
        let val = Get @gbl
        echo fmt"{item:>12}: {val}"

proc showRSSItem*(keys: string) =
    var gbl = fmt"^RSSItem({keys},title)"
    let title = Get @gbl
    gbl = fmt"^RSSItem({keys},description)"
    let description = Get @gbl
    gbl = fmt"^RSSItem({keys},pubDate)"
    let pubDate = Get @gbl.int
    gbl = fmt"^RSSItem({keys},idxref)"
    let idxref = Get @gbl
    echo title
    let umbruch = description.wrapWords(maxLineWidth = 74).indent(5)
    if umbruch.len > 5:
        echo umbruch

    # Show feed info
    let rssid = keys.split(',')[0]
    let dta = Data ^RSS(rssid)
    if dta == 0:
        echo "RSS entry ", rssid, " not found!"
        return

    let rss = loadObject[RSS](rssid)
    let feedTitle = if rss.title.isSome: rss.title.get else: ""
    echo fmt"     {feedTitle} {pubDate.fromUnix.local()} ({idxref})"
    echo ""


proc getLatestRSSItems*(max: int, feeds: seq[Feed]): seq[RSSItem] =
    var cnt = max
    var feedtable : seq[string]
    for feed in feeds:
        if feed.enabled:
            feedtable.add(feed.rssid)

    for key  in QueryItr ^RSSItemPUBDATE.reverse.keys:  # youngest first
        let idxKey = key[1]
        let feedId = Order ^RSSItemIDXREF(idxkey,"")
        if feedId in feedtable:
            let itemKey = idxKey.split(",")
            let rssItem = loadObject[RSSItem](itemKey)
            result.add(rssItem)
            dec cnt
            if cnt == 0: break


proc getLatestRSSItemKeys*(max: int): seq[string] =
    var cnt = max
    for key  in QueryItr ^RSSItemPUBDATE.reverse:
        let parts = key.split(',')
        let keys = parts[1] & "," & parts[2][0..^2]
        result.add(keys)
        dec cnt
        if cnt == 0: break


proc fullDump*(global: string) =
    let gbl = if global.startsWith("^"): global else: "^" & global
    for key, value in QueryItr @gbl.kv:
        #let rss = loadObject[RSS](key)
        echo key,"=",value
