import std/strformat
import std/strutils
import std/wordwrap
import std/[algorithm, sequtils, tables]
import std/[options, strutils, strformat, typetraits]
import std/[times]
import rssatom
import yottadb
import ydbutils
import types

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


proc normalizeUrl*(url: string): string =
    result = url.multiReplace(
        ("https://", ""), ("rss", ""), ("www", ""),
        ("/", ""), (".", ""), ("-", ""), ("!", ""),
        (";", ""), ("_", "")
    )

proc normalizeChannelTitle*(title: string): string =
    result = title.toUpper
    # result = result.multiReplace(
    #     ("RSS CHANNEL", ""), 
    #     ("AKTUELLE", ""), ("WWW", ""), ("ONLINE", ""),
    #     ("TICKER", ""), ("SCHLAGZEILEN", ""), ("NEUIGKEITEN", ""), ("NEWS", ""),
    #     ("DIE", ""), ("DER", ""), ("IM", ""), ("VON",""), ("UND",""), ("AUS",""),
    #     ("  "," "), ("-", ""), (",", ""),
    #     ("SECTION", ""),
    # )
    while find(result,"  ") > 0:
        result = result.replace("  "," ")
    while result.len > 40:
        let pos = result.rfind(" ")
        if pos > 0:
            result = result[0..pos-1]
    return result.strip

proc normalizeChannelTitle*(title: Option[string]): Option[string] =
    if title.isSome: return some(normalizeChannelTitle(title.get())) else: title

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
    var rsss: seq[RSS]

    var feedtable : seq[string]
    for feed in feeds:
        if feed.enabled:
            feedtable.add(feed.rssid)

    for key  in QueryItr ^RSSItemPUBDATE.reverse.keys:  # youngest first
        let idxKey = key[1]
        let feedId = Order ^RSSItemIDXREF(idxkey,"")
        if feedId in feedtable:
            let verify = Data ^RSSItemIDXREF(idxkey, feedId)
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
