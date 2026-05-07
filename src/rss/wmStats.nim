import std/[strutils, strformat]
import mummy, mummy/routers, mummy/datastar
import nimrss

const
    globals = @[
        "^Author", "^ConfigFeed", "^DBStats", "^Feed", "^RSS", "^RSSCNT", "^RSSEnclosure",
        "^RSSFTI", "^RSSImage", "^RSSItem",  "^RSSItemFTI",
        "^RSSItemGUID", "^RSSItemIDXREF", "^RSSItemPUBDATE", "^Session", "^UserFeeds",
        ]

    emptyline = "<tr><td line-height:12px;' colspan=4>&nbsp;</td></tr>"


proc countGlobalDetail(gbl: string): DBStats =
    var stats = DBStats()
    let global = if gbl.startsWith("^"): gbl else: "^" & gbl
    stats.global = global

    for cnt in OrderItr @global.count:
        stats.orderCnt = cnt

    for key, value in QueryItr @global.kv:
        inc stats.querycnt
        inc(stats.keylen, key.len)
        inc(stats.valuelen, value.len)
        stats.minkey = min(stats.minkey, key.len)
        stats.minvalue = min(stats.minvalue, value.len)
        stats.maxkey = max(stats.maxkey, key.len)
        stats.maxvalue = max(stats.maxvalue, value.len)
    return stats


proc handleStats(req: Request) =
    var sse = req.respondSSE()
    var totalOrder, totalQuery, totalKeylen, totalValuelen = 0
    let timestamp = datetimeToUnix()

    let totalDuration = meassure:
        for gbl in globals:
            let duration = meassure:
                var stats = countGlobalDetail(gbl)
                let avgKey: float = (stats.keylen / stats.querycnt)
                let avgValue: float = (stats.valuelen / stats.querycnt)

            stats.duration = duration

            let time = stats.duration.split(" ")[0]
            let unit = stats.duration.split(" ")[1]
            let tr = fmt"""
                <tr>
                    <td align='left'>{gbl}</td>
                    <td align='right'>{stats.ordercnt}</td>
                    <td align='right'>{stats.querycnt}</td>
                    <td align='right'>{stats.keylen:>12}</td>
                    <td align='right'>{stats.valuelen:>12}</td>
                    <td align='right'>{avgKey:>5.1f}</td>
                    <td align='right'>{avgValue:>5.1f}</td>
                    <td align='right'>{stats.minkey:>4}</td>
                    <td align='right'>{stats.maxkey:>4}</td>
                    <td align='right'>{stats.minvalue:>4}</td>
                    <td align='right'>{stats.maxvalue:>8}</td>
                    <td align='right'>{time}</td>
                    <td align='right'>{unit}</td>
                </tr>
                """
            patchElements(sse, tr, selector="#stats-body", mode=Append)
            
            inc(totalOrder, stats.ordercnt)
            inc(totalQuery, stats.querycnt)
            inc(totalKeylen, stats.keylen)
            inc(totalValuelen, stats.valuelen)

            # Save in DB
            saveObject[DBStats](@[$timestamp, stats.global], stats)
            


    # Empty line
    patchElements(sse, emptyline, selector="#stats-body", mode=Append)
    # Summary line
    let totalTime = totalDuration.split(" ")[0]
    let totalUnit = totalDuration.split(" ")[1]
    let tr = fmt"""
        <tr>
            <td align='left'>Totals:</td>
            <td align='right'>{totalOrder}</td>
            <td align='right'>{totalQuery}</td>
            <td align='right'>{totalKeylen}</td>
            <td align='right'>{totalValuelen}</td>
            <td></td>
            <td></td>
            <td></td>
            <td></td>
            <td></td>
            <td></td>
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