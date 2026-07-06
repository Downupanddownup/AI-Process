(function () {
  'use strict';

  const categoryOrder = ['正常推进', '细化完善', '探索发散', '纠偏拉回', '极端失控', '确认空转', '实施确认'];

  function initChart(container) {
    if (typeof echarts === 'undefined') {
      container.innerHTML = '<div class="error">ECharts 未加载</div>';
      return null;
    }
    return echarts.init(container);
  }

  window.renderPieChart = function (container, data, colorMap) {
    const chart = initChart(container);
    if (!chart) return;

    const items = categoryOrder
      .filter(k => data[k] > 0)
      .map(k => ({ value: data[k], name: k, itemStyle: { color: colorMap[k] || '#999' } }));

    chart.setOption({
      tooltip: { trigger: 'item', formatter: '{b}: {c} ({d}%)' },
      legend: { orient: 'vertical', left: 'left', top: 'center' },
      series: [{
        type: 'pie',
        radius: ['40%', '70%'],
        center: ['65%', '50%'],
        avoidLabelOverlap: false,
        itemStyle: { borderRadius: 4, borderColor: '#fff', borderWidth: 2 },
        label: { show: false },
        emphasis: { label: { show: true, fontSize: 14, fontWeight: 'bold' } },
        data: items
      }]
    });

    window.addEventListener('resize', () => chart.resize());
  };

  window.renderBarChart = function (container, data) {
    const chart = initChart(container);
    if (!chart) return;

    chart.setOption({
      tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' } },
      grid: { left: '3%', right: '4%', bottom: '3%', containLabel: true },
      xAxis: { type: 'category', data: ['轮次', '时长(分)', '人输字数', 'AI字数'] },
      yAxis: { type: 'value' },
      series: [
        { name: '主讨论', type: 'bar', stack: 'total', data: [data.main.rounds, data.main.timeMinutes, data.main.humanChars, data.main.aiChars], itemStyle: { color: '#1890ff' } },
        { name: '结果微调', type: 'bar', stack: 'total', data: [data.resultFineTunings.rounds, data.resultFineTunings.timeMinutes, data.resultFineTunings.humanChars, data.resultFineTunings.aiChars], itemStyle: { color: '#faad14' } },
        { name: '子主题', type: 'bar', stack: 'total', data: [data.subThemes.rounds, data.subThemes.timeMinutes, data.subThemes.humanChars, data.subThemes.aiChars], itemStyle: { color: '#52c41a' } }
      ]
    });

    window.addEventListener('resize', () => chart.resize());
  };

  window.renderGauge = function (container, value, label) {
    const chart = initChart(container);
    if (!chart) return;

    chart.setOption({
      series: [{
        type: 'gauge',
        startAngle: 180,
        endAngle: 0,
        min: 0,
        max: 1,
        splitNumber: 5,
        axisLine: { lineStyle: { width: 8, color: [[value, '#52c41a'], [1, '#f0f0f0']] } },
        pointer: { show: false },
        axisTick: { show: false },
        splitLine: { show: false },
        axisLabel: { show: false },
        title: { offsetCenter: [0, '-20%'], fontSize: 14 },
        detail: { valueAnimation: true, formatter: '{value0%}', fontSize: 28, offsetCenter: [0, '10%'] },
        data: [{ value: value, name: label }]
      }]
    });

    window.addEventListener('resize', () => chart.resize());
  };
})();
