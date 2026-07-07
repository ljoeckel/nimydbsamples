window.updateChart = function(chart) {
    if (!chart.x || chart.x.length === 0) return;
    var chartDom = document.getElementById(chart.id);
    if (!chartDom) return;
    // 2. Bestehende Instanz holen oder neu erstellen
    var myChart = echarts.getInstanceByDom(chartDom);
    if (!myChart) {
        myChart = echarts.init(chartDom);
    }
    // 3. Optionen setzen (ECharts merged das automatisch)
    var option = {
        title: { text: chart.mnemonic},
        tooltip: { trigger: 'axis', axisPointer: { animation: false } },
        legend: { data: [chart.mnemonic], left: 10 },
        toolbox: { feature: { dataZoom: { yAxisIndex: 'none' }, restore: {}, saveAsImage: {} } },
        axisPointer: { link: [{ xAxisIndex: 'all' }] },
        dataZoom: [
            { show: true, realtime: true, start: 70, end: 100, xAxisIndex: [0] },
            { type: 'inside', realtime: true, start: 70, end: 100, xAxisIndex: [0] }
        ],
        grid: [
            { left: 60, right: 50, height: '35%' },
            { left: 60, right: 50, top: '55%', height: '35%' }
        ],                      
        xAxis: {
            type: 'category',
            data: chart.x // Datastar-Signal liefert direkt das JS-Array
        },
        yAxis: {
            type: 'log',
            min: 'dataMin',
            max: 'dataMax'
        },
        series: [
            {
                name: chart.mnemonic,
                type: 'line',
                data: chart.y // Datastar-Signal liefert direkt das JS-Array
            }
        ]
    };
    myChart.setOption(option);
};
