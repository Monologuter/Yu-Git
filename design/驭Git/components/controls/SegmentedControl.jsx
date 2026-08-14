import React from 'react';

/**
 * 分段控件。中栏顶部的「变更 N｜历史」就是它。
 * 选中段用强调色填充 + 白字，跟系统 .pickerStyle(.segmented) 一致。
 */
export function SegmentedControl({ items, value, onChange, style }) {
  return (
    <div
      role="tablist"
      style={{
        display: 'flex', gap: 2, padding: 2, borderRadius: 'var(--radius-medium)',
        background: 'var(--fill-quaternary)', border: '1px solid var(--hairline)', ...style,
      }}
    >
      {items.map((item) => {
        const selected = item.value === value;
        return (
          <button
            key={item.value} type="button" role="tab" aria-selected={selected}
            onClick={() => onChange && onChange(item.value)}
            title={item.title}
            style={{
              flex: 1, height: 20, border: 'none', borderRadius: 'var(--radius-small)',
              font: 'var(--type-body)',
              fontWeight: selected ? 'var(--weight-medium)' : 'var(--weight-regular)',
              background: selected ? 'var(--accent)' : 'transparent',
              color: selected ? 'var(--text-on-accent)' : 'var(--text-body)',
              cursor: 'default', whiteSpace: 'nowrap',
              transition: 'background var(--dur-fast) var(--ease-standard)',
            }}
          >
            {item.label}
          </button>
        );
      })}
    </div>
  );
}
