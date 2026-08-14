import React from 'react';
import { Icon } from '../core/Icon.jsx';

/**
 * 过滤框。放在它所影响的那一列的顶部 —— 位置本身说明了它管什么范围，
 * 这也是不用 .searchable 的原因（那会把框放进全窗口共用的工具栏）。
 */
export function FilterField({ value, onChange, placeholder, autoFocus = false, style }) {
  const [focused, setFocused] = React.useState(false);
  const ref = React.useRef(null);
  return (
    <div
      style={{
        display: 'flex', alignItems: 'center', gap: 6, flex: 1, minWidth: 0,
        padding: '5px var(--space-regular)', borderRadius: 'var(--radius-medium)',
        background: 'var(--fill-quaternary)',
        boxShadow: focused ? 'inset 0 0 0 2px var(--border-focus)' : 'none',
        transition: 'box-shadow var(--dur-fast) var(--ease-standard)', ...style,
      }}
    >
      <Icon name="list-filter" size={11} color="var(--ink-2)" />
      <input
        ref={ref} value={value} placeholder={placeholder} autoFocus={autoFocus}
        onChange={(e) => onChange && onChange(e.target.value)}
        onFocus={() => setFocused(true)} onBlur={() => setFocused(false)}
        style={{
          flex: 1, minWidth: 0, border: 'none', outline: 'none', background: 'transparent',
          font: 'var(--type-secondary)', color: 'var(--text-body)',
        }}
      />
      {value ? (
        <button
          type="button" title="清空"
          onClick={() => { onChange && onChange(''); if (ref.current) ref.current.focus(); }}
          style={{
            display: 'flex', border: 'none', background: 'transparent', padding: 0,
            color: 'var(--ink-4)', cursor: 'default',
          }}
        >
          <Icon name="circle-x" size={11} />
        </button>
      ) : null}
    </div>
  );
}
