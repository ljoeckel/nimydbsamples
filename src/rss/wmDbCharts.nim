import std/[strutils, strformat, tables, algorithm, sequtils, json, times]
import mummy, mummy/routers, mummy/datastar
import nimrss


type 
    StatResult = object
        processed: int
        data: OrderedTable[int, seq[int]]

    StatType = enum
        All,
        Minute,
        Hour,
        Day,
        Week,
        Month,
        YearByDay,
        YearByMonth


proc sort(table: OrderedTable[int, seq[int]]): OrderedTable[int, seq[int]]=
    var pairsSeq = toSeq(table.pairs)
    pairsSeq.sort(proc (x, y: (int, seq[int])): int =
      result = system.cmp(x[0], y[0])
    )
    for (key, val) in pairsSeq:
        result[key] = val


proc getStats(mnemonic: string, domain: string, period: string, jsDt: DateTime): StatResult =
    var 
        seconds: array[60, int]
        minutes: array[60, int]
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
    of Minute:  timeRange = minuteFromTo(jsDt)
    of Hour:    timeRange = hourFromTo(jsDt)
    of Day:     timeRange = dayFromTo(jsDt)
    of Week:    timeRange = weekFromTo(jsDt)
    of Month:   timeRange = monthFromTo(jsDt)
    of YearByDay, YearByMonth:  timeRange = yearFromTo(jsDt)
    of All:     timeRange = (0, now)
    for keys in QueryItr ^DBStatsDOMAIN(domain, mnemonic, timeRange[0]).keys:
        # ^DBStatsDOMAIN("srv","KIL",1788065309,318994)=5
        if keys[0] != domain: break
        if keys[1] != mnemonic: break
        let tm = parseInt(keys[2])
        if tm > timeRange[1]: break
        let value = parseInt( Get ^DBStatsDOMAIN(keys) )

        let dt = fromUnix(tm).local
        case statType
        of Minute:      seconds[dt.second] += value
        of Hour:        minutes[dt.minute] += value
        of Day:         hours[dt.hour] += value
        of Week:        weekdays[ord(dt.weekday)] += value
        of Month:       monthdays[dt.monthday-1] += value
        of YearByDay:   yeardays[dt.yearday] += value
        of YearByMonth: months[ord(dt.month)-1] += value
        of All:         result.data.mgetOrPut(tm, @[]).add(value)

        inc processed

    
    case statType
    of All:
        discard # handled before
    of Minute:
        for i in 0..59:
            let td = calcTimeForSecond(timeRange[0], i)
            result.data.mgetOrPut(td, @[]).add(seconds[i])
    of Hour:
        for i in 0..59:
            let td = calcTimeForMinute(timeRange[0], i)
            result.data.mgetOrPut(td, @[]).add(minutes[i])
    of Day:
        for i in 0..23:
            let td = calcTimeForHour(timeRange[0], i)
            result.data.mgetOrPut(td, @[]).add(hours[i])
    of Week:
        for i in 0..<weekdays.len:
            let td = calcTimeForDay(timeRange[0], i)
            result.data.mgetOrPut(td, @[]).add(weekdays[i])
    of Month:
        for i in 0..<monthdays.len:
            let td = calcTimeForDay(timeRange[0], i)
            result.data.mgetOrPut(td, @[]).add(monthdays[i])
    of YearByDay:
        for i in 0..<yeardays.len:
            let td = calcTimeForDay(timeRange[0], i)
            result.data.mgetOrPut(td, @[]).add(yeardays[i])
    of YearByMonth:
        for i in 0..<months.len:
            let td = calcTimeForMonth(timeRange[0], i)
            result.data.mgetOrPut(td, @[]).add(months[i])

    result.processed = processed
    result.data = result.data.sort()


proc handleChart(req: Request) =
    let chartid = req.path[1..^1] # /chart1 -> chart1
    let ctx = getContext(req)
    let mnemonics = ctx.getSeq("mnemonics")
    let dts = ctx.getStr("dateTime")
    let dt = fromISO8601(dts)

    let params = ctx.getJson(chartid)
    let mnemonic = params["mnemonic"].getStr()
    let domain = ctx.getStr("domain")
    let period = ctx.getStr("period")

    let duration = meassure:
        let stats = getStats(mnemonic, domain, period, dt)

    #echo fmt"chartid: {chartid}, mnemnomic: {mnemonic}, domain: {domain}, period: {period}, processed: {stats.processed}, duration: {duration}"

    var xAxis = newSeqOfCap[int](stats.data.len)
    var yAxis = newSeqOfCap[int](stats.data.len)
    for (k, v) in stats.data.pairs():
        xAxis.add(k*1000)
        yAxis.add(v[0])

    if yAxis.len == 0: 
        xAxis.add(0)
        yAxis.add(0)

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
let wmDbChartsModule* = WebModule(
    name: "wmDbCharts",
    register: register
)
