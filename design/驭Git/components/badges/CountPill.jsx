import React from 'react';

/** 计数胶囊。跟在标题后面说明「有几个」，不参与点击。 */
export function CountPill({ children, tone = 'neutral', style }) {
  const warn = tone === 'warn';
  return (
    <span
      style={{
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center', minWidth: 16,
        padding: '1px 5px', borderRadius: 'var(--radius-capsule)',
        font: 'var(--type-secondary)', fontVariantNumeric: 'tabular-nums',
        background: warn ? 'var(--warn-wash)' : 'var(--fill-quaternary)',
        color: warn ? 'var(--warn)' : 'var(--ink-2)', ...style,
      }}
    >
      {children}
    </span>
  );
}
