import std/[strutils, strformat, math, tables, json]
import mummy, mummy/routers, mummy/datastar
import nimrss

const mnemomics = {
    "AFRA": "# of waits for instance freeze to release critical sections",
    "BREA": "# of waits for block read & decryption",
    "BTD": "# of database Block Transitions to Dirty",
    "BTS": "# of times a dirty buffer was flushed so a BT could be reused",
    "BUS": "# of times db_csh_get could not determine whether a block was in cache or not",
    "CAT": "Critical section Total Acquisitions successes",
    "CFE": "Critical section Failed (blocked) acquisition total caused by Epochs. It is incremented a single time for each observed instance of contention.",
    "CFS": "This mnemonic is not maintained and contains zeros.",
    "CFT": "Critical section Failed (blocked) acquisition Total. It is incremented a single time for each observed instance of contention.",
    "CQS": "This mnemonic is not maintained and contains zeros.",
    "CQT": "This is maintained only if MUTEX_TYPE is YDB or ADAPTIVE. It is not maintained and contains zeros if MUTEX_TYPE is PTHREAD. When maintained, this is the number of times a process did a queued sleep while waiting for the database critical section.",
    "CTN": "Current Transaction Number of the database for the last committed read-write transaction (TP and non-TP)",
    "CYS": "This mnemonic is not maintained and contains zeros.",
    "CYT": "This is maintained only if MUTEX_TYPE is YDB or ADAPTIVE. It is not maintained and contains zeros if MUTEX_TYPE is PTHREAD. When maintained, this is the number of times a process did a yield while waiting for the database critical section.",
    "DEX": "# of Database file EXtentions",
    "DEXA": "# of waits for database extension",
    "DFL": "# of Database FLushes of the entire set of dirty global buffers in shared memory to disk",
    "DFS": "# of times a process does an fsync of the database file.",
    "DRD": "# of Disk ReaDs from the database file (TP and non-TP, committed and rolled-back). This does not include reads that are satisfied by buffered globals for databases that use the BG (Buffered Global) access method. YottaDB always reports 0 for databases that use the MM (memory-mapped) access method as this has no real meaning in that mode.",
    "DTA": "# of DaTA operations (TP and non-TP)",
    "DWT": "# of Disk WriTes to the database file (TP and non-TP, committed and rolled-back). This does not include writes that are satisfied by buffered globals for databases that use the BG (Buffered Global) access method. YottaDB always reports 0 for databases that use the MM (memory-mapped) access method as this has no real meaning in that mode.",
    "GET": "# of GET operations (TP and non-TP)",
    "GLB": "# of waits for bg access critical section",
    "JBB": "# of Journal Buffer Bytes updated in shared memory",
    "JEX": "# of Journal file EXtentions",
    "JFB": "# of Journal File Bytes written to the journal file on disk. For performance reasons, YottaDB always aligns the beginning of these writes to file system block size boundaries. JFB counts all bytes including those needed for alignment in order to reflect the actual IO load on the journal file. Since the bytes required to achieve alignment may have already been counted as part of the previous JFB, processes may write the same bytes more than once, causing the JFB counter to typically be higher than JBB.",
    "JFL": "# of Journal FLushes of all dirty journal buffers in shared memory to disk. For example: when switching journal files etc.",
    "JFS": "# of Journal FSync operations on the journal file. For example: when writing an epoch record, switching a journal file etc.",
    "JFW": "# of Journal File Write system calls",
    "JNL": "# of waits for journal access critical section",
    "JOPA": "# of waits for journal open critical section",
    "JRE": "# of Journal Regular Epoch records written to the journal file (only seen in a -detail journal extract). These are written every time an epoch-interval boundary is crossed while processing updates.",
    "JRI": "# of JouRnal Idle epoch journal records written to the journal file (only seen in a -detail journal extract). These are written when a burst of updates is followed by an idle period, around 5 seconds of no updates after the database flush timer has flushed all dirty global buffers to the database file on disk.",
    "JRL": "# of Journal Records with a Logical record type (e.g. SET, KILL etc.) written to the journal file",
    "JRO": "# of Journal Records with a type Other than logical written to the journal file (e.g. AIMG, EPOCH, PBLK, PFIN, PINI, and so on)",
    "JRP": "# of Journal Records with a Physical record type (i.e. PBLK, AIMG) written to the journal file (these records are seen only in a -detail journal extract)",
    "KIL": "# of KILl operations (kill as well as zwithdraw, TP and non-TP)",
    "KTG": "# of invoked KILL triggers",
    "LKF": "# of LocK calls (mapped to this db) that Failed",
    "LKS": "# of LocK calls (mapped to this db) that Succeeded",
    "MLBA": "# of waits for blocked LOCK",
    "MLK": "# of waits for LOCK access",
    "NBR": "# of Non-tp committed transaction induced Block Reads on this database",
    "NBW": "# of Non-tp committed transaction induced Block Writes on this database",
    "NR0": "# of Non-tp transaction Restarts at try 0",
    "NR1": "# of Non-tp transaction Restarts at try 1",
    "NR2": "# of Non-tp transaction Restarts at try 2",
    "NR3": "# of Non-tp transaction Restarts at try 3",
    "NTR": "# of Non-tp committed Transactions that were Read-only on this database",
    "NTW": "# of Non-tp committed Transactions that were read-Write on this database",
    "ORD": "# of $ORDer(,1) (forward) operations (TP and non-TP); the count of $Order(,-1) operations are reported under ZPR.",
    "PRC": "# of waits on exit",
    "PRG": "# of pre-read globals that were performed by the reader helper",
    "QRY": "# of $QueRY() operations (TP and non-TP)",
    "SET": "# of SET operations (TP and non-TP)",
    "STG": "# of invoked SET triggers",
    "TBR": "# of Tp transaction induced Block Reads on this database",
    "TBW": "# of Tp transaction induced Block Writes on this database",
    "TC0": "# of Tp transaction Conflicts at try 0 (counted only for that region which caused the TP transaction restart)",
    "TC1": "# of Tp transaction Conflicts at try 1 (counted only for that region which caused the TP transaction restart)",
    "TC2": "# of Tp transaction Conflicts at try 2 (counted only for that region which caused the TP transaction restart)",
    "TC3": "# of Tp transaction Conflicts at try 3 (counted only for that region which caused the TP transaction restart)",
    "TC4": "# of Tp transaction Conflicts at try 4 and above (counted only for that region which caused the TP transaction restart)",
    "TR0": "# of Tp transaction Restarts at try 0 (counted for all regions participating in restarting TP transaction)",
    "TR1": "# of Tp transaction Restarts at try 1 (counted for all regions participating in restarting TP transaction)",
    "TR2": "# of Tp transaction Restarts at try 2 (counted for all regions participating in restarting TP transaction)",
    "TR3": "# of Tp transaction Restarts at try 3 (counted for all regions participating in restarting TP transaction)",
    "TR4": "# of Tp transaction Restarts at try 4 and above (restart counted for all regions participating in restarting TP transaction)",
    "TRB": "# of Tp read-only or read-write transactions Rolled Back (excluding incremental rollbacks)",
    "TRGA": "# of mini-transaction completion",
    "TRX": "# of waits for transaction in progress",
    "TTR": "# of Tp committed Transactions that were Read-only on this database",
    "TTW": "# of Tp committed Transactions that were read-Write on this database",
    "WFL": "# of database flushes that were performed by the writer helpers",
    "WFR": "# of times a process slept while waiting for another process to read in a database block",
    "WHE": "# of writer helper epochs",
    "WRL": "# of times a process consistently slept (longer than WFR) while waiting for another process to read in a database block",
    "ZAD": "# of waits for region freeze off",
    "ZPR": "# of $order(,-1) or $ZPRevious() (reverse order) operations (TP and non-TP). The count of $Order(,1) operations are reported under ORD.",
    "ZTG": "# of invoked ZTRIGGERs",
    "ZTR": "# of ZTRigger command operations"
}.toTable


const
    globals = @[
        "^Author", "^ConfigFeed", "^DBStats", "^Feed", "^RSS", "^RSSCNT", "^RSSEnclosure",
        "^RSSFTI", "^RSSImage", "^RSSItem",  "^RSSItemFTI",
        "^RSSItemGUID", "^RSSItemIDXREF", "^RSSItemPUBDATE", "^Session", "^UserFeeds",
        "^stopwordsEN", "^stopwordsDE", "^stopwordsES", "^stopwordsWC",
        "^Registration", "^RegistrationEMAIL", "^DBSTATS"
        ]

    emptyline = "<tr><td line-height:12px;' colspan=4>&nbsp;</td></tr>"

const
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
                                $global='{gbl}';
                                @post('/editglobal')">
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
    if ctx.userid != "admin":
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


proc updateDBStats*(sse: SSEConnection) =
    ydb_ci: "xzshow"
    for (key, value) in QueryItr RESULT("G",0).kv:
        let fields = value.split(",")
        for field in fields:
            let parts = field.split(":")
            let mnemonic = parts[0]
            if mnemonic in mnemomics:
                let lastValue = Get ^DBSTATS(mnemonic).int
                let value = parseInt(parts[1]) # cummulated value
                let delta = abs(lastValue - value)
                if value > 0:
                    Set: 
                        ^DBSTATS(mnemonic) = value
                        ^DBSTATS(mnemonic, "delta") = delta
                

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
    patchElements(sse, tbody, selector="#rtstats", mode=Replace)


proc handleRTStats(req: Request) =
    SSE(req):
        updateDBStats(sse)


proc handleEditGlobal(req: Request) =
    let
        ctx = getContext(req)
        global = ctx.getStr("global")
        lastPage = ctx.getInt("lastPage")
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
        if page > lastPage: direction = Up else: direction = Down
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

    let pageDelta = page - lastPage
    if subscripts_high.len > 0 and pageDelta > 1:
        for i in 0..pageDelta:
            incrementSubscripts(subscripts_high, TABLE_PAGESIZE)
    elif subscripts_high.len > 0 and pageDelta < -1:
        for i in 0..abs(pageDelta):
            incrementSubscripts(subscripts_low, TABLE_PAGESIZE)
    
    
    #proc createGlobalsTR(keys: seq[string], value: string): string =
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
            "lastPage": page,
        })
        patchElements(sse, table, selector="#globaltbody", mode=Replace)




# Callback for router registration
proc register*(router: var Router) =
    router.post("/get-stats", handleStats)
    router.post("/get-rtstats", handleRTStats)
    router.post("/editglobal", handleEditGlobal)

# Create module instance
let wmStatsModule* = WebModule(
    name: "wmStats",
    register: register
)