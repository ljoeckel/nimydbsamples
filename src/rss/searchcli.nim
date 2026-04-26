import std/[algorithm, sequtils]
import std/[options, wordwrap, strutils, strformat, typetraits]
import std/[base64, parseopt, httpclient, times]
import nimrss
import std/tables
import checksums/sha1


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

        
proc search(lang: string = "DE", userid: string = "ljoeckel") =
    while true:
        stdout.write("Search for: ")
        stdout.flushFile()
        var searchFor = readLine(stdin)
        if searchFor == "": quit(0)

        timed:
            let results = getFTI(searchFor, lang, userid, SortBy.ByTimeDescending)
            for tse in results:
                showRSSItem(tse.subscript[0] & "," & tse.subscript[1])
        echo fmt"Found {results.len} results"


proc showLatest(max: int) =
    for key in getLatestRSSItemKeys(max):
        showRSSItem(key)


proc dumpFTI(start: string) = 
    var wt = initCountTable[string]()    
    for keys in QueryItr ^RSSItemFTI.keys:
        let k = keys[0]
        wt.inc(k)
    
    var keys = toSeq(wt.keys)
    keys.sort() # Sort keys alphabetically
    for k in keys:
        echo k," ",wt[k]


# ----------------
proc main() =
    var p = initOptParser()
    var optcnt = 0
    var numberOfItems = 50
    for kind, key, val in p.getopt():
        inc optcnt

        case kind
        # Ein normales Argument (z. B. "meinfile.txt")
        of cmdArgument: discard
        of cmdLongOption, cmdShortOption:
            if key == "h" or key == "help":
                echo "search -l"
                echo "     -l[=n], --latest : Get the n latest entries (50 is default)"
                echo "     -f=n,m           : Fetch ^RSSItem(n, m)"
                echo "     -s[=lang]        : Search with keywords (lang defaults to DE)"
                echo "     -d=^global       : Dump a database global"
                echo "     -t               : Dump Full Text Index"
                quit(0)
            elif key == "l" or key == "latest":
                if val.len > 0:
                    try:
                        numberOfItems = parseInt(val)
                    except:
                        echo "ERROR: Wrong number format. Using default"
                showLatest(numberOfItems)
            elif key == "f":
                if val.len == 0:
                    echo "ERROR: need value for -f"
                    quit(0)
                showRSS(val)
                showRSSItem(val)
            elif key == "s":
                search(val)
            elif key == "d":
                fullDump(val)
            elif key == "t":
                dumpFTI(val)
            else:
                echo "ERROR: Illegal command. Use -h"
        of cmdEnd: 
            echo "cmdEnd"
            discard
    
    # Default, if no option was given
    if optcnt == 0:
        search()

if isMainModule:
    main()
