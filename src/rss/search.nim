import std/strformat
import std/strutils
import std/wordwrap
import std/[algorithm, sequtils]
import std/[options, strutils, strformat, typetraits, enumerate, os]
import std/[sha1, base64, parseopt, httpclient, times]
import rssatom
import yottadb
import ydbutils
include searchlib

proc search() =
    while true:
        stdout.write("Search for: ")
        stdout.flushFile()
        var searchFor = readLine(stdin)
        if searchFor == "": quit(0)

        timed:
            for key in getRSSItemKeys(searchFor):
                showRSSItem(key)

        let more = getKeywords(searchFor)
        if more.len > 0: echo "More keywords: ", more


proc showLatest(max: int) =
    for key in getLatestRSSItemKeys(max):
        showRSSItem(key)
    #for item in getLatestRSSItems(25):
    #    echo item


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
                echo "     -s               : Search with keywords"
                echo "     -d=^global       : Dump a database global"
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

                showRSSItem(val)
            elif key == "s":
                search()
            elif key == "d":
                fullDump(val)
            else:
                echo "ERROR: Illegal command. Use -h"
        of cmdEnd: 
            echo "cmdEnd"
            discard
    
    # Default, if no option was given
    if optcnt == 0:
        search()


main()
