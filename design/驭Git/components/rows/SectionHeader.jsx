import React from 'react';

/**
 * 列表分组头：标题（带计数）+ 右侧动作。
 * 动作只在悬停时出现 —— 每个分组后面常挂一个按钮会很吵。
 * 文案照实说数量：筛选时是「暂存这 12 个」，不是「全部暂存」。
 */
export function SectionHeader({ title, count, tone = 'neutral', action, sticky = true, style }) {
  const [hover, setHover] = React.useState(false);
  return (
    <div
      onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
      style={{
        display: 'flex', alignItems: 'center', gap: 'var(--space-tight)',
        height: 22, padding: '0 var(--space-regular)',
        position: sticky ? 'sticky' : 'static', top: 0, zIndex: 1,
        background: 'var(--surface-sunken)',
        borderBottom: '1px solid var(--hairline)',
        font: 'var(--type-secondary)', fontWeight: 'var(--weight-semibold)',
        color: tone === 'warn' ? 'var(--warn)' : 'var(--ink-2)', ...style,
      }}
    >
      <span>{title}{typeof count === 'number' ? '（' + count + '）' : ''}</span>
      <span style={{ flex: 1 }} />
      <span style={{ visibility: hover && action ? 'visible' : 'hidden' }}>{action}</span>
    </div>
  );
}
