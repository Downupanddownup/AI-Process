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
    const nav = document.getElementById('timeline-nav');
    const content = document.getElementById('timeline-content');
    if (!container || !nav || !content) return;

    const units = collectUnits(data);

    renderTree(nav, units, (selected) => {
      if (typeof window.renderChatTimeline === 'function') {
        window.renderChatTimeline(content, selected.rounds, { colorMap, title: selected.name });
      } else {
        content.innerHTML = '<div class="error">时间线渲染模块未加载</div>';
      }
    });

    // 默认选中主讨论
    const defaultUnit = units.find(u => u.id === 'main') || units[0];
    if (defaultUnit && typeof window.renderChatTimeline === 'function') {
      window.renderChatTimeline(content, defaultUnit.rounds, { colorMap, title: defaultUnit.name });
    }
  };

  function collectUnits(data) {
    const units = [];
    if (data.rounds?.items?.length) {
      units.push({ id: 'main', name: '主讨论', rounds: data.rounds.items });
    }
    (data.resultFineTunings || []).forEach((unit, idx) => {
      if (unit.rounds?.items?.length) {
        units.push({ id: 'rf-' + idx, name: '结果微调/' + unit.name, rounds: unit.rounds.items, parent: 'resultFineTunings' });
      }
    });
    (data.subThemes || []).forEach((unit, idx) => {
      if (unit.rounds?.items?.length) {
        units.push({ id: 'st-' + idx, name: '子主题/' + unit.name, rounds: unit.rounds.items, parent: 'subThemes' });
      }
    });
    return units;
  }

  function renderTree(nav, units, onSelect) {
    const groups = {
      main: { name: '主讨论', children: [] },
      resultFineTunings: { name: '结果微调', children: [] },
      subThemes: { name: '子主题', children: [] }
    };

    units.forEach(u => {
      if (u.id === 'main') {
        groups.main.children.push(u);
      } else if (u.parent === 'resultFineTunings') {
        groups.resultFineTunings.children.push(u);
      } else {
        groups.subThemes.children.push(u);
      }
    });

    let html = '<ul class="timeline-tree">';
    Object.values(groups).forEach(group => {
      if (!group.children.length) return;
      html += `<li><div class="node group-node">${escapeHtml(group.name)}</div><ul class="children">`;
      group.children.forEach(u => {
        html += `<li><div class="node leaf-node" data-id="${escapeHtml(u.id)}">${escapeHtml(u.name)}</div></li>`;
      });
      html += '</ul></li>';
    });
    html += '</ul>';

    nav.innerHTML = html;

    const leafNodes = nav.querySelectorAll('.leaf-node');
    leafNodes.forEach(node => {
      node.addEventListener('click', () => {
        leafNodes.forEach(n => n.classList.remove('active'));
        node.classList.add('active');
        const id = node.getAttribute('data-id');
        const unit = units.find(u => u.id === id);
        if (unit) onSelect(unit);
      });
    });

    if (leafNodes.length) leafNodes[0].classList.add('active');
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
