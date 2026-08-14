import React from 'react';

/**
 * 历史列表的日期分组行。
 *
 * 这是本版新加的东西，用来解决「提交列表每一行长得完全一样，眼睛没有落点」。
 * 24px 一条，粘在滚动顶部，只花一行高度换来整列的节奏，
 * 比给每一行加装饰便宜得多，也不动信息密度。
 */
export function DayGroupRow({ label, count, style }) {
  return (
    <div
      style={{
        display: 'flex', alignItems: 'center', gap: 'var(--space-tight)',
        height: 24, padding: '0 var(--space-regular)',
        position: 'sticky', top: 0, zIndex: 1,
        background: 'var(--surface-sunken)',
        borderTop: '1px solid var(--hairline)', borderBottom: '1px solid var(--hairline)',
        font: 'var(--type-secondary)', fontWeight: 'var(--weight-semibold)',
        color: 'var(--ink-2)', ...style,
      }}
    >
      <span>{label}</span>
      {typeof count === 'number' ? (
        <span style={{ color: 'var(--ink-4)', fontWeight: 'var(--weight-regular)', fontVariantNumeric: 'tabular-nums' }}>
          {count}
        </span>
      ) : null}
    </div>
  );
}
