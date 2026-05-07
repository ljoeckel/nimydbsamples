import std/[options, strutils, strformat, typetraits, enumerate, os]
import std/[parseopt, httpclient, times, tables]
import rssatom
import nimrss

const
    DOCUMENTS = "DOCUMENTS"
    DOCUMENTS_SIZE = "DOCUMENTS_SIZE"



proc getGUID(item: RSSItem): (string, bool) =
    let guid = generateSHA1(getOption(item.title) & getOption(item.description), 32)
    let dta = Data ^RSSItemGUID(guid)
    return (guid, dta == 0)


proc getXmlFromUrl(url: string): string =
    let client = newHttpClient()
    defer: client.close()
    try:
        result = client.getContent(url)
        return trim(result)
    except:
        echo "ERROR with url ", url, " : ", getCurrentException().msg
        return

    
proc updateConfigFeed(rss: RSS, group: string) =
    var normalizedTitle = normalizeChannelTitle(getOption(rss.title))
    let sha = generateSHA1(normalizedTitle)  # Feed-Title 'Deutschlandfunk' > abckdkd93,d;-
    let dta = Data ^ConfigFeed(sha)
    if dta == 0:  # new feed
        var newFeed: ConfigFeed
        newFeed.rssid = sha
        newFeed.title = getOption(rss.title)
        newFeed.description = getOption(rss.description)
        newFeed.enabled = true
        newFeed.group = group
        newFeed.link = getOption(rss.link)
        saveObject[ConfigFeed](sha, newFeed)

        # Update the ^UsersFeeds
        for userid in OrderItr ^UserFeeds:
            var userFeeds = loadObject[UserFeeds](userid)
            userFeeds.feeds.add(newFeed)
            saveObject[UserFeeds](userid, userFeeds)


proc saveXmlFile(url: string, xml: string) =
    let nurl = generateSHA1(url)
    let xmlcount = datetimeToUnix()
    writeFile(fmt"./xml/{nurl}_{xmlcount}.xml", xml)


proc setPubDate(rss: var RSS) =
    # setup Dates for items and rss
    let ts = now().format("yyyy-MM-dd'T'HH:mm:sszzz")
    var opt: string
    for item in rss.items.mitems:
        opt = getOption(item.pubDate)
        if opt.len == 0: opt = getOption(rss.pubDate)
        let pubDate = if opt.len > 0: parseInt(getUnixTimestamp(opt)) else: parseInt(getUnixTimestamp(ts))
        opt = getOption(item.updated)
        let updated = if opt.len > 0: parseInt(getUnixTimestamp(opt)) else: 0
        item.pubDate = if updated > pubDate: some($updated) else: some($pubDate)
        item.updated = some($updated)

    opt = getOption(rss.pubDate)
    let pubDate = if opt.len > 0: parseInt(getUnixTimestamp(opt)) else: parseInt(getUnixTimestamp(ts))
    opt = getOption(rss.lastBuildDate)
    let updated = if opt.len > 0: parseInt(getUnixTimestamp(opt)) else: 0
    rss.pubDate = if updated > pubDate: some($updated) else: some($pubDate)
    rss.lastBuildDate = some($updated)


proc processFeed(rss: var RSS): (int, int) =
    setPubDate(rss)

    # Collect new items
    var newItems: seq[RSSItem]
    var wordCount: int
    for cnt, item in enumerate(rss.items.mitems):
        let (guid, isNew) = getGUID(item)
        if isNew: # New item
            item.guid = some(guid)
            newItems.add(item)

    if newItems.len > 0:
        # Create a new id for ^RSS, ^RSSItem, ... used in serialization
        var normalizedTitle = normalizeChannelTitle(rss.title.get())
        let feedId = generateSHA1(normalizedTitle)  # Feed-Title 'Deutschlandfunk' > abckdkd93,d;-
        let id = Increment ^RSSCNT("RSS")
        rss.id = some($feedId & "," & $id)
        for cnt, item in enumerate(newItems.mitems):
            item.idxref = fmt"{id},{cnt}" # idxref="33,1"
            item.feedId = some(feedId)
            # Calculation for FTI BM25
            discard Increment ^RSSCNT(DOCUMENTS)
            let documentLen = (getOption(item.title)).len + (getOption(item.description)).len
            Set: ^RSSFTI(id, cnt, "len") = documentLen
            let totalSize = Get ^RSSCNT(DOCUMENTS_SIZE).int
            Set: ^RSSCNT(DOCUMENTS_SIZE) = totalSize + documentLen

        
        # replace items with newItems and save
        rss.items = newItems
        saveObject(@[$id], rss)

        # create the FTI index
        wordCount = createFTI(rss)

    return (newItems.len, wordCount)


proc processFeeds(feedPath: string) =
    let feeds = getRSSFeedConfiguration(feedPath) #: Table[string, seq[string]] =
    # Main entry point for the RSS Feed application (Collector)
    for group, urls in feeds.pairs:
        if group.len == 0: continue
        echo fmt"Group {group}"
        for url in urls:
            echo fmt"  {url}"
            let xml = getXmlFromUrl(url)
            if xml.len == 0: continue
            var rss = parseRSS(xml)
            if not rss.link.isSome(): # No link found in RSS. Try Atom-Parser
                rss = parseAtom(xml)

            updateConfigFeed(rss, group) # create a ^ConfigFeed entry for new feeds

            let (nbrNewItms, wordCount) = processFeed(rss)
            if nbrNewItms > 0:
                saveXmlFile(url, xml) # Save the XMl file
                echo fmt"    {nbrNewItms} new Items with {wordCount} index words."


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
                echo " -x <xmlfile>.      : Load data from given xml-file." 
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
            if key == "x" and feedPath.len > 0:
                echo "Loading from ", feedPath
                let xml = trim(readFile(feedPath))
                var feed = parseRSS(xml)
                let (nbrNewItms, wordCount) = processFeed(feed)
                if nbrNewItms > 0:
                    echo "file:", feedPath, " nbrNewItms=", nbrNewItms, " wordCount=", wordCount
            if key == "k" or key == "kill":
                clearRssDb()
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
        for file in files:
            if not toUpper(file).endsWith(".XML"): continue
            let xml = trim(readFile(file))
            echo "file: ", file
            var feed = parseRSS(xml)
            let (nbrNewItms, wordCount) = processFeed(feed)
            if nbrNewItms > 0:
                echo "file:", file, " nbrNewItms=", nbrNewItms, " wordCount=", wordCount
                dec maxItems
                if maxItems == 0:
                    break
