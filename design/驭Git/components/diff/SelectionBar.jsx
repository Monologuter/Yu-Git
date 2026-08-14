import React from 'react';

/** 有行被选中时出现的操作条。半透明材质，压在 diff 顶部。 */
export function SelectionBar({ count, primaryLabel = '暂存选中的行', onApply, onClear, style }) {
  return (
    <div
      style={{
        display: 'flex', alignItems: 'center', gap: 'var(--space-loose)',
        padding: '6px var(--space-loose)',
        background: 'var(--surface-sidebar)', backdropFilter: 'var(--blur-overlay)',
        WebkitBackdropFilter: 'var(--blur-overlay)',
        borderBottom: '1px solid var(--hairline)',
        font: 'var(--type-callout)', color: 'var(--text-body)', ...style,
      }}
    >
      <span>已选 {count} 行</span>
      <span style={{ flex: 1 }} />
      <button
        type="button" onClick={onClear}
        style={{ border: 'none', background: 'transparent', font: 'var(--type-callout)', color: 'var(--accent)', cursor: 'default' }}
      >清除选择</button>
      <button
        type="button" onClick={onApply}
        style={{
          height: 22, padding: '0 10px', border: 'none', borderRadius: 'var(--radius-medium)',
          background: 'var(--accent)', color: 'var(--text-on-accent)',
          font: 'var(--type-callout)', fontWeight: 'var(--weight-medium)', cursor: 'default',
        }}
      >{primaryLabel}</button>
    </div>
  );
}
