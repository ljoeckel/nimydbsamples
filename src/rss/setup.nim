import std/[options, strutils, strformat, typetraits, enumerate, os]
import std/[sha1, base64, parseopt, httpclient, times, tables]
import rssatom
import yottadb
import ydbutils
import searchlib
import types

proc getXmlFromUrl(url: string): string =
    let client = newHttpClient()
    defer: client.close()
    try:
        result = client.getContent(url)
    except:
        echo "ERROR with url ", url, " : ", getCurrentException().msg



proc clearDB(): int =
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
    echo "All RSS globals killed"
    0


proc setupFeeds(path: string): int =
    let feedPath = if path.len == 0: "feeds.rss" else: path
    if not fileExists(feedPath):
        echo fmt"Error: Missing configuration file '{feedPath}'"
        return 1

    let feeds = getRSSFeedConfiguration(feedPath) #: Table[string, seq[string]] =
    # Main entry point for the RSS Feed application (Collector)
    for group, urls in feeds.pairs:
        if group.len == 0: continue
        for url in urls:
            echo "Group: ", group, " url: ", url
            let xml = getXmlFromUrl(url)
            if xml.len == 0: continue

            let rss = parseRSS(xml)
            var feed: ConfigFeed 
            feed.title = normalizeChannelTitle(getOption(rss.title))
            feed.description = getOption(rss.description)
            feed.rssid = generateSHA1(feed.title)
            feed.group = group
            feed.enabled = true

            if feed.title.len > 0:
                saveObject[ConfigFeed](feed.rssid, feed)
    0



if isMainModule:
    type
        Command = enum 
            Help, SetupFeed, KillDB

    var feedPath: string = "feeds.rss"
    var command: Command

    var p = initOptParser()
    for kind, key, val in p.getopt():
        case kind
        of cmdArgument: feedPath = key
        of cmdLongOption, cmdShortOption:
            if key == "h": command = Help
            if key == "f": command = SetupFeed
            if key == "k": command = KillDB
        # Ende der Eingabe
        of cmdEnd: assert(false)
    
    if command == KillDB:
        quit(clearDB())
    elif command == SetupFeed:
        quit(setupFeeds(feedPath))
    elif command == Help:
        echo "-f  : Load RSS feeds from <feeds.rss>"
        echo "-k  : Kill all RSS globals in the database"
    

# if isMainModule:
#     let feeds = getRSSFeedConfiguration()
#     # In Sequenz umwandeln
#     var sortedPairs = collect(newSeq):
#         for k, v in feeds.pairs: (k, v)
#     # Nach dem ersten Element (dem Key) sortieren
#     sortedPairs.sort((a, b) => cmp(a[0], b[0]))
#     for (section, urls) in sortedPairs:
#         echo section, "=", urls
