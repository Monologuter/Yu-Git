import React from 'react';

/** 工具栏上的传输进度。数字用等宽，避免每帧宽度跳动。 */
const SPIN_ID = 'yugit-spin-keyframes';

export function TransferIndicator({ label, style }) {
  React.useEffect(() => {
    if (document.getElementById(SPIN_ID)) return;
    const tag = document.createElement('style');
    tag.id = SPIN_ID;
    tag.textContent = '@keyframes yugit-spin{to{transform:rotate(360deg)}}';
    document.head.appendChild(tag);
  }, []);
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, ...style }}>
      <span style={{
        width: 12, height: 12, borderRadius: '50%',
        border: '1.5px solid var(--hairline-strong)', borderTopColor: 'var(--ink-2)',
        animation: 'yugit-spin 0.7s linear infinite',
      }} />
      {label ? (
        <span style={{ font: 'var(--type-secondary)', color: 'var(--ink-2)', fontVariantNumeric: 'tabular-nums' }}>{label}</span>
      ) : null}
    </span>
  );
}
