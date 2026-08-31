import std/[os, times, json, strutils, strformat, math, tables, base64]
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


func hrb*(bytes: int): string =
    # return number of bytes as b/k/m/g
    if bytes < 1024:     return $bytes & "b"
    elif bytes < 1024^2: return $(bytes div 1024) & "k"
    elif bytes < 1024^3: return $(bytes div 1024^2) & "m"
    elif bytes < 1024^4: return $(bytes div 1024^3) & "g"
    elif bytes < 1024^5: return $(bytes div 1024^4) & "t"


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
        ("\n", ""),
        ("<img ", "<img loading='lazy' "),
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


proc getCurrentDay*(ts: int): string =
    let dt = fromUnix(ts).local
    dt.format("yyyy-MM-dd")


proc toDateTime*(ts: int): string =
    let dt = fromUnix(ts).local
    dt.format("yyyy-MM-dd HH:mm:ss")


proc fromISO8601*(dt: string): DateTime =
    # comes from webclient as 'yyyy-MM-ddTHH:mm'
    let ss = dt.split("T")
    result = parse(fmt"{ss[0]} {ss[1]}", "yyyy-MM-dd HH:mm")


proc calcTimeForSecond*(ts: int, second: int): int =
    let dt = fromUnix(ts).local
    let endDay = (dt + seconds(second)).local()
    dateTime(endDay.year, endDay.month, endDay.monthday, endDay.hour, endDay.minute, endDay.second, 999_000_000).toTime().toUnix()

proc calcTimeForMinute*(ts: int, minute: int): int =
    let dt = fromUnix(ts).local
    let endDay = (dt + minutes(minute)).local()
    dateTime(endDay.year, endDay.month, endDay.monthday, endDay.hour, endDay.minute, 59, 999_000_000).toTime().toUnix()

proc calcTimeForHour*(ts: int, hour: int): int =
    let dt = fromUnix(ts).local
    let endDay = (dt + hours(hour)).local()
    dateTime(endDay.year, endDay.month, endDay.monthday, endDay.hour, 59, 59, 999_000_000).toTime().toUnix()

proc calcTimeForDay*(ts: int, day: int): int =
    let dt = fromUnix(ts).local
    let endDay = (dt + days(day)).local()
    dateTime(endDay.year, endDay.month, endDay.monthday, 23, 59, 59, 999_000_000).toTime().toUnix()

proc calcTimeForMonth*(ts: int, month: int): int =
    let dt = fromUnix(ts).local
    let endDay = (dt + months(month)).local()
    let lastDay = getDaysInMonth(endDay.month, endDay.year)
    dateTime(endDay.year, endDay.month, lastDay, 23, 59, 59, 999_000_000).toTime().toUnix()


proc minuteFromTo*(dt: DateTime = now()): (int, int) =
    let startTime = dateTime(dt.year, dt.month, dt.monthday, dt.hour, dt.minute, 0, 0).toTime()
    let endTime = dateTime(dt.year, dt.month, dt.monthday, dt.hour, dt.minute, 59, 999_000_000).toTime()
    return (startTime.local().toTime().toUnix(), endTime.local().toTime().toUnix())

proc hourFromTo*(dt: DateTime = now()): (int, int) =
    let startTime = dateTime(dt.year, dt.month, dt.monthday, dt.hour, 0, 0, 0).toTime()
    let endTime = dateTime(dt.year, dt.month, dt.monthday, dt.hour, 59, 59, 999_000_000).toTime()
    return (startTime.local().toTime().toUnix(), endTime.local().toTime().toUnix())

proc dayFromTo*(dt: DateTime = now()): (int, int) =
    let startTime = dateTime(dt.year, dt.month, dt.monthday, 0, 0, 0, 0).toTime()
    let endTime = dateTime(dt.year, dt.month, dt.monthday, 23, 59, 59, 999_000_000).toTime()
    return (startTime.local().toTime().toUnix(),  endTime.local().toTime().toUnix())

proc weekFromTo*(dt: DateTime = now()): (int, int) =
    let daysFromStart = ord(dt.weekday)
    let daysUntilEnd = 6 - daysFromStart
    let startDay = dt - days(daysFromStart)
    let endDay = dt + days(daysUntilEnd)
    let startTime = dateTime(startDay.year, startDay.month, startDay.monthday, 0, 0, 0, 0).toTime()
    let endTime = dateTime(endDay.year, endDay.month, endDay.monthday, 23, 59, 59, 999_000_000).toTime()
    return (startTime.local().toTime().toUnix(), endTime.local().toTime().toUnix())

proc monthFromTo*(dt: DateTime = now()): (int, int) =
    let lastDay = getDaysInMonth(dt.month, dt.year)
    let startTime = dateTime(dt.year, dt.month, 1, 0, 0, 0, 0).toTime()
    let endTime = dateTime(dt.year, dt.month, lastDay, 23, 59, 59, 999_000_000).toTime()
    return (startTime.local().toTime().toUnix(),  endTime.local().toTime().toUnix())

proc yearFromTo*(dt: DateTime = now()): (int, int) =
    #let (startDt, endDt) = getYearBounds(dt)
    let startTime = dateTime(dt.year, mJan, 1, 0, 0, 0, 0).toTime()
    let endTime = dateTime(dt.year, mDec, 31, 23, 59, 59, 999_000_000).toTime()
    return (startTime.local().toTime().toUnix(),  endTime.local().toTime().toUnix())


proc datetimeToUnix*(): int =
    let tm = now().toTime()
    result = tm.toUnix()


proc getFirstPubDate*(): int =
    let now = datetimeToUnix()
    for keys in QueryItr ^RSSItemPUBDATE.reverse.keys:
        result = parseInt(keys[0])
        if result > now: continue
        break


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
