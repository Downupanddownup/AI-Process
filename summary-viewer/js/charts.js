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
      legend: {
        orient: 'horizontal',
        bottom: 0,
        left: 'center',
        itemWidth: 12,
        itemHeight: 12,
        textStyle: { fontSize: 12 }
      },
      series: [{
        type: 'pie',
        radius: ['42%', '68%'],
        center: ['50%', '48%'],
        avoidLabelOverlap: true,
        itemStyle: { borderRadius: 4, borderColor: '#fff', borderWidth: 2 },
        label: { show: true, formatter: '{b}\n{d}%', fontSize: 11 },
        emphasis: { label: { show: true, fontSize: 13, fontWeight: 'bold' } },
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

  window.renderBreakdownCharts = function (container, data) {
    if (!data || !container) return;

    const units = ['主讨论', '结果微调', '子主题'];
    const keys = ['main', 'resultFineTunings', 'subThemes'];
    const colors = ['#1890ff', '#faad14', '#52c41a'];

    container.innerHTML = `
      <h2>成本拆分</h2>
      <div class="breakdown-grid">
        <div class="breakdown-chart" id="breakdown-rounds"></div>
        <div class="breakdown-chart" id="breakdown-time"></div>
        <div class="breakdown-chart" id="breakdown-chars"></div>
      </div>
    `;

    renderSingleBar(document.getElementById('breakdown-rounds'), '轮次分布', units,
      keys.map((k, i) => ({ name: units[i], value: data[k]?.rounds || 0, itemStyle: { color: colors[i] } })));

    renderSingleBar(document.getElementById('breakdown-time'), '时长分布（分钟）', units,
      keys.map((k, i) => ({ name: units[i], value: data[k]?.timeMinutes || 0, itemStyle: { color: colors[i] } })));

    renderGroupedBar(document.getElementById('breakdown-chars'), '字数分布', units,
      [
        { name: '人输字数', data: keys.map(k => data[k]?.humanChars || 0), color: '#1890ff' },
        { name: 'AI字数', data: keys.map(k => data[k]?.aiChars || 0), color: '#52c41a' }
      ]
    );
  };

  function renderSingleBar(container, title, categories, seriesData) {
    const chart = initChart(container);
    if (!chart) return;

    chart.setOption({
      title: { text: title, left: 'center', textStyle: { fontSize: 13, color: '#666' } },
      tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' } },
      grid: { left: '3%', right: '4%', bottom: '3%', top: '24%', containLabel: true },
      xAxis: { type: 'category', data: categories, axisLabel: { fontSize: 11 } },
      yAxis: { type: 'value', axisLabel: { fontSize: 11 } },
      series: [{ type: 'bar', data: seriesData, barWidth: '50%', label: { show: true, position: 'top', fontSize: 11 } }]
    });

    window.addEventListener('resize', () => chart.resize());
  }

  function renderGroupedBar(container, title, categories, seriesList) {
    const chart = initChart(container);
    if (!chart) return;

    chart.setOption({
      title: { text: title, left: 'center', textStyle: { fontSize: 13, color: '#666' } },
      tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' } },
      legend: { bottom: 0, textStyle: { fontSize: 11 } },
      grid: { left: '3%', right: '4%', bottom: '16%', top: '24%', containLabel: true },
      xAxis: { type: 'category', data: categories, axisLabel: { fontSize: 11 } },
      yAxis: { type: 'value', axisLabel: { fontSize: 11 } },
      series: seriesList.map(s => ({
        name: s.name,
        type: 'bar',
        data: s.data,
        itemStyle: { color: s.color },
        label: { show: true, position: 'top', fontSize: 10 }
      }))
    });

    window.addEventListener('resize', () => chart.resize());
  }

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
