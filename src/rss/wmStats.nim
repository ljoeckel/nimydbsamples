import std/[strutils, strformat]
import mummy, mummy/routers, mummy/datastar
import nimrss

const
    globals = @[
        "^Author", "^ConfigFeed", "^Feed", "^RSS", "^RSSCNT", "^RSSEnclosure",
        "^RSSFTI", "^RSSImage", "^RSSItem",  "^RSSItemFTI",
        "^RSSItemGUID", "^RSSItemIDXREF", "^RSSItemPUBDATE", "^Session", "^UserFeeds",
        ]

    emptyline = "<tr><td line-height:12px;' colspan=4>&nbsp;</td></tr>"


proc countGlobal(gbl: string): (int, int) =
    let global = if gbl.startsWith("^"): gbl else: "^" & gbl
    var orderCnt, queryCnt = 0
    for cnt in OrderItr @global.count:
        orderCnt = cnt
    for cnt in QueryItr @global.count:
        queryCnt = cnt
    return (orderCnt, queryCnt)


proc handleStats(req: Request) =
    var sse = req.respondSSE()
    var totalOrder, totalQuery = 0

    let totalDuration = meassure:
        for gbl in globals:
            let duration = meassure:
                let (orderCnt, queryCnt) = countGlobal(gbl)
            let time = duration.split(" ")[0]
            let unit = duration.split(" ")[1]
            let tr = fmt"""
                <tr>
                    <td align='left'>{gbl}</td>
                    <td align='right'>{orderCnt}</td>
                    <td align='right'>{queryCnt}</td>
                    <td align='right'>{time}</td>
                    <td align='right'>{unit}</td>
                </tr>
                """
            patchElements(sse, tr, selector="#stats-body", mode=Append)
            
            inc(totalOrder, orderCnt)
            inc(totalQuery, queryCnt)

    # Empty line
    patchElements(sse, emptyline, selector="#stats-body", mode=Append)
    # Summary line
    let totalTime = totalDuration.split(" ")[0]
    let totalUnit = totalDuration.split(" ")[1]
    let tr = fmt"""
        <tr>
            <td align='left'>Total # of records:</td>
            <td align='right'>{totalOrder}</td>
            <td align='right'>{totalQuery}</td>
            <td align='right'>{totalTime}</td>
            <td align='right'>{totalUnit}</td>
        </tr>
        """
    patchElements(sse, tr, selector="#stats-body", mode=Append)

    sse.close()


# Callback for router registration
proc register*(router: var Router) =
    router.get("/get-stats", handleStats)

# Create module instance
let wmStatsModule* = WebModule(
    name: "wmStats",
    register: register
)