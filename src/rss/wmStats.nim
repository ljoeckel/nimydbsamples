import std/[strutils, strformat, math, json]
import std/[tables, algorithm]
import mummy, mummy/routers, mummy/datastar
import nimrss

const
    globals = @[
        "^Author", "^ConfigFeed", "^Feed", "^RSS", "^RSSCNT", "^RSSEnclosure",
        "^RSSFTI", "^RSSImage", "^RSSItem",  "^RSSItemFTI",
        "^RSSItemGUID", "^RSSItemIDXREF", "^RSSItemPUBDATE", 
        "^stopwordsEN", "^stopwordsDE", "^stopwordsES", "^stopwordsWC",
        ]

    adminglobals = @[
        "^Session", "^UserFeeds",
        "^Registration", "^RegistrationEMAIL", "^DBStats", "^DBStatsDetail"
        ]

    emptyline = "<tr><td line-height:12px;' colspan=4>&nbsp;</td></tr>"

    TABLE_PAGESIZE = 20


func hrb(bytes: int): string =
    # return number of bytes as b/k/m/g
    if bytes < 1024:     return $bytes & "b"
    elif bytes < 1024^2: return $(bytes div 1024) & "k"
    elif bytes < 1024^3: return $(bytes div 1024^2) & "m"
    elif bytes < 1024^4: return $(bytes div 1024^3) & "g"
    

proc countKeys(gbl: string): DBStats =
    var stats = DBStats()
    let global = if gbl.startsWith("^"): gbl else: "^" & gbl
    stats.global = global

    for cnt in OrderItr @global.count:
        stats.orderCnt = cnt

    return stats

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


proc scanKeys(req: Request) =
    var sse = req.respondSSE()
    var totalOrder = 0

    let totalDuration = meassure:
        for gbl in globals:
            let duration = meassure:
                var stats = countKeys(gbl)
                let avgKey: float = (stats.keylen / stats.querycnt)
                let avgValue: float = (stats.valuelen / stats.querycnt)

            stats.duration = duration

            let time = stats.duration.split(" ")[0]
            let unit = stats.duration.split(" ")[1]
            let tr = fmt"""
                <tr>
                    <td align='left'>
                        <a href=#{gbl} 
                            data-on:click="
                                $page=-1;
                                $lastpage=-1;
                                $global='{gbl}';
                                @post('/dbedit.html')">
                            {gbl}
                        </a>
                    </td>
                    <td align='right'>{stats.ordercnt}</td>
                    <td></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td>
                    <td align='right'>{time}</td>
                    <td align='right'>{unit}</td>
                </tr>
                """
            patchElements(sse, tr, selector="#stats-body", mode=Append)
            inc(totalOrder, stats.ordercnt)
            
    # Empty line
    patchElements(sse, emptyline, selector="#stats-body", mode=Append)
    # Summary line
    let totalTime = totalDuration.split(" ")[0]
    let totalUnit = totalDuration.split(" ")[1]
    let tr = fmt"""
        <tr>
            <td align='left'>Totals:</td>
            <td align='right'>{totalOrder}</td>
            <td></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td>
            <td align='right'>{totalTime}</td>
            <td align='right'>{totalUnit}</td>
        </tr>
        """
    patchElements(sse, tr, selector="#stats-body", mode=Append)

    sse.close()


proc scanFull(req: Request) =
    let ctx = getContext(req)
    if not ctx.isAdmin():
        SSE(req):
            patchElements(sse, "<h4>'admin' only!</h4>", selector="#stats-body", mode=Replace)
            return

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
                    <td align='right'>{hrb(stats.keylen):>12}</td>
                    <td align='right'>{hrb(stats.valuelen):>12}</td>
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
            <td align='right'>{hrb(totalKeylen)}</td>
            <td align='right'>{hrb(totalValuelen)}</td>
            <td></td><td></td><td></td><td></td><td></td><td></td>
            <td align='right'>{totalTime}</td>
            <td align='right'>{totalUnit}</td>
        </tr>
        """
    patchElements(sse, tr, selector="#stats-body", mode=Append)

    sse.close()


proc handleStats(req: Request) =
    let ctx = getContext(req)
    let action = ctx.getStr("action")
    if action == "keys":
        scanKeys(req)
    elif action == "full":
        scanFull(req)
    else:
        echo "Unhandled action: ", action


proc handleRTStats(req: Request) =
    var tbody = "<tbody id='rtstats'>"
    for k in OrderItr ^DBSTATS.keys:
        let mnemonic = k[0]
        let v = Get ^DBSTATS(mnemonic)
        let delta = Get ^DBSTATS(mnemonic, "delta")
        if v != "0":
            #<td><span class='has-tooltip' data-tooltip='{title}' tabindex='0' role='toolbar'>{k[0]}</span></td>
            let title = mnemonic & ": " & mnemomics[mnemonic]
            tbody.add(fmt"""
                <tr>
                    <td><span class='has-tooltip tooltip-right' data-tooltip='{title}' tabindex='0' role='toolbar'>{k[0]}</span></td>
                    <td align='right'>{v}</td>
                    <td align='right'>{delta}</td>
                </tr>
                """)
    tbody.add("</tbody>")

    SSE(req):
        patchElements(sse, tbody, selector="#rtstats", mode=Replace)


proc handleEditGlobal(req: Request) =
    echo "*** handleEditGlobal ***"
    let
        ctx = getContext(req)
        global = ctx.getStr("global")
        lastpage = ctx.getInt("lastpage")
    
    echo "global=", global
    if global.isEmptyOrWhitespace: return

    var 
        btn = ctx.getStr("btn")
        subscripts_low = getSeq[string](ctx, "subscripts_low")
        subscripts_high = getSeq[string](ctx, "subscripts_high")    
        page = ctx.getInt("page")
        cnt = 0
        direction: ListDirection
        rows = ""
        entries: seq[seq[string]]
    
    # cleanup when global changes
    if page <= 0 or btn == "firstPage":
        page = 1
        btn = ""
        direction = Up
        subscripts_low = @[]
        subscripts_high = @[]
    elif btn == "lastPage":
        page = 99999
        direction = Down
        subscripts_low = @[]
        subscripts_high = @[]
    elif btn == "nextPage":
        direction = Up
    elif btn == "currentPageInput":
        if page > lastpage: direction = Up else: direction = Down
    else:
        direction = Down

    proc incrementSubscripts(subscripts: var seq[string], maxCount: int) =
        var cnt = 0
        for keys in QueryItr @global(subscripts).keys:
            subscripts = keys
            inc cnt
            if cnt >= maxCount:
                break

    proc decrementSubscripts(subscripts: var seq[string], maxCount: int) =
        var cnt = 0
        for keys in QueryItr @global(subscripts).keys.reverse:
            subscripts = keys
            inc cnt
            if cnt >= maxCount:
                break

    echo "page=", page, " lastpage=", lastpage, " btn=", btn, " direction=", direction
    echo "subscripts_high=", subscripts_high

    let pageDelta = page - lastpage
    if subscripts_high.len > 0 and pageDelta > 1:
        for i in 0..pageDelta:
            incrementSubscripts(subscripts_high, TABLE_PAGESIZE)
    elif subscripts_high.len > 0 and pageDelta < -1:
        for i in 0..abs(pageDelta):
            incrementSubscripts(subscripts_low, TABLE_PAGESIZE)
    
    proc createGlobalsTR(idx: int): string =
        let keys = entries[idx]
        let value = Get @global(keys)
        let k = keys.join(", ")
        result.add(fmt"""
            <tr>
                <td>{k}</td>
                <td>{value}</td>
            </tr>
            """)

    if direction == Up:
        for keys in QueryItr @global(subscripts_high).keys:
            entries.add(keys)
            inc cnt
            if cnt >= TABLE_PAGESIZE: break

        for idx in 0..<entries.len:
            rows.add(createGlobalsTR(idx))
        
        if entries.len > 0:
            ctx.save("subscripts_low", entries[0])
            ctx.save("subscripts_high", entries[entries.len-1])
    else:
        for keys in QueryItr @global(subscripts_low).keys.reverse:
            entries.add(keys)
            inc cnt
            if cnt >= TABLE_PAGESIZE: break

        for idx in countdown(entries.len-1, 0):
            rows.add(createGlobalsTR(idx))

        if entries.len > 0:
            ctx.save("subscripts_low", entries[entries.len-1])
            ctx.save("subscripts_high", entries[0])

    let table = fmt"""
        <tbody id="globaltbody">
            {rows}
        </tbody>
        """

    SSE(req):
        patchSignals(sse, %*{
            "showGlobals": true, 
            "page": page,
            "lastpage": page,
        })
        patchElements(sse, table, selector="#globaltbody", mode=Replace)


proc handleGetGlobalList(req: Request) =
    echo "*** handleGetGlobalList ***"
    let ctx = getContext(req)
    let selected = ctx.getStr("global")
    echo "global selected=", selected

    var options = "<option value='' selected disabled>Select Global</option>"
    for global in globals:
        if global == selected:
            options.add(fmt"""<option value={global} selected>{global}</option>""")
        else:
            options.add(fmt"""<option value={global}>{global}</option>""")
    
    if ctx.isAdmin():
        for global in adminglobals:
            options.add(fmt"""<option value={global}>{global}</option>""")

    SSE(req):
        patchElements(sse, options, selector="#globals", mode=Inner)



# Callback for router registration
proc register*(router: var Router) =
    router.post("/get-stats", handleStats)
    router.post("/get-rtstats", handleRTStats)
    router.post("/editglobal", handleEditGlobal)
    router.post("/getGlobalList", handleGetGlobalList)

# Create module instance
let wmStatsModule* = WebModule(
    name: "wmStats",
    register: register
)
