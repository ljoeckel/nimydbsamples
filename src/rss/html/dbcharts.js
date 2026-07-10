window.updateChart = function(chart, chartType) {
    if (!chart.x || chart.x.length === 0) return;
    var chartDom = document.getElementById(chart.id);
    if (!chartDom) return;
    
    var myChart = echarts.getInstanceByDom(chartDom);
    if (!myChart) {
        myChart = echarts.init(chartDom);
    }

    // 1. Combine X (timestamps) and Y (values) into an array of [x, y] pairs
    var seriesData = chart.x.map(function(xVal, index) {
        return [xVal, chart.y[index]];
    });

    var option = {
        title: { text: chart.mnemonic},
        tooltip: { trigger: 'axis', axisPointer: { animation: true } },
        legend: { data: [chart.mnemonic], left: 10 },
        toolbox: { feature: { dataZoom: { yAxisIndex: 'none' }, restore: {}, saveAsImage: {} } },
        axisPointer: { link: [{ xAxisIndex: 'all' }] },
        dataZoom: [
            { show: true, realtime: true, start: 0, end: 100, xAxisIndex: [0] },
            { type: 'inside', realtime: true, start: 90, end: 100, xAxisIndex: [0] }
        ],
        grid: [
            { left: 60, right: 50, height: '35%' },
            { left: 60, right: 50, top: '55%', height: '35%' }
        ],                      
        xAxis: {
            type: 'time',
            axisLabel: {
                formatter: '{yyyy}-{MM}-{dd} {HH}:{mm}:{ss}'
            }
        },
        yAxis: {
            type: 'value',
            min: 'dataMin',
            max: 'dataMax'
        },
        series: [
            {
                name: chart.mnemonic,
                type: chartType,
                data: seriesData // Use the combined [x, y] data array here
            }
        ]
    };
    myChart.setOption(option);
};
