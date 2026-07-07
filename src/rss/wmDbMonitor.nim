import std/[strutils, strformat, tables, algorithm, sequtils, json]
import mummy, mummy/routers, mummy/datastar
import nimrss

type StatData* = ref object
    value*: int = 0
    delta*: int = 0


proc sort(table: OrderedTable[int, seq[StatData]]): OrderedTable[int, seq[StatData]]=
    var pairsSeq = toSeq(table.pairs)
    pairsSeq.sort(proc (x, y: (int, seq[StatData])): int =
      result = system.cmp(x[0], y[0])
    )
    for (key, val) in pairsSeq:
        result[key] = val


proc getStats(mnemonic: string, domain: string): OrderedTable[int, seq[StatData]] =
    var lastData: StatData

    for keys in QueryItr ^DBStatsDetail.keys:
        if keys[0] != mnemonic: continue
        let dmn = keys[2]
        if dmn != domain: continue

        let tm = parseInt(keys[1])
        let value = Get ^DBStatsDetail(keys).int
        var delta = if lastData.isNil: value else: value - lastData.value
        if delta == 0: continue
        if delta < 0: delta = value # process restart, counters start from 0 again 
        let data = StatData(value: value, delta: delta)
        result.mgetOrPut(tm, @[]).add(data)
        lastData = data

    result.sort()


proc handleChart(req: Request) =
    let chartid = req.path[1..^1] # /chart1 -> chart1
    let ctx = getContext(req)
    let params = ctx.getJson(chartid)
    let mnemonic = params["mnemonic"].getStr()
    let domain = ctx.getStr("domain")

    let stats = getStats(mnemonic, domain)
    var xAxis: seq[int]
    var yAxis: seq[int]
    for (k, v) in stats.pairs():
        xAxis.add(k)
        yAxis.add(v[0].delta)

    SSE(req):
        patchSignals(sse, %*{
            fmt"{chartid}": {
                "x": xAxis,
                "y": yAxis,
            }
        })

        # cleanup the big array. TODO: find other solution
        patchSignals(sse, %*{
            fmt"{chartid}": {
                "x": [],
                "y": [],
            }
        })


# Callback for router registration
proc register*(router: var Router) =
    router.post("/chart*", handleChart) # handle chart1..chartN


# Create module instance
let wmDbMonitorModule* = WebModule(
    name: "wmDbMonitor",
    register: register
)
