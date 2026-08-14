import React from 'react';

/**
 * commit 上的分支 / tag 徽章。
 * HEAD 不单独画 —— 它总和它指向的分支一起出现，单独一个徽章只是噪音。
 */
const TONE = { local: 'var(--brand)', remote: 'var(--ink-2)', tag: 'var(--warn)' };

export function RefBadge({ kind = 'local', children, emphasized = false, style }) {
  return (
    <span
      style={{
        display: 'inline-flex', alignItems: 'center', maxWidth: 170,
        padding: '1px 5px', borderRadius: 'var(--radius-capsule)',
        font: 'var(--type-caption)',
        color: emphasized ? 'var(--selection-fg)' : TONE[kind],
        background: emphasized
          ? 'color-mix(in srgb, var(--selection-fg) 22%, transparent)'
          : 'color-mix(in srgb, ' + TONE[kind] + ' 15%, transparent)',
        whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', ...style,
      }}
    >
      {children}
    </span>
  );
}
