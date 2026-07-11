import std/[strutils, strformat, tables, algorithm, sequtils, json, times]
import mummy, mummy/routers, mummy/datastar
import nimrss


type 
    StatData* = ref object
        value*: int
        delta*: int

    StatResult = object
        processed: int
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
    var 
        lastData: StatData
        hours: array[24, int]
        weekdays: array[7, int]
        monthdays: array[31, int]
        months: array[12, int]
        yeardays: array[365, int]
        timeRange: (int, int)
        now = datetimeToUnix()
        processed = 0

    let statType = parseEnum[StatType](period)
    case statType
    of Hour:    timeRange = currentHourFromTo()
    of Day:     timeRange = currentDayFromTo()
    of Week:    timeRange = currentWeekFromTo()
    of Month:   timeRange = currentMonthFromTo()
    of YearByDay, YearByMonth:  timeRange = currentYearFromTo()
    of All:     timeRange = (0, now)

    for keys in QueryItr ^DBStatsDetail(mnemonic, timeRange[0]).keys:
        if mnemonic != keys[0] or domain != keys[2]: continue
        let tm = parseInt(keys[1])
        if tm > timeRange[1]: break
        inc processed

        let value = Get ^DBStatsDetail(keys).int
        var delta = if lastData.isNil: value else: value - lastData.value
        if delta == 0: continue
        if delta < 0: delta = value # process restart, counters start from 0 again 
        let data = StatData(value: value, delta: delta)
        lastData = data

        let timeObj = fromUnix(tm)
        let dt = timeObj.local

        case statType
        of Hour, All:   result.data.mgetOrPut(tm, @[]).add(data)
        of Day:         hours[dt.hour] += delta
        of Week:        weekdays[ord(dt.weekday)] += delta
        of Month:       monthdays[dt.monthday] += delta
        of YearByDay:   yeardays[dt.yearday] += delta
        of YearByMonth: months[ord(dt.month)] += delta
    
    case statType
    of Hour, All:
        discard # handled before
    of Day:
        for i in 0..23:
            let data = StatData(delta: hours[i])
            let td = calcTimeForHour(timeRange[0], i)
            result.data.mgetOrPut(td, @[]).add(data)
    of Week:
        for i in 0..<weekdays.len:
            let data = StatData(delta: weekdays[i])
            let td = calcTimeForDay(timeRange[0], i)
            result.data.mgetOrPut(td, @[]).add(data)
    of Month:
        for i in 0..<monthdays.len:
            let data = StatData(delta: monthdays[i])
            let td = calcTimeForDay(timeRange[0], i)
            result.data.mgetOrPut(td, @[]).add(data)
    of YearByDay:
        for i in 0..<yeardays.len:
            let data = StatData(delta: yeardays[i])
            let td = calcTimeForDay(timeRange[0], i)
            result.data.mgetOrPut(td, @[]).add(data)
    of YearByMonth:
        for i in 0..<months.len:
            let data = StatData(delta: months[i])
            let td = calcTimeForMonth(timeRange[0], i)
            result.data.mgetOrPut(td, @[]).add(data)

    result.processed = processed
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

    echo fmt"chartid: {chartid}, mnemnomic: {mnemonic}, domain: {domain}, period: {period}, processed: {stats.processed}, duration: {ms}"

    var xAxis = newSeqOfCap[int](stats.data.len)
    var yAxis = newSeqOfCap[int](stats.data.len)
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
