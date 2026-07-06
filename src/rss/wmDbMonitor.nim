import std/[strutils, strformat, times, tables, algorithm, sequtils, json]
import mummy, mummy/routers, mummy/datastar
import nimrss

type StatData* = ref object
    mnemonic*: string
    domain*: string
    value*: int = 0
    delta*: int = 0

proc asStr(data: seq[int]): string =
    return data.join(",")

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
        let data = StatData(mnemonic: keys[0], domain: dmn, value: value, delta: delta)
        result.mgetOrPut(tm, @[]).add(data)
        lastData = data

    result.sort()


proc createScript(domain: string, xAxis: seq[int], data: seq[int]): string =
    let strxAxis = asStr(xAxis)
    let strData = asStr(data)

    result = fmt"""
        window.showChart = function() {{
            var chartDom = document.getElementById('chart1');
            if (!chartDom) return;

            var myChart = echarts.init(chartDom);
            var option = {{
                title: {{ text: 'YottaDB Monitoring data' }},
                tooltip: {{
                    trigger: 'axis',
                    axisPointer: {{
                      animation: false
                    }}
                  }},
                  legend: {{
                    data: ['{domain}'],
                    left: 10
                  }},
                toolbox: {{
                    feature: {{
                      dataZoom: {{
                        yAxisIndex: 'none'
                      }},
                      restore: {{}},
                      saveAsImage: {{}}
                    }}
                  }},
                axisPointer: {{
                    link: [
                      {{
                        xAxisIndex: 'all'
                      }}
                    ]
                  }},
                  dataZoom: [
                    {{
                      show: true,
                      realtime: true,
                      start: 70,
                      end: 100,
                      xAxisIndex: [0]
                    }},
                    {{
                      type: 'inside',
                      realtime: true,
                      start: 70,
                      end: 100,
                      xAxisIndex: [0]
                    }}
                  ],
                  grid: [
                    {{
                      left: 60,
                      right: 50,
                      height: '35%'
                    }},
                    {{
                      left: 60,
                      right: 50,
                      top: '55%',
                      height: '35%'
                    }}
                  ],                      
                xAxis: {{
                    data: [{strxAxis}] 
                }},
                yAxis: {{
                    type: 'log',
                    logBase: 10,  // Defaults to 10 if omitted
                    min: 'dataMin',
                    max: 'dataMax'
                }},
                series: [
                {{
                    name: '{domain}',
                    type: 'line',
                    data: [{strData}],
                }},
                ]
            }};
            myChart.setOption(option);
        }};
        showChart();
        """ 

proc handleChart1(req: Request) =
    let chartid = req.path[1..^1]
    let ctx = getContext(req)
    let params = ctx.getJson(chartid)
    let mnemonic = params["mnemonic"].getStr()
    let domain = params["domain"].getStr()

    let duration = meassure:
        let stats = getStats(mnemonic, domain)
        var xAxis: seq[int]
        var yAxis: seq[int]
        for (k, v) in stats.pairs():
            xAxis.add(k)
            yAxis.add(v[0].delta)

    SSE(req):
        let xAxisData = asStr(xAxis)
        let yAxisData = asStr(yAxis)
        patchSignals(sse, %*{
            fmt"{chartid}": {
                "x": xAxis,
                "y": yAxis,
                "processed": duration
            }
        })

        # cleanup the big array. TODO: find other solution
        patchSignals(sse, %*{
            fmt"{chartid}": {
                "x": [],
                "y": [],
            }
        })

        #let script = fmt"updateChart('{chartId}', '{mnemonic}', '{domain}', [{xAxisData}], [{yAxisData}]);"
        #sse.executeScript(script)

proc XhandleChart1(req: Request) =
    var statsTable: OrderedTable[int, seq[StatData]]
    var xAxis: seq[int]

    proc getStatsData(mnemonic: string, domain: string): seq[int] =
        var statsTable = getStats(mnemonic, domain)
        for (tm, entries) in statsTable.pairs():
            for entry in entries:
                if not xAxis.contains(tm): xAxis.add(tm)
                result.add(entry.delta)
          

    echo "handleChart1"
    let domain = "srv"
    
    xAxis.sort(proc (x, y: int): int =
      result = system.cmp(x, y)
    )
    
    let statsData = getStatsData("GET", "srv")
    let script = createScript(domain, xAxis, statsData)

    SSE(req):
        sse.executeScript(script)


# Callback for router registration
proc register*(router: var Router) =
    router.post("/chart*", handleChart1)


# Create module instance
let wmDbMonitorModule* = WebModule(
    name: "wmDbMonitor",
    register: register
)
