import std/[algorithm, sequtils, wordwrap, strutils]
import std/[parseopt, times, tables, strformat, typetraits]
import nimrss


proc printValue(key: string, value: string) =
    if value.len > 0:
        let wrap = value.wrapWords(maxLineWidth = 90).indent(18)
        echo fmt"{key:>16}: {strip(wrap)}"


proc showRSSItem(subscript: seq[string]) =
    for (field, value) in getRSSFields(subscript):
        printValue(field, value)


proc fullDump*(global: string) =
    let gbl = if global.startsWith("^"): global else: "^" & global
    for key, value in QueryItr @gbl.kv:
        #let rss = loadObject[RSS](key)
        echo key,"=",value

        
proc search(lang: string = "DE", userid: string = "guest") =
    while true:
        stdout.write("Search for: ")
        stdout.flushFile()
        var searchFor = readLine(stdin)
        if searchFor == "": quit(0)

        timed:
            let results = getFTI(searchFor, lang, userid, SortBy.ByTimeDescending)
            for tse in results:
                showRSSItem(tse.subscript)
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
                echo "     -f=n,m | *       : Fetch ^RSSItem(n, m) or * for all"
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
                if val == "*":
                    for rssId in OrderItr ^RSSItem:
                        for rssItemId in OrderItr ^RSSItem(rssId,""):
                            let subscript = @[rssId, rssItemId]
                            #showRSS(subscript)
                            showRSSItem(subscript)
                else:
                    let subscript = val.split(',')
                    #showRSS(subscript)
                    showRSSItem(subscript)
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
