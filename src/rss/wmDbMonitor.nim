import std/[strutils, strformat, tables, algorithm, sequtils, json, times]
import mummy, mummy/routers, mummy/datastar
import nimrss


type 
    StatData* = ref object
        value*: int
        delta*: int

    StatResult = object
        processed: int
        filtered: int
        data: OrderedTable[int, seq[StatData]]

    StatType = enum
        Hour,
        Day,
        Week,
        Month,
        YearByDay,
        YearByMonth,
        All

proc sort(table: OrderedTable[int, seq[StatData]]): OrderedTable[int, seq[StatData]]=
    var pairsSeq = toSeq(table.pairs)
    pairsSeq.sort(proc (x, y: (int, seq[StatData])): int =
      result = system.cmp(x[0], y[0])
    )
    for (key, val) in pairsSeq:
        result[key] = val


proc getStats(mnemonic: string, domain: string, period: string): StatResult =
    let statType = parseEnum[StatType](period)

    var lastData: StatData
    var hours: array[24, int]
    var weekdays: array[7, int]
    var monthdays: array[31, int]
    var months: array[12, int]
    var yeardays: array[365, int]
    var timeRange: (int, int)
    let now = datetimeToUnix()

    case statType
    of Hour:
        timeRange = (now - (60*60), now)
    of Day:
        timeRange = currentDayFromTo()
    of Week:
        timeRange = currentWeekFromTo()
    of Month:
        timeRange = currentMonthFromTo()
    of YearByDay, YearByMonth:
        timeRange = currentYearFromTo()
    of All:
        timeRange = (0, now)

    var processed = 0
    var filtered = 0
    
    for keys in QueryItr ^DBStatsDetail(mnemonic, timeRange[0]).keys:
        if mnemonic != keys[0] or domain != keys[2]: continue
        let tm = parseInt(keys[1])
        if tm > timeRange[1]: break

        inc processed
        #if tm >= timeRange[0] and tm <= timeRange[1]: 
        inc filtered
        let value = Get ^DBStatsDetail(keys).int
        var delta = if lastData.isNil: value else: value - lastData.value
        if delta == 0: continue
        if delta < 0: delta = value # process restart, counters start from 0 again 
        let data = StatData(value: value, delta: delta)
        lastData = data

        case statType
        of Hour, All:
            result.data.mgetOrPut(tm, @[]).add(data)
        of Day:
            let timeObj = fromUnix(tm)
            let dt = timeObj.local
            let hour = ord(dt.hour)
            hours[hour] += delta
        of Week:
            let timeObj = fromUnix(tm)
            let dt = timeObj.local
            let weekday = ord(dt.weekday)
            weekdays[weekday] += delta
        of Month:
            let timeObj = fromUnix(tm)
            let dt = timeObj.local
            let month = ord(dt.month)
            monthdays[month] += delta
        of YearByDay:
            let timeObj = fromUnix(tm)
            let dt = timeObj.local
            let yearday = ord(dt.yearday)
            yeardays[yearday] += delta
        of YearByMonth:
            let timeObj = fromUnix(tm)
            let dt = timeObj.local
            let month = ord(dt.month)
            months[month] += delta
    
    case statType
    of Hour, All:
        discard # handled before
    of Day:
        for i in 0..23:
            let data = StatData(value: hours[i], delta: hours[i])
            result.data.mgetOrPut(timeRange[0] + (i*3600), @[]).add(data)
    of Week:
        for i in 0..<weekdays.len:
            let value = weekdays[i]
            let data = StatData(value: value, delta: value)
            result.data.mgetOrPut(timeRange[0] + (i*3600), @[]).add(data)
    of Month:
        for i in 0..<monthdays.len:
            let value = monthdays[i]
            let data = StatData(value: value, delta: value)
            result.data.mgetOrPut(timeRange[0] + (i*3600), @[]).add(data)
    of YearByDay:
        for i in 0..<yeardays.len:
            let value = yeardays[i]
            let data = StatData(value: value, delta: value)
            result.data.mgetOrPut(timeRange[0] + (i*3600), @[]).add(data)
    of YearByMonth:
        for i in 0..<months.len:
            let value = months[i]
            let data = StatData(value: value, delta: value)
            result.data.mgetOrPut(timeRange[0] + (i*3600), @[]).add(data)

    result.processed = processed
    result.filtered = filtered
    result.data = result.data.sort()


proc handleChart(req: Request) =
    let chartid = req.path[1..^1] # /chart1 -> chart1
    let ctx = getContext(req)
    let params = ctx.getJson(chartid)
    let mnemonic = params["mnemonic"].getStr()
    let domain = ctx.getStr("domain")
    let period = ctx.getStr("period")

    let ms = meassure:
        let stats = getStats(mnemonic, domain, period)

    echo fmt"chartid: {chartid}, mnemnomic: {mnemonic}, domain: {domain}, period: {period}, processed: {stats.processed}, filtered: {stats.filtered}, duration: {ms}"

    var xAxis: seq[int]
    var yAxis: seq[int]
    for (k, v) in stats.data.pairs():
        xAxis.add(k*1000)
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
