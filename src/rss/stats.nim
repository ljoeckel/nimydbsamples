import std/[strformat, strutils]
import yottadb


proc countGlobal(gbl: string): (int, int) =
    let global = if gbl.startsWith("^"): gbl else: "^" & gbl
    var orderCnt, queryCnt = 0
    for cnt in OrderItr @global.count:
        orderCnt = cnt
    for cnt in QueryItr @global.count:
        queryCnt = cnt
    return (orderCnt, queryCnt)

if isMainModule:
    let globals = @[
        "^Author", "^ConfigFeed", "^Feed", "^RSS", "^RSSCNT", "^RSSEnclosure",
        "^RSSFTI", "^RSSImage", "^RSSItem",  "^RSSItemFEEDID", "^RSSItemFTI",
        "^RSSItemGUID", "^RSSItemIDXREF", "^RSSItemPUBDATE", "^Session", "^UserFeeds",
        ]

    var totalOrder, totalQuery = 0

    echo "Global".alignLeft(25),"Order".align(10), " ", "Query".align(10)
    echo "-".repeat(46)
    for gbl in globals:
        let (orderCnt, queryCnt) = countGlobal(gbl)
        echo fmt"{gbl:<25}{orderCnt:>10} {queryCnt:>10}"
        inc(totalOrder, orderCnt)
        inc(totalQuery, queryCnt)
    echo "-".repeat(46)
    echo "".align(25),fmt"{totalOrder:>10} {totalQuery:>10}"

    