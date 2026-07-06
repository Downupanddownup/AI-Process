(function () {
  'use strict';

  const colorMap = window.SummaryViewer?.colorMap || {
    '正常推进': '#52c41a',
    '细化完善': '#1890ff',
    '探索发散': '#722ed1',
    '纠偏拉回': '#fa8c16',
    '极端失控': '#f5222d',
    '确认空转': '#8c8c8c',
    '实施确认': '#13c2c2'
  };

  window.renderTimeline = function (data) {
    const container = document.getElementById('timeline');
    if (!container) return;

    const rounds = collectRounds(data);
    const phases = data.rounds?.phases || [];

    container.innerHTML = `
      <h2>阶段与轮次</h2>
      ${renderPhasesBar(phases, data.rounds?.items || [])}
      ${renderRoundsTable(rounds)}
    `;
  };

  function collectRounds(data) {
    const list = [];

    (data.rounds?.items || []).forEach(r => {
      list.push({ ...r, source: '根目录' });
    });

    (data.resultFineTunings || []).forEach(unit => {
      const source = '结果微调/' + unit.name;
      (unit.rounds?.items || []).forEach(r => {
        list.push({ ...r, source: source });
      });
    });

    (data.subThemes || []).forEach(unit => {
      const source = '子主题/' + unit.name;
      (unit.rounds?.items || []).forEach(r => {
        list.push({ ...r, source: source });
      });
    });

    return list;
  }

  function getPhaseColor(phase, rootRounds) {
    const indexes = phase.roundIndexes || [];
    for (const idx of indexes) {
      const round = rootRounds.find(r => r.roundIndex === idx);
      if (round && round.category && colorMap[round.category]) {
        return colorMap[round.category];
      }
    }
    return '#999';
  }

  function renderPhasesBar(phases, rootRounds) {
    if (!phases.length) return '';

    const items = phases.map(p => {
      const indexes = p.roundIndexes || [];
      const firstRound = indexes[0];
      const label = indexes.length > 1 ? `R${firstRound}~R${indexes[indexes.length - 1]}` : `R${firstRound}`;
      const color = getPhaseColor(p, rootRounds);
      return `<div class="phase-item" style="background:${color}" data-summary="${escapeHtml(p.summary || '')}" title="${escapeHtml(p.summary || '')}">${escapeHtml(p.name)} (${label})</div>`;
    }).join('');

    return `<div class="phases-bar">${items}</div>`;
  }

  function renderRoundsTable(rounds) {
    if (!rounds.length) return '<p>无轮次数据</p>';

    const rows = rounds.map(r => {
      const category = r.category || '未知';
      const color = colorMap[category] || '#999';
      const duration = r.duration?.display || (r.durationMinutes ? r.durationMinutes + '分钟' : '-');
      return `
        <tr>
          <td>R${r.roundIndex}</td>
          <td><span class="category-badge" style="background:${color}">${escapeHtml(category)}</span></td>
          <td>${escapeHtml(duration)}</td>
          <td class="round-summary">${escapeHtml(r.humanSummary || '')}</td>
          <td class="round-summary">${escapeHtml(r.aiSummary || '')}</td>
          <td class="source-cell">${escapeHtml(r.source)}</td>
        </tr>
      `;
    }).join('');

    return `
      <table class="rounds-table">
        <thead>
          <tr>
            <th>轮次</th>
            <th>类型</th>
            <th>耗时</th>
            <th>用户输入摘要</th>
            <th>AI 回复摘要</th>
            <th>来源</th>
          </tr>
        </thead>
        <tbody>${rows}</tbody>
      </table>
    `;
  }

  function escapeHtml(text) {
    if (text === undefined || text === null) return '';
    return String(text)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }
})();
