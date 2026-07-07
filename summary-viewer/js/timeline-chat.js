(function () {
  'use strict';

  const MAX_LINES = 3;
  const LINE_HEIGHT = 22;

  window.renderChatTimeline = function (container, rounds, options) {
    options = options || {};
    const colorMap = options.colorMap || {};
    const title = options.title || '时间线';

    if (!rounds || !rounds.length) {
      container.innerHTML = '<div class="empty-tip">无轮次数据</div>';
      return;
    }

    container.innerHTML = `
      <div class="chat-timeline-header">
        <h3>${escapeHtml(title)}</h3>
        <span class="round-count">共 ${rounds.length} 轮</span>
      </div>
      <div class="chat-timeline"></div>
    `;

    const timeline = container.querySelector('.chat-timeline');
    rounds.forEach(r => {
      timeline.appendChild(renderRound(r, colorMap));
    });

    applyCollapsing(timeline);
  };

  function renderRound(round, colorMap) {
    const category = round.category || '未知';
    const color = colorMap[category] || '#999';
    const duration = round.duration?.display || (round.durationMinutes ? round.durationMinutes + '分钟' : '-');
    const startTime = round.startTime || '-';

    const el = document.createElement('div');
    el.className = 'chat-round';
    el.innerHTML = `
      <div class="chat-round-header">
        <span class="round-index">R${round.roundIndex}</span>
        <span class="category-badge" style="background:${color}">${escapeHtml(category)}</span>
        <span>${escapeHtml(startTime)}</span>
        <span>耗时 ${escapeHtml(duration)}</span>
        <span>人${round.humanChars || 0}字 / AI${round.aiChars || 0}字</span>
      </div>
      ${renderMessage('human', '用户', round.humanSummary || '')}
      ${renderMessage('ai', 'AI', round.aiSummary || '')}
    `;
    return el;
  }

  function renderMessage(type, speaker, text) {
    const avatar = type === 'human' ? '用户' : 'AI';
    const safeText = escapeHtml(text);
    return `
      <div class="chat-message ${type}">
        <div class="chat-avatar">${avatar}</div>
        <div class="chat-bubble" data-full="${safeText}">
          <div class="content">${safeText}</div>
        </div>
      </div>
    `;
  }

  function applyCollapsing(timeline) {
    const bubbles = timeline.querySelectorAll('.chat-bubble');
    bubbles.forEach(bubble => {
      const content = bubble.querySelector('.content');
      if (!content) return;
      // 简单按行高判断是否需要折叠
      if (content.scrollHeight > MAX_LINES * LINE_HEIGHT) {
        bubble.classList.add('collapsed');
      }
    });
  }

  function escapeHtml(text) {
    if (text === undefined || text === null) return '';
    return String(text)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  // 折叠/展开交互（事件委托）
  document.addEventListener('click', (e) => {
    const bubble = e.target.closest('.chat-bubble');
    if (!bubble) return;
    const content = bubble.querySelector('.content');
    if (!content) return;

    const fullText = bubble.getAttribute('data-full');
    if (bubble.classList.contains('collapsed')) {
      bubble.classList.remove('collapsed');
      content.textContent = fullText;
    }
  });
})();
