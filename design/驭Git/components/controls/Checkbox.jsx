import React from 'react';
import { Icon } from '../core/Icon.jsx';

/** 复选框。对应 Toggle(.checkbox)，标签 11pt。 */
export function Checkbox({ checked, onChange, label, disabled = false, style }) {
  return (
    <label
      style={{
        display: 'inline-flex', alignItems: 'center', gap: 6,
        font: 'var(--type-secondary)', color: 'var(--text-body)',
        opacity: disabled ? 0.4 : 1, cursor: 'default', ...style,
      }}
    >
      <span
        onClick={() => !disabled && onChange && onChange(!checked)}
        style={{
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          width: 13, height: 13, borderRadius: 3,
          background: checked ? 'var(--accent)' : 'var(--surface-app)',
          border: '1px solid ' + (checked ? 'transparent' : 'var(--border-control)'),
          boxShadow: checked ? 'none' : '0 0.5px 1px rgba(0,0,0,0.04)',
          color: 'var(--text-on-accent)',
        }}
      >
        {checked ? <Icon name="checkmark" size={9} /> : null}
      </span>
      {label}
    </label>
  );
}
