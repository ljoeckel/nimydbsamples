import std/[options, strutils, strformat, typetraits, enumerate, os]
import std/[parseopt, httpclient, times, tables]
import rssatom
import nimrss
import wmWordcloud
import ydbhnsw
import hnsw_common


const
    DOCUMENTS = "DOCUMENTS"
    DOCUMENTS_SIZE = "DOCUMENTS_SIZE"

    Usage = """
        usage: <program> [option=value] [path]
            " -l[=n], --live[=n] : Get data from RSS feeds for one time"
            " -i[=n], --init[=n] : Load data from xml-files. (optional [n] items)"
            " -x <path>          : Load from the given xml-file."
            " --reset            : Kill all database globals"
            " -d --diag          : Run diagnostics"
            "<path>              : Path to file of RSS adresses"
        """

type
    AppOptions = object
            init: bool
            reset: bool
            diag: bool
            liveFeed: bool
            loadXml: bool
            maxItems: int
            minutes: int
            path: string = "feeds.rss"


var lastPubDate = 9999999999


proc getAppOptions(): AppOptions =
    result = AppOptions()

    for kind, key, val in getopt():
      case kind
      of cmdArgument:
        if not fileExists(key):
            echo fmt"Error: Missing file '{key}'"
            quit(1)
        result.path = key
        echo "Using ", result.path
      of cmdEnd: break
      of cmdShortOption, cmdLongOption:
        case toLowerAscii(key)
        of "init", "i":
            result.init = true
            result.maxItems = if val.len > 0: parseInt(val) else: 0
        of "live", "l":
            result.liveFeed = true
            try:
                result.minutes = parseInt(val)
            except:
                echo "Invalid value for 'minutes'"
                quit(1)
        of "d", "diag":
            result.diag = true
        of "x":
            result.loadXml = true
        of "reset":
            result.reset = true
        of "help", "h": echo Usage
        else: discard


proc embedTitle(item: RSSItem): seq[float32] =
    let normalized = hnswNormalize(getOption(item.title))
    embedOne(normalized)


func getTokens(s: string): seq[string] =
    result = hnswNormalize(s).split(" ")

func getPubDate(item: RSSItem): int =
    let pd = getOption(item.pubDate)
    if pd.len > 0: 
        return parseInt(pd)

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


proc isDuplicate(ix: HnswIndex, item: RSSItem): bool =
    let title = hnswNormalize(getOption(item.title))
    let description = hnswNormalize(getOption(item.description))
    if getTokens(description).len < 2:
        echo "no meaningful description. Ignored:"
        echo "         title: ", title
        echo "   description: ", description
        return true

    let vec = embedTitle(item)
    let hits = ix.search(vec)

    let pubdate = getPubDate(item)
    #echo fromUnix(pubdate), " ", title

    for hit in hits:
        if title == getRssTitle(hit.id):
            echo "Duplicate found: ", hit.id, " ", getRssTitle(hit.id)
            return true
            
        let idxref = ix.lookup(hit.id)
        let rssItem = loadObject[RSSItem](idxref.split(","))
        let pd = getPubDate(rssItem)
        if pd > 0:
            let delta = abs(pd - pubdate)
            if delta < 86400 and hit.sim > 0.9:
                echo "title: ", title
                echo "       lookup: hit.id:", hit.id, " sim:", hit.sim, " time-delta:", delta, " idxref:", ix.lookup(hit.id)
                echo "       ", getOption(rssItem.title)
                echo "       ", getOption(rssItem.description)
                return true


proc processFeed(ix: HnswIndex, rss: var RSS): (int, int) =
    setPubDate(rss)
    let now = datetimeToUnix()

    # Collect new items
    var newItems: seq[RSSItem]
    var wordCount: int
    for cnt, item in enumerate(rss.items.mitems):
        let (guid, isNew) = getGUID(item)
        let pubDate = parseInt(getOption(item.pubDate))
        if pubDate > now:
            echo "Article ignored because in future: ", toDateTime(pubDate), " ", rss.title
            continue   # ignore articles in the future

        if isNew and not isDuplicate(ix, item): # New item
            item.guid = some(guid)
            newItems.add(item)

    if newItems.len > 0:
        # Create a new id for ^RSS, ^RSSItem, ... used in serialization
        let title = if isSome(rss.title): rss.title.get() else: rss.description.get()
        var normalizedChannelTitle = normalizeChannelTitle(title)
        let feedId = generateSHA1(normalizedChannelTitle)  # Feed-Title 'Deutschlandfunk' > ..
        let id = Increment ^RSSCNT("RSS")
        rss.id = some(fmt"{feedId},{id}")
        for cnt, item in enumerate(newItems.mitems):
            item.idxref = fmt"{id},{cnt}" # idxref="33,1"
            item.feedId = some(feedId)
            let pubDate = parseInt(getOption(item.pubDate))
            lastPubDate = min(lastPubDate, pubDate)

            # Add to HNSW Index
            let vec = embedTitle(item)
            let id = ix.add(vec, item.idxref)
            # Calculation for FTI BM25
            discard Increment ^RSSCNT(DOCUMENTS)
            let documentLen = (getOption(item.title)).len + (getOption(item.description)).len
            Set: ^RSSFTI(id, cnt, "len") = documentLen
            let totalSize = Get ^RSSCNT(DOCUMENTS_SIZE).int
            Set: ^RSSCNT(DOCUMENTS_SIZE) = totalSize + documentLen
        
        # replace items with newItems and save
        rss.items = newItems
        saveObject(id, rss)

        # create the FTI index
        wordCount = createFTI(rss)

    return (newItems.len, wordCount)


proc processFeeds(ix: HnswIndex, feedPath: string) =
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

            # Set languuge to the base language: en-gb -> en
            var language = getOption(rss.language)
            if language.contains("-"):
                rss.language = some(language.split("-")[0])

            let (nbrNewItms, wordCount) = processFeed(ix, rss)
            if nbrNewItms > 0:
                saveXmlFile(url, xml) # Save the XMl file
                echo fmt"    {nbrNewItms} new Items with {wordCount} index words."


proc processWordCloud() =
    var processed = createWordCloudForToday()
    echo fmt"Processed {processed} Articles for WordCloud"


proc loadFromXml(ix: HnswIndex, options: AppOptions) =
    echo "Loading from XML file ", options.path
    let xml = trim(readFile(options.path))
    var feed = parseRSS(xml)
    let (nbrNewItms, wordCount) = processFeed(ix, feed)
    if nbrNewItms > 0:
        echo "file:", options.path, " nbrNewItms=", nbrNewItms, " wordCount=", wordCount


proc getFeeds(ix: HnswIndex, options: AppOptions) =
    echo "Running Live-Feed"
    while true:
        # Get the pubDate of the oldest article in the database
        processFeeds(ix, options.path)
        # Process wordcloud
        var processed = createWordCloudForToday()
        echo fmt"Processed {processed} Articles for WordCloud"
        # update timestamps
        let minutes = options.minutes
        Set:
            ^Session("rsscollector", "lastRun") = dateTimeToUnix()
            ^Session("rsscollector", "nextRun") = datetimeToUnix() + 60 * minutes
        # update dbstats
        updateDBStats("clc")

        if options.minutes == 0: break
        echo "Sleep for ", minutes, " minutes"
        nimSleep(1000 * 60 * minutes) # sleep for minutes


proc initFromXml(ix: HnswIndex, options: AppOptions) =
    var maxItems = options.maxItems
    echo "Loading from 'xml' files"

    for file in directoryWalk("./xml"):
        if not toUpper(file).endsWith(".XML"): continue
        let xml = trim(readFile(file))
        var feed = parseRSS(xml)
        let (nbrNewItms, wordCount) = processFeed(ix, feed)
        if nbrNewItms > 0:
            echo "maxItems:", maxItems, " file:", file, " nbrNewItms=", nbrNewItms, " wordCount=", wordCount
            dec maxItems
            if maxItems == 0: break

    updateDBStats("clc")


proc runDiagnostics(ix: HnswIndex, options: AppOptions) =
    var emptyTitles, emptyDescription = 0
    var minTitleLen, minDescriptionLen, minTitleTokens, minDescriptionTokens = int.high
    var maxTitleLen, maxDescriptionLen, maxTitleTokens, maxDescriptionTokens = 0
    
    for rssKey in OrderItr ^RSSItem:
        for itemKey in OrderItr ^RSSItem(rssKey,""):
            let title = Get ^RSSItem(rssKey, itemKey, "title")
            let description = Get ^RSSItem(rssKey, itemKey, "description")
            if title.len == 0: inc emptyTitles
            if description.len == 0: inc emptyDescription
            if title.len > 0:
                minTitleLen = min(minTitleLen, title.len)
                maxTitleLen = max(maxTitleLen, title.len)
                let tokens = getTokens(title)
                minTitleTokens = min(minTitleTokens, tokens.len)
                maxTitleTokens = max(maxTitleTokens, tokens.len)
            if description.len > 0:
                minDescriptionLen = min(minDescriptionLen, description.len)
                maxDescriptionLen = max(maxDescriptionLen, description.len)
                let tokens = getTokens(description)
                minDescriptionTokens = min(minDescriptionTokens, tokens.len)
                maxDescriptionTokens = max(maxDescriptionTokens, tokens.len)

    echo "empty:        titles=", emptyTitles, ", description=" , emptyDescription
    echo "title:        min=", minTitleLen, " max:", maxTitleLen
    echo "title tokens: min=", minTitleTokens, " max:", maxTitleTokens
    echo "descr       : min=", minDescriptionLen, " max:", maxDescriptionLen
    echo "descr tokens: min=", minDescriptionTokens, " max:", maxDescriptionTokens


if isMainModule:
    var appOpts = getAppOptions()
    var hnswOpts = getHnswParams()
    let ix = openHnsw(hnswOpts)

    if appOpts.reset:
        clearRssDb()
        if hnswOpts.reset:
            dropIndex(hnswOpts)
            quit(0)
    elif appOpts.diag:
        runDiagnostics(ix, appOpts)
    elif appOpts.loadXml:
        loadFromXml(ix, appOpts)
    elif appOpts.liveFeed:
        getFeeds(ix, appOpts)
    elif appOpts.init:
        initFromXml(ix, appOpts)