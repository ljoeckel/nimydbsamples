import std/[os, times, json, strutils, strformat, tables, base64]
import std/[options, typetraits]
import std/[httpclient]
import checksums/sha1
import mummy, mummy/routers, mummy/datastar
import macros
import yottadb
import types


const
    MAXNEWS* = 100 # How many news to show in 'latest'
    HTML_DIR* = "html/"
    USERID* = "userid"


template meassure*(body: untyped): auto =
    let t0 = getTime()
    body
    let td = (getTime() - t0).inMicroseconds
    if td > 1000: $(td div 1000) & " ms."
    else: $td & " µs."


template getOption*(option: Option): string =
    if option.isSome: option.get() else: ""


proc generateSHA1*(input: string, length: int = 20): string =
  let maxlen = min(input.len, 2048) # only the first 2048 bytes
  var hash: SecureHash
  if input.len > maxlen:
    hash = secureHash(input[0..maxlen-1]) # calculate SHA1 
  else:
    hash = secureHash(input)
  let bytes = cast[array[20, byte]](hash) # convert distinct type to byte array
  # 3. Bytes in einen String für den Encoder umwandeln
  var rawData = ""
  for b in bytes: 
    rawData.add(char(b))
  # 4. Base64-Encoding (URL-safe)
  let b64 = encode(rawData, safe = true)
  # 5. Kürzen auf die gewünschte Länge
  return b64[0 ..< min(length, b64.len)]


proc trim*(s: string): string =
    # remove all leading, trailing and double spaces from a string " abc  def " -> "abc def"
    result = strip(s)
    var idx = result.find("  ")
    while idx > 0:
        result = result.replace("  ", " ")
        idx = result.find("  ")
    
    result = result.multiReplace(
        ("&lt;strong&gt;", " "), ("&lt;/strong&gt;", ""),
    )


func fastParseInt*(s: string): int {.inline.} =
  ## scan a string for positive numbers
  ## Return 0 if no numbers
  result = 0
  for i in 0 ..< s.len:
    let c = s[i]
    if c in '0'..'9':
      result = result * 10 + (ord(c) - ord('0'))
    else:
      break # Stopp at first non numeric character


func stripSignal*(signal: string): string =
    result = strip(signal)
    if result.startsWith("\"") and result.endsWith("\""): # Remove "xxxx" -> xxxx
        result = result[1..^2]


proc patch*(sse: SSEConnection, signals: JsonNode) =
    let dsSignals = getSignals(sse)
    let userid = if USERID in dsSignals: dsSignals[USERID].getStr() else: ""

    patchSignals(sse, signals)
    for key in signals.keys:
        Set: ^Session(userid, key) = stripSignal($signals[key])


proc getSignal*(userid: string, key: string): string =
    result = Get ^Session(userid, key)


proc getSignals*(userid: string): seq[(string, string)] =
    for k,v in OrderItr ^Session(userid,"").kv:
        result.add((k,v))


proc getSignal*(req: Request, key: string): string = 
    let signals = getSignals(req)
    let userid = if USERID in signals: stripSignal($signals[USERID]) else: ""
    for k, v in signals.pairs:
        Set: ^Session(userid, k) = stripSignal($v)
    getSignal(userid, key)


proc handleGoto*(req: Request) =
    # process menu links g.E. <a href="#form" data-on:click="$menuOpen = false; @get('goto/form.html')">Registration</a>
    let page = req.path.split("/goto/")[1]
    SSE(req):
        forward(sse, HTML_DIR & page)


proc getCurrentDay*(datetime: int): string =
    let timeObj = fromUnix(datetime)
    let dt = timeObj.local
    result = dt.format("yyyy-MM-dd")


proc currentDayFromTo*(): (int, int) =
    # Get time range for the current day    
    let date = getDateStr(now())
    let dt1 = parse(date & " 00:00:00", "yyyy-MM-dd HH:mm:ss")
    let dt2 = parse(date & " 23:59:59", "yyyy-MM-dd HH:mm:ss")
    return (dt1.toTime().toUnix(),  dt2.toTime().toUnix())


proc datetimeToUnix*(): int =
    let tm = now().toTime()
    result = tm.toUnix()

    
proc getWallClock*(): string =
    result = now().format("dd.MM.yyyy - HH:mm")


proc getEnabledFeeds*(userid: string): seq[string] =
    let userFeeds = loadObject[UserFeeds](userid)
    for feed in userFeeds.feeds:
        if feed.enabled:
            result.add(feed.rssid)


proc clearFeedsDb*() =
    Kill:
        ^ConfigFeed
        ^Feed
        ^UserFeeds
    echo "Feed related globals killed"


proc clearRssDb*() =
    Kill:
        ^Author
        ^DBStats
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
