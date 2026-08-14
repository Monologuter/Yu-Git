import React from 'react';

/** hunk 头，兼作「暂存此块」的入口。悬停才显示按钮，避免密集的按钮干扰阅读。 */
export function HunkHeader({ header, action, sticky = true, style }) {
  const [hover, setHover] = React.useState(false);
  return (
    <div
      onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
      style={{
        display: 'flex', alignItems: 'center', gap: 'var(--space-regular)',
        padding: '4px var(--space-loose)', background: 'var(--surface-sunken)',
        position: sticky ? 'sticky' : 'static', top: 0, zIndex: 1,
        font: 'var(--type-mono)', color: 'var(--ink-2)', ...style,
      }}
    >
      <span style={{ minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{header}</span>
      <span style={{ flex: 1 }} />
      <span style={{ visibility: hover && action ? 'visible' : 'hidden' }}>{action}</span>
    </div>
  );
}
