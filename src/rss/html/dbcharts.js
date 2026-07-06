window.updateChart = function(chartId, mnemonic, domainName, x, y) {
    console.log("in UpdateChart")
    if (!x || x.length === 0) return;
    var chartDom = document.getElementById(chartId);
    if (!chartDom) return;
    console.log("have chartDom")
    // 2. Bestehende Instanz holen oder neu erstellen
    var myChart = echarts.getInstanceByDom(chartDom);
    if (!myChart) {
        myChart = echarts.init(chartDom);
    }
    // 3. Optionen setzen (ECharts merged das automatisch)
    var option = {
        title: { text: mnemonic},
        tooltip: { trigger: 'axis', axisPointer: { animation: false } },
        legend: { data: [mnemonic], left: 10 },
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
            data: x // Datastar-Signal liefert direkt das JS-Array
        },
        yAxis: {
            type: 'log',
            min: 'dataMin',
            max: 'dataMax'
        },
        series: [
            {
                name: mnemonic,
                type: 'line',
                data: y // Datastar-Signal liefert direkt das JS-Array
            }
        ]
    };
    myChart.setOption(option);
};
