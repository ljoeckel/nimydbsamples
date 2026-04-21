import std/strformat
import std/wordwrap
import std/[algorithm, hashes, sets, tables]
import std/[options, strutils, typetraits]
import std/[sha1, base64, httpclient, times]
import rssatom
import yottadb
import stemmer
import types
import sugar


const TIME_FORMATS* = [
    "yyyy-MM-dd'T'HH:mm:sszzz",
    "ddd, d MMM yyyy HH:mm:ss ZZZ",
    "ddd, d MMM yyyy HH:mm:ss 'GMT'",
    "ddd, d MMM yyyy HH:mm:ss 'UTC'",
    "ddd, d MMM yyyy HH:mm:ss 'EDT'",
    "d MMM yyyy HH:mm:ss ZZZ",
    "ddd, dd MMM yyyy HH:mm 'GMT'" # Thu, 09 Apr 2026 12:57 GMT
  ]

proc trim(s: string): string =
    # remove all leading, trailing and double spaces from a string " abc  def " -> "abc def"
    result = strip(s)
    var idx = result.find("  ")
    while idx > 0:
        result = result.replace("  ", " ")
        idx = result.find("  ")


proc getUnixTimestamp*(dts: string): string =
  if dts.len > 0:
    for f in TIME_FORMATS:
        try:
            let dt = parse(dts, f)
            return $dt.toTime().toUnix()
        except:
            continue
  
    raise newException(YdbError, "No matching timeformat found to create timestamp for '" & $dts)


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

proc getWordCountFromFTI(word: string, subscript: seq[string]): int =
    let s0 = subscript[0]
    let s1 = subscript[1]
    result = Get ^RSSItemFTI(word, s0, s1).int
    #TODO: Allow 1. Get ^RSSItemFTI(word, subscript)
    #TODO: Allow 2. Get ^RSSItemFTI(word, subscript[0], subscript[1])


# ========= Overwrites for HashTable[TimeSearchEntry] ========

# Nur 'subscript' für den Vergleich nutzen
proc `==`*(a, b: TimeSearchEntry): bool =
  a.subscript == b.subscript

# Nur 'subscript' für den Hash nutzen
proc hash*(x: TimeSearchEntry): Hash =
  var h: Hash = 0
  h = h !& hash(x.subscript)
  result = !$h

template append(result: var HashSet[TimeSearchEntry], keyword: string, wc: int, item: TimeSearchEntry) =
    var itm = item
    inc(itm.wordCount, getWordCountFromFTI(keyword, item.subscript) + wc)
    incl(result, itm)

proc intersect(keyword: string, s1: var HashSet[TimeSearchEntry], s2: var HashSet[TimeSearchEntry]): HashSet[TimeSearchEntry] =
    #var itm: TimeSearchEntry
    if s1.len == 0:
        for item in s2:
            let wc = s2[item].wordCount
            result.append(keyword, wc, item)
    elif s2.len == 0:
        for item in s1: 
            let wc = s1[item].wordCount
            result.append(keyword, wc, item)
    elif s1.len < s2.len:
        for item in s1:
            if item in s2: 
                let wc = s2[item].wordCount
                result.append(keyword, wc, item)
    else:
        for item in s2:
            if item in s1: 
                let wc = s1[item].wordCount
                result.append(keyword, wc, item)

proc sortFTIResult*(data: var seq[TimeSearchEntry], sortBy: SortBy) =
    case sortBy
    of ByTodayAscending, ByTimeAscending:
        data.sort((x, y) => cmp(x.time, y.time))
    of ByTodayDescending, ByTimeDescending:
        data.sort((x, y) => cmp(y.time, x.time))
    of ByRelevanceAscending:
        data.sort do (x, y: TimeSearchEntry) -> int:
            var res: int
            res = cmp(x.wordCount, y.wordCount) # sort by wordCount
            if res == 0:
                res = cmp(x.time, y.time) # by 'time' if 'wordCont' is 0 (equal)
            return res
    of ByRelevanceDescending:
        data.sort do (x, y: TimeSearchEntry) -> int:
            var res: int
            res = cmp(y.wordCount, x.wordCount) # sort by wordCount
            if res == 0:
                res = cmp(y.time, x.time) # by 'time' if 'wordCont' is 0 (equal)
            return res


proc getFTI*(keyword: string, lang: string, userid: string): seq[TimeSearchEntry] =
    # Search Full Text Index
    if keyword.isEmptyOrWhitespace or keyword.len < MIN_KEYWORD_LEN: 
        return # check minimum length of keywords

    # Get enabled feeds
    let userFeeds = loadObject[UserFeeds](userid)
    var feedtable : seq[string]
    for feed in userFeeds.feeds:
        if feed.enabled:
            feedtable.add(feed.rssid)

    # resultTable holds for each search word a sequence of TimeSearchEntry
    var resultTable = initTable[string, seq[TimeSearchEntry]]()
    # Find entries for each search word
    for kw in split(toLower(trim(keyword))," "):
        var items: seq[TimeSearchEntry]
        let stemword = stem(kw, lang)
        for keys in QueryItr ^RSSItemFTI(stemword).keys:
            if not keys[0].startsWith(stemword): break
            # check if item is in active feed
            let feedId = Order ^RSSItemIDXREF(keys[1] & "," & keys[2] ,"")
            if feedId in feedtable:
                items.add(TimeSearchEntry(subscript: @[keys[1], keys[2] ]))
        # save found items under stemword
        resultTable[stemword] = items

    # Find TimeSearchEntry's which are in all resultTables
    var common: HashSet[TimeSearchEntry]
    for key in resultTable.keys:
        var s2 = resultTable[key].toHashSet
        common = intersect(key, common, s2)

    #echo fmt"Found {common.len} entries for '{kws}'"
    # Update TimeSearchEntry with pubDate
    for entry in common:
        var sr = entry
        let subscript = entry.subscript
        sr.time = Get ^RSSItem(subscript, "pubDate").int # get time from DB
        result.add(sr)

   
    # Sort result Descending by-pubdate: compare y with x
    # if sortOrder == byTime:
    #     result.sort((x, y) => cmp(y.time, x.time))
    # else:
    #     result.sort((x, y) => cmp(y.wordCount, x.wordCount))

    # result.sort do (x, y: TimeSearchEntry) -> int:
    #     var res: int
    #     # sort by wordCount
    #     res = cmp(y.wordCount, x.wordCount)
    #     # sort additionally by 'time' if 'wordCont' is 0 (equal)
    #     if res == 0:
    #         res = cmp(y.time, x.time)
    #     return res

    # # Reduce result to max_search_results
    # let maxresults = min(result.len, MAX_SEARCH_RESULTS)-1
    # return result[0..maxresults]
        

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


proc clearFeedsDb*() =
    Kill:
        ^ConfigFeed
        ^Feed
        ^UserFeeds
    echo "Feed related globals killed"

proc clearRssDb*() =
    Kill:
        ^Author
        ^RSSCNT
        ^RSS
        ^RSSTITLE
        ^RSSEnclosure
        ^RSSImage
        ^RSSItem
        ^RSSItemGUID
        ^RSSItemCATEGORY
        ^RSSItemPUBDATE
        ^RSSItemIDXREF
        ^RSSFTI
        ^RSSItemFTI
        ^ConfigFeed
        ^Feed
        ^UserFeeds
    echo "RSS Globals killed"
