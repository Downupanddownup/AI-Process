(function () {
  'use strict';

  const colorMap = {
    '正常推进': '#52c41a',
    '细化完善': '#1890ff',
    '探索发散': '#722ed1',
    '纠偏拉回': '#fa8c16',
    '极端失控': '#f5222d',
    '确认空转': '#8c8c8c',
    '实施确认': '#13c2c2'
  };

  function getJsonPath() {
    const params = new URLSearchParams(window.location.search);
    return params.get('json') || '';
  }

  function toRelativePath(path) {
    if (!path) return '';
    // 如果已经是服务器相对路径（以 / 开头），直接使用
    if (path.charAt(0) === '/') {
      return path;
    }
    // 否则按 Windows 绝对路径处理：去盘符、反斜杠转正斜杠
    let p = path.replace(/\\/g, '/');
    p = p.replace(/^[A-Za-z]:/, '');
    return p;
  }

  async function loadData() {
    const jsonPath = getJsonPath();
    if (!jsonPath) {
      document.getElementById('content').innerHTML = '<div class="error">未指定 JSON 数据源</div>';
      return;
    }

    const relativePath = toRelativePath(jsonPath);
    try {
      const res = await fetch(relativePath);
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const data = await res.json();
      render(data);
    } catch (err) {
      document.getElementById('content').innerHTML = '<div class="error">加载 Summary.json 失败：' + err.message + '</div>';
    }
  }

  function render(data) {
    window.currentData = data;
    document.getElementById('page-title').textContent = '经验总结：' + (data.themeName || '');
    document.getElementById('page-subtitle').textContent = '生成于 ' + (data.generatedAt || '');

    renderOverview(data.overview, data.overview?.totalTime);
    renderKeyMetrics(document.getElementById('key-metrics'), data.metrics);
    renderPieSection(data.metrics);
    renderMetrics(data.metrics);
    renderBreakdown(data.breakdown);
    if (typeof window.renderTimeline === 'function') {
      window.renderTimeline(data);
    }
    if (typeof window.renderAnalysis === 'function') {
      window.renderAnalysis(data.analysis);
    }
  }

  function renderKeyMetrics(container, metrics) {
    if (!metrics || !container) return;

    const byRound = metrics.byRound || {};
    const totalTimeMinutes = metrics.totalTimeMinutes || 0;
    const totalTimeDisplay = formatDuration(totalTimeMinutes);
    const misalignment = (byRound.correction || 0) + (byRound.extreme || 0);

    const items = [
      { label: '总轮数', value: metrics.totalRounds || 0, unit: '轮' },
      { label: '总时长', value: totalTimeDisplay, unit: '' },
      { label: '意图匹配率', value: formatPercent(byRound.intentMatchRate), unit: '' },
      { label: '错位轮数量', value: misalignment, unit: '轮' },
      { label: '失控轮数量', value: byRound.extreme || 0, unit: '轮' }
    ];

    container.innerHTML = '<h2>关键指标</h2>' +
      '<div class="key-metrics-row">' +
      items.map(item => `
        <div class="key-metric-card">
          <div class="label">${escapeHtml(item.label)}</div>
          <div class="value">${escapeHtml(String(item.value))}</div>
          ${item.unit ? `<div class="unit">${escapeHtml(item.unit)}</div>` : ''}
        </div>
      `).join('') +
      '</div>';
  }

  function renderPieSection(metrics) {
    const container = document.getElementById('pie-chart');
    if (!container || !metrics) return;

    container.innerHTML = `
      <h2>分类占比</h2>
      <div id="chart-rounds" class="chart-container" style="height:320px;"></div>
    `;

    if (typeof window.renderPieChart === 'function') {
      window.renderPieChart(
        document.getElementById('chart-rounds'),
        mapMetricsToChinese(metrics.byRound || {}),
        colorMap
      );
    }
  }

  function renderOverview(overview, totalTime) {
    const container = document.getElementById('overview');
    if (!overview) return;

    const tagsHtml = (overview.tags || []).map(t => '<span class="tag">' + escapeHtml(t) + '</span>').join('');

    container.innerHTML = `
      <h2>总览</h2>
      <div class="overview-grid">
        <div class="overview-item">
          <label>摘要</label>
          <div class="value">${escapeHtml(overview.abstract || '')}</div>
          <div class="tags">${tagsHtml}</div>
        </div>
        <div class="overview-item">
          <label>复杂程度</label>
          <div class="value">${escapeHtml(overview.complexity || '')}</div>
          <div style="font-size:12px;color:#6b7280;margin-top:4px;">${escapeHtml(overview.complexityReason || '')}</div>
        </div>
        <div class="overview-item">
          <label>协作顺畅度</label>
          <div class="value">${escapeHtml(overview.collaboration || '')}</div>
          <div style="font-size:12px;color:#6b7280;margin-top:4px;">${escapeHtml(overview.collaborationReason || '')}</div>
        </div>
      </div>
      <div style="margin-top:12px;font-size:14px;color:#6b7280;">
        总耗时：${escapeHtml(totalTime?.display || '')}
      </div>
    `;
  }

  function renderMetrics(metrics) {
    const container = document.getElementById('metrics');
    if (!metrics) return;

    const byRound = metrics.byRound || {};
    const byTime = metrics.byTime || {};
    const byChars = metrics.byChars || {};

    container.innerHTML = `
      <h2>核心指标</h2>
      <div class="metrics-grid">
        ${metricCard('按轮次', byRound.intentMatchRate, byRound)}
        ${metricCard('按时间', byTime.intentMatchRate, byTime, '分钟')}
        ${metricCard('按字数', byChars.intentMatchRate, byChars, '字')}
      </div>
    `;
  }

  function metricCard(title, rate, data, unit) {
    const smooth = data.normal + data.refinement + data.exploration + data.idle;
    const correction = data.correction + data.extreme;
    const totalSmooth = unit ? (data.smoothMinutes || data.smoothHumanChars || 0) : smooth;
    const totalCorrection = unit ? (data.correctionMinutes || data.correctionHumanChars || 0) : correction;
    const totalExtreme = unit ? (data.extremeMinutes || data.extremeHumanChars || 0) : data.extreme;
    const total = totalSmooth + totalCorrection;

    return `
      <div class="metric-card">
        <div class="label">${escapeHtml(title)}</div>
        <div class="value">${formatPercent(rate)}</div>
        <div class="detail">意图匹配率</div>
        <div class="detail" style="margin-top:4px;">
          顺畅 ${totalSmooth}/${total} ${unit || '轮'}，
          纠偏 ${totalCorrection}/${total} ${unit || '轮'}${totalExtreme ? '（含失控 ' + totalExtreme + '）' : ''}
        </div>
      </div>
    `;
  }

  function renderBreakdown(breakdown) {
    const container = document.getElementById('breakdown');
    if (!breakdown) {
      container.style.display = 'none';
      return;
    }
    container.style.display = '';
    if (typeof window.renderBreakdownCharts === 'function') {
      window.renderBreakdownCharts(container, breakdown);
    }
  }

  function renderAnalysis(analysis) {
    const container = document.getElementById('analysis');
    if (!container) return;

    let html = '<h2>纠偏与失控分析</h2>';

    const correctionItems = analysis?.correctionAnalysis?.perRound || [];
    const extremeItems = analysis?.extremeAnalysis?.perRound || [];
    const allItems = correctionItems.map(item => ({ ...item, type: 'correction' }))
      .concat(extremeItems.map(item => ({ ...item, type: 'extreme' })));

    if (allItems.length === 0) {
      container.innerHTML = html + '<div class="empty-tip">本主题未识别到纠偏或失控轮次。</div>';
      return;
    }

    const groups = groupAnalysisBySource(allItems);

    html += '<div class="analysis-groups">';
    Object.entries(groups).forEach(([unit, items]) => {
      html += `
        <div class="analysis-group">
          <div class="analysis-group-title">${escapeHtml(unit)} (${items.length})</div>
          <div class="analysis-grid">
            ${items.map(item => renderAnalysisCard(item, item.type)).join('')}
          </div>
        </div>
      `;
    });
    html += '</div>';

    container.innerHTML = html;
  }

  function groupAnalysisBySource(items) {
    const groups = {};
    items.forEach(item => {
      const source = parseSourceFromSummary(item.summary);
      const key = source.unit;
      if (!groups[key]) {
        groups[key] = [];
      }
      groups[key].push(item);
    });
    return groups;
  }

  function parseSourceFromSummary(summary) {
    if (!summary) return { unit: '未知', unitRoundIndex: '-' };
    const match = summary.match(/^(主讨论|结果微调\d+|子主题\d+)第(\d+)轮[：:]/);
    if (match) {
      return { unit: match[1], unitRoundIndex: match[2] };
    }
    return { unit: '未知', unitRoundIndex: '-' };
  }

  function buildRoundSourceMap(data) {
    // 已废弃：analysis.perRound 的来源现在直接从 summary 字段解析
    return {};
  }

  function renderAnalysisCard(item, type) {
    const titleClass = type === 'extreme' ? 'extreme' : 'correction';
    const title = type === 'extreme' ? '极端失控' : '纠偏拉回';
    const source = parseSourceFromSummary(item.summary);
    const sourceLabel = source.unit + ' · R' + source.unitRoundIndex;

    return `
      <div class="analysis-card ${titleClass}">
        <h3>${title} · R${item.roundIndex}</h3>
        <div class="meta">来源：${escapeHtml(sourceLabel)}</div>
        <p><span class="label">摘要：</span>${escapeHtml(item.summary || '')}</p>
        ${item.rootCause ? `<p><span class="label">根因：</span>${escapeHtml(item.rootCause)}</p>` : ''}
        ${item.impact ? `<p><span class="label">影响：</span>${escapeHtml(item.impact)}</p>` : ''}
        ${item.trigger ? `<p><span class="label">触发：</span>${escapeHtml(item.trigger)}</p>` : ''}
        ${item.escalation ? `<p><span class="label">升级：</span>${escapeHtml(item.escalation)}</p>` : ''}
        ${item.resolution ? `<p><span class="label">解决：</span>${escapeHtml(item.resolution)}</p>` : ''}
        <p><span class="label">经验：</span>${escapeHtml(item.lesson || '')}</p>
      </div>
    `;
  }

  window.renderAnalysis = renderAnalysis;

  function formatPercent(value) {
    if (value === undefined || value === null) return '-';
    return (value * 100).toFixed(0) + '%';
  }

  function formatDuration(minutes) {
    if (!minutes && minutes !== 0) return '-';
    const h = Math.floor(minutes / 60);
    const m = minutes % 60;
    if (h > 0 && m > 0) return `${h}小时\n${m}分钟`;
    if (h > 0) return `${h}小时`;
    return `${m}分钟`;
  }

  function escapeHtml(text) {
    if (text === undefined || text === null) return '';
    return String(text)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  window.addEventListener('DOMContentLoaded', loadData);
  function mapMetricsToChinese(data) {
    return {
      '正常推进': data.normal || 0,
      '细化完善': data.refinement || 0,
      '探索发散': data.exploration || 0,
      '纠偏拉回': data.correction || 0,
      '极端失控': data.extreme || 0,
      '确认空转': data.idle || 0
    };
  }

  window.SummaryViewer = { colorMap, getJsonPath, escapeHtml, formatPercent, formatDuration, mapMetricsToChinese };
})();
