import std/[algorithm, sequtils]
import std/[options, wordwrap, strutils, strformat, typetraits]
import std/[sha1, base64, parseopt, httpclient, times]
import nimrss
import std/tables


proc search(lang: string = "DE", userid: string = "ljoeckel") =
    while true:
        stdout.write("Search for: ")
        stdout.flushFile()
        var searchFor = readLine(stdin)
        if searchFor == "": quit(0)

        timed:
            let results = getFTI(searchFor, lang, userid)
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
    echo wt
    echo "words=", wt.len


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
