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

const mnemomics* = {
    "AFRA": "# of waits for instance freeze to release critical sections",
    "BREA": "# of waits for block read & decryption",
    "BTD": "# of database Block Transitions to Dirty",
    "BTS": "# of times a dirty buffer was flushed so a BT could be reused",
    "BUS": "# of times db_csh_get could not determine whether a block was in cache or not",
    "CAT": "Critical section Total Acquisitions successes",
    "CFE": "Critical section Failed (blocked) acquisition total caused by Epochs. It is incremented a single time for each observed instance of contention.",
    "CFS": "This mnemonic is not maintained and contains zeros.",
    "CFT": "Critical section Failed (blocked) acquisition Total. It is incremented a single time for each observed instance of contention.",
    "CQS": "This mnemonic is not maintained and contains zeros.",
    "CQT": "This is maintained only if MUTEX_TYPE is YDB or ADAPTIVE. It is not maintained and contains zeros if MUTEX_TYPE is PTHREAD. When maintained, this is the number of times a process did a queued sleep while waiting for the database critical section.",
    "CTN": "Current Transaction Number of the database for the last committed read-write transaction (TP and non-TP)",
    "CYS": "This mnemonic is not maintained and contains zeros.",
    "CYT": "This is maintained only if MUTEX_TYPE is YDB or ADAPTIVE. It is not maintained and contains zeros if MUTEX_TYPE is PTHREAD. When maintained, this is the number of times a process did a yield while waiting for the database critical section.",
    "DEX": "# of Database file EXtentions",
    "DEXA": "# of waits for database extension",
    "DFL": "# of Database FLushes of the entire set of dirty global buffers in shared memory to disk",
    "DFS": "# of times a process does an fsync of the database file.",
    "DRD": "# of Disk ReaDs from the database file (TP and non-TP, committed and rolled-back). This does not include reads that are satisfied by buffered globals for databases that use the BG (Buffered Global) access method. YottaDB always reports 0 for databases that use the MM (memory-mapped) access method as this has no real meaning in that mode.",
    "DTA": "# of DaTA operations (TP and non-TP)",
    "DWT": "# of Disk WriTes to the database file (TP and non-TP, committed and rolled-back). This does not include writes that are satisfied by buffered globals for databases that use the BG (Buffered Global) access method. YottaDB always reports 0 for databases that use the MM (memory-mapped) access method as this has no real meaning in that mode.",
    "GET": "# of GET operations (TP and non-TP)",
    "GLB": "# of waits for bg access critical section",
    "JBB": "# of Journal Buffer Bytes updated in shared memory",
    "JEX": "# of Journal file EXtentions",
    "JFB": "# of Journal File Bytes written to the journal file on disk. For performance reasons, YottaDB always aligns the beginning of these writes to file system block size boundaries. JFB counts all bytes including those needed for alignment in order to reflect the actual IO load on the journal file. Since the bytes required to achieve alignment may have already been counted as part of the previous JFB, processes may write the same bytes more than once, causing the JFB counter to typically be higher than JBB.",
    "JFL": "# of Journal FLushes of all dirty journal buffers in shared memory to disk. For example: when switching journal files etc.",
    "JFS": "# of Journal FSync operations on the journal file. For example: when writing an epoch record, switching a journal file etc.",
    "JFW": "# of Journal File Write system calls",
    "JNL": "# of waits for journal access critical section",
    "JOPA": "# of waits for journal open critical section",
    "JRE": "# of Journal Regular Epoch records written to the journal file (only seen in a -detail journal extract). These are written every time an epoch-interval boundary is crossed while processing updates.",
    "JRI": "# of JouRnal Idle epoch journal records written to the journal file (only seen in a -detail journal extract). These are written when a burst of updates is followed by an idle period, around 5 seconds of no updates after the database flush timer has flushed all dirty global buffers to the database file on disk.",
    "JRL": "# of Journal Records with a Logical record type (e.g. SET, KILL etc.) written to the journal file",
    "JRO": "# of Journal Records with a type Other than logical written to the journal file (e.g. AIMG, EPOCH, PBLK, PFIN, PINI, and so on)",
    "JRP": "# of Journal Records with a Physical record type (i.e. PBLK, AIMG) written to the journal file (these records are seen only in a -detail journal extract)",
    "KIL": "# of KILl operations (kill as well as zwithdraw, TP and non-TP)",
    "KTG": "# of invoked KILL triggers",
    "LKF": "# of LocK calls (mapped to this db) that Failed",
    "LKS": "# of LocK calls (mapped to this db) that Succeeded",
    "MLBA": "# of waits for blocked LOCK",
    "MLK": "# of waits for LOCK access",
    "NBR": "# of Non-tp committed transaction induced Block Reads on this database",
    "NBW": "# of Non-tp committed transaction induced Block Writes on this database",
    "NR0": "# of Non-tp transaction Restarts at try 0",
    "NR1": "# of Non-tp transaction Restarts at try 1",
    "NR2": "# of Non-tp transaction Restarts at try 2",
    "NR3": "# of Non-tp transaction Restarts at try 3",
    "NTR": "# of Non-tp committed Transactions that were Read-only on this database",
    "NTW": "# of Non-tp committed Transactions that were read-Write on this database",
    "ORD": "# of $ORDer(,1) (forward) operations (TP and non-TP); the count of $Order(,-1) operations are reported under ZPR.",
    "PRC": "# of waits on exit",
    "PRG": "# of pre-read globals that were performed by the reader helper",
    "QRY": "# of $QueRY() operations (TP and non-TP)",
    "SET": "# of SET operations (TP and non-TP)",
    "STG": "# of invoked SET triggers",
    "TBR": "# of Tp transaction induced Block Reads on this database",
    "TBW": "# of Tp transaction induced Block Writes on this database",
    "TC0": "# of Tp transaction Conflicts at try 0 (counted only for that region which caused the TP transaction restart)",
    "TC1": "# of Tp transaction Conflicts at try 1 (counted only for that region which caused the TP transaction restart)",
    "TC2": "# of Tp transaction Conflicts at try 2 (counted only for that region which caused the TP transaction restart)",
    "TC3": "# of Tp transaction Conflicts at try 3 (counted only for that region which caused the TP transaction restart)",
    "TC4": "# of Tp transaction Conflicts at try 4 and above (counted only for that region which caused the TP transaction restart)",
    "TR0": "# of Tp transaction Restarts at try 0 (counted for all regions participating in restarting TP transaction)",
    "TR1": "# of Tp transaction Restarts at try 1 (counted for all regions participating in restarting TP transaction)",
    "TR2": "# of Tp transaction Restarts at try 2 (counted for all regions participating in restarting TP transaction)",
    "TR3": "# of Tp transaction Restarts at try 3 (counted for all regions participating in restarting TP transaction)",
    "TR4": "# of Tp transaction Restarts at try 4 and above (restart counted for all regions participating in restarting TP transaction)",
    "TRB": "# of Tp read-only or read-write transactions Rolled Back (excluding incremental rollbacks)",
    "TRGA": "# of mini-transaction completion",
    "TRX": "# of waits for transaction in progress",
    "TTR": "# of Tp committed Transactions that were Read-only on this database",
    "TTW": "# of Tp committed Transactions that were read-Write on this database",
    "WFL": "# of database flushes that were performed by the writer helpers",
    "WFR": "# of times a process slept while waiting for another process to read in a database block",
    "WHE": "# of writer helper epochs",
    "WRL": "# of times a process consistently slept (longer than WFR) while waiting for another process to read in a database block",
    "ZAD": "# of waits for region freeze off",
    "ZPR": "# of $order(,-1) or $ZPRevious() (reverse order) operations (TP and non-TP). The count of $Order(,1) operations are reported under ORD.",
    "ZTG": "# of invoked ZTRIGGERs",
    "ZTR": "# of ZTRigger command operations"
}.toTable



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


proc handleGoto*(req: Request) =
    # process menu links g.E. <a href="#form" data-on:click="$menuOpen = false; @post('goto/form.html')">Registration</a>
    let page = req.path.split("/goto/")[1]
    SSE(req):
        forward(sse, HTML_DIR & page)


proc getCurrentDay*(datetime: int): string =
    let timeObj = fromUnix(datetime)
    let dt = timeObj.local
    dt.format("yyyy-MM-dd")


proc toDateTime*(datetime: int): string =
    let timeObj = fromUnix(datetime)
    let dt = timeObj.local
    dt.format("yyyy-MM-dd HH:mm:ss")


proc getCurrentDayBounds(dt: DateTime): (DateTime, DateTime) =
  let startOfDay = dateTime(dt.year, dt.month, dt.monthday, 0, 0, 0, 0).toTime()
  let endOfDay = dateTime(dt.year, dt.month, dt.monthday, 23, 59, 59, 999_000_000).toTime()
  return (startOfDay.local(), endOfDay.local())


proc getCurrentHourBounds(dt: DateTime): (DateTime, DateTime) =
  let startOfHour = dateTime(dt.year, dt.month, dt.monthday, dt.hour, 0, 0, 0).toTime()
  let endOfHour = dateTime(dt.year, dt.month, dt.monthday, dt.hour, 59, 59, 999_000_000).toTime()
  return (startOfHour.local(), endOfHour.local())


proc getWeekBounds(dt: DateTime): (DateTime, DateTime) =
  let daysFromStart = ord(dt.weekday)
  let daysUntilEnd = 6 - daysFromStart
  let startDay = dt - days(daysFromStart)
  let endDay = dt + days(daysUntilEnd)
  let startOfWeekRaw = dateTime(startDay.year, startDay.month, startDay.monthday, 0, 0, 0, 0).toTime()
  let endOfWeekRaw = dateTime(endDay.year, endDay.month, endDay.monthday, 23, 59, 59, 999_000_000).toTime()
  return (startOfWeekRaw.local(), endOfWeekRaw.local())


proc getMonthBounds(dt: DateTime): (DateTime, DateTime) =
  let lastDay = getDaysInMonth(dt.month, dt.year)
  let startOfMonthRaw = dateTime(dt.year, dt.month, 1, 0, 0, 0, 0).toTime()
  let endOfMonthRaw = dateTime(dt.year, dt.month, lastDay, 23, 59, 59, 999_000_000).toTime()
  return (startOfMonthRaw.local(), endOfMonthRaw.local())


proc getYearBounds(dt: DateTime): (DateTime, DateTime) =
  let startOfYearRaw = dateTime(dt.year, mJan, 1, 0, 0, 0, 0).toTime()
  let endOfYearRaw = dateTime(dt.year, mDec, 31, 23, 59, 59, 999_000_000).toTime()
  return (startOfYearRaw.local(), endOfYearRaw.local())


proc currentHourFromTo*(): (int, int) =
    let dt = now()
    let (startDt, endDt) = getCurrentHourBounds(dt)
    return (startDt.toTime().toUnix(),  endDt.toTime().toUnix())

proc currentDayFromTo*(): (int, int) =
    let dt = now()
    let (startDt, endDt) = getCurrentDayBounds(dt)
    return (startDt.toTime().toUnix(),  endDt.toTime().toUnix())


proc currentWeekFromTo*(): (int, int) =
    let dt = now()
    let (startDt, endDt) = getWeekBounds(dt)
    return (startDt.toTime().toUnix(),  endDt.toTime().toUnix())


proc currentMonthFromTo*(): (int, int) =
    let dt = now()
    let (startDt, endDt) = getMonthBounds(dt)
    return (startDt.toTime().toUnix(),  endDt.toTime().toUnix())


proc currentYearFromTo*(): (int, int) =
    let dt = now()
    let (startDt, endDt) = getYearBounds(dt)
    return (startDt.toTime().toUnix(),  endDt.toTime().toUnix())


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

proc updateDBStats*(domainKey: string) =
    let now = datetimeToUnix()
    echo "updateDBStats key=", domainKey, " now=", now
    ydb_ci: "xzshow"
    for (key, value) in QueryItr RESULT("G",0).kv:
        let fields = value.split(",")
        for field in fields:
            let parts = field.split(":")
            let mnemonic = parts[0]
            if mnemonic in mnemomics:
                let value = parseInt(parts[1]) # cummulated value
                if value > 0:
                    Set: ^DBStatsDetail(mnemonic, now, domainKey) = value

                let lastValue = Get ^DBSTATS(mnemonic).int
                let delta = abs(lastValue - value)
                if value > 0:
                    Set: 
                        ^DBSTATS(mnemonic) = value
                        ^DBSTATS(mnemonic, "delta") = delta


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
