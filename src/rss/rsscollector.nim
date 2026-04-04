import std/[options, strutils, strformat, typetraits, enumerate, os]
import std/[sha1, base64, parseopt, httpclient, times, tables]
import rssatom
import yottadb
import ydbutils
import searchlib


proc generateSHA1(input: string, length: int = 16): string =
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


proc getUnixTimestamp(dateStr: Option[string]): string =
  let dts = getOption(dateStr)
  if dts.len > 0:
    for f in TIME_FORMATS:
        try:
            let dt = parse(dts, f)
            return $dt.toTime().toUnix()
        except:
            continue
  
    raise newException(YdbError, "No matching timeformat found to create timestamp for '" & $dateStr)


proc getNewGUID(item: RSSItem): string =
    #let guid = normalizeGUID(item)
    let title = getOption(item.title) # = if item.title.isSome: item.title.get() else: ""
    let guidStr = getOption(item.guid) #if item.guid.isSome: item.guid.get() else: ""
    let guid = generateSHA1(title & guidStr, 32)
    let id = Query ^RSSItemGUID(guid)
    result = if id.len > 0 and id.find(guid) != -1: "" else: guid


proc getXmlFromUrl(url: string): string =
    let client = newHttpClient()
    defer: client.close()
    try:
        result = client.getContent(url)
    except:
        echo "ERROR with url ", url, " : ", getCurrentException().msg
        return


proc getXmlFromFile(path: string): string =
    result = strip(readFile(path))
    result = result.replace("\9","").replace("\n","")

    
proc saveXmlFile(url: string, xml: string) =
    let nurl = normalizeUrl(url)
    let xmlcount = Increment ^RSSCNT(nurl)
    writeFile(fmt"./xml/{nurl}_{xmlcount}.xml", xml)


proc processFeed(feed: var RSS): int =
    # process the feed. Returns the number of new entries
    # 1. Check if any new article found in feed
    var newArticles: bool
    for item in feed.items:
        if getNewGUID(item).len > 0:
            newArticles = true
            break
    if not newArticles: return 0

    # Collect new items
    var newItems: seq[RSSItem]
    for cnt, item in enumerate(feed.items.mitems):
        let guid = getNewGUID(item)
        if guid.len == 0: continue # Only new items will have a 'guid'

        # Update id for RSSItem's to build the indexes g.E. ^RSSItemGUID, ^RSSItemTOPIC etc. index
        item.guid = some(guid)
        item.pubDate = some(getUnixTimestamp(item.pubDate)) # create normalized timestamp
        # lowercase category / keywords / topic for search index
        for i in 0..<item.category.len:
            item.category[i] = toLower(item.category[i])
        for i in 0..<item.keywords.len:
            item.keywords[i] = tolower(item.keywords[i])
        if item.topic.isSome: item.topic = some(toLower(item.topic.get()))
        newItems.add(item)

    if newItems.len > 0:
        # Create a new id for ^RSS, ^RSSItem, ... used in serialization
        feed.title = normalizeChannelTitle(feed.title)
        let fid = getOption(feed.title)
        var feedId = Order ^RSSTITLE(fid,"")
        if feedId.len == 0:  # creaete new feedid if not used before
            feedId = $(Increment ^RSSCNT("FeedID"))
            Set: ^RSSTITLE(fid, feedId) = ""
        echo "feedTitle:", fid, " feedId=", feedId, " fid=", fid
        
        let id = Increment ^RSSCNT("RSS")
        feed.id = some($feedId & "," & $id)

        for cnt, item in enumerate(newItems.mitems):
            item.idxref = fmt"{id},{cnt}" # idxref="33,1"
            item.feedId = some(feedId)
        
        # replace items with newItems and save
        feed.items = newItems
        saveObject(@[$id], feed)
        
        # create a lookup index for Feed.title
        
        echo "Saved object id:", $id, " new articles:", feed.items.len, " feed.len=", ($feed).len

    return newItems.len


proc processFeeds(feedPath: string) =
    let feeds = getRSSFeedConfiguration() #: Table[string, seq[string]] =
    # Main entry point for the RSS Feed application (Collector)
    for section, urls in feeds.pairs:
        echo "Section ", section
        if section.len == 0: continue
        for url in urls:
            echo "Fetching ", url
            let xml = getXmlFromUrl(url)
            if xml.len == 0: continue

            var feed = parseRSS(xml)
            let nbrNewItms = processFeed(feed)
            if nbrNewItms > 0:
                saveXmlFile(url, xml) # Save the XMl file


proc clearDB() =
    Kill:
        ^Author
        ^Feed
        ^UserFeeds
        ^RSSCNT
        ^RSS
        ^RSSTITLE
        ^RSSEnclosure
        ^RSSImage
        ^RSSItem
        ^RSSItemGUID
        ^RSSItemCATEGORY
        ^RSSItemTOPIC
        ^RSSItemKEYWORDS
        ^RSSItemPUBDATE
        ^RSSItemIDXREF

if isMainModule:
    var init = false
    var minutes = 0
    var liveFeed = false
    var feedPath = "feeds.rss"
    var maxItems = 0

    var p = initOptParser()
    for kind, key, val in p.getopt():
        case kind
        # Ein normales Argument (z. B. "meinfile.txt")
        of cmdArgument:
            feedPath = key
            echo "Using ", feedPath
        of cmdLongOption, cmdShortOption:
            if key == "h" or key == "help":
                echo "rsscollector -l -i <feeds.rss>"
                echo " -l, --live         : Get data from RSS feeds for one time"
                echo " -l=n, --live=n     : Get data from RSS and repeat each 'n' minutes."
                echo " -i[=n], --init.    : Load data from xml-files. (optional [n] items)" 
                echo " -k, --kill.        : Kill all database globals"
                echo "<feeds.rss>.        : List of RSS adresses"
                quit(0)
            if key == "l" or key == "live": 
                liveFeed = true
                if val.len > 0:
                    try:
                        minutes = parseInt(val)
                    except:
                        echo "Invalid number of minutes"
                        quit(1)

            if key == "i" or key == "init": 
                init = true
                maxItems = if val.len > 0: parseInt(val) else: 0
            if key == "k" or key == "kill":
                echo "Kill all Globals"
                clearDB()
                quit(0)

        # Ende der Eingabe
        of cmdEnd: assert(false)
    
    # Test for configuration file
    if not fileExists(feedPath):
        echo fmt"Error: Missing configuration file '{feedPath}'"
        quit(0)
    
    if liveFeed:
        echo "Running Live-Feed"
        processFeeds(feedPath)
        while minutes > 0:
            echo "Sleep for ", minutes, " minutes"
            nimSleep(1000 * 60 * minutes) # sleep for minutes
            processFeeds(feedPath)
    
    elif init:
        echo "Loading from 'xml' files"
        let files = directoryWalk("./xml")
        for url in files:
            let xml = getXmlFromFile(url)
            var feed = parseRSS(xml)
            let nbrNewItms = processFeed(feed)
            if nbrNewItms > 0:
                echo "url:", url, " nbrNewItms=", nbrNewItms
                dec maxItems
                if maxItems == 0:
                    break