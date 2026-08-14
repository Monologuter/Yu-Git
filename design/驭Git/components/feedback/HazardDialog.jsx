import React from 'react';
import { Icon } from '../core/Icon.jsx';

/**
 * 危险操作预警。一次答完三个问题：会发生什么、能不能撤销、怎么撤销。
 * 再附上等价的 git 命令（透明命令层）—— 这个 app 教你 Git，而不是把 Git 藏起来。
 */
export function HazardDialog({ title, whatHappens, undoable, howToUndo, command, confirmLabel, onConfirm, onCancel, style }) {
  return (
    <div
      style={{
        display: 'flex', flexDirection: 'column', gap: 'var(--space-section)',
        width: 460, padding: 'var(--space-major)',
        background: 'var(--surface-raised)', borderRadius: 'var(--radius-large)',
        boxShadow: 'var(--shadow-sheet)', ...style,
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-regular)' }}>
        <Icon name="triangle-alert" size={18} color="var(--warn)" />
        <span style={{ font: 'var(--type-title)', color: 'var(--text-body)' }}>{title}</span>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-loose)' }}>
        {[['会发生什么', whatHappens], ['能不能撤销', undoable], ['怎么撤销', howToUndo]].map(([label, value]) =>
          value ? (
            <div key={label} style={{ display: 'flex', gap: 'var(--space-loose)' }}>
              <span style={{
                flex: '0 0 auto', width: 72, textAlign: 'right',
                font: 'var(--type-secondary)', color: 'var(--ink-2)', paddingTop: 1,
              }}>{label}</span>
              <span style={{ font: 'var(--type-callout)', color: 'var(--text-body)', textWrap: 'pretty' }}>{value}</span>
            </div>
          ) : null
        )}
      </div>

      {command ? (
        <code style={{
          display: 'block', padding: 'var(--space-regular) var(--space-loose)',
          borderRadius: 'var(--radius-medium)', background: 'var(--surface-sunken)',
          font: 'var(--type-mono)', color: 'var(--ink-2)', overflowX: 'auto', whiteSpace: 'pre',
        }}>{command}</code>
      ) : null}

      <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 'var(--space-regular)' }}>
        <button
          type="button" onClick={onCancel}
          style={{
            height: 24, padding: '0 12px', borderRadius: 'var(--radius-medium)',
            border: '1px solid var(--border-control)', background: 'var(--surface-app)',
            font: 'var(--type-body)', color: 'var(--text-body)', cursor: 'default',
          }}
        >取消</button>
        <button
          type="button" onClick={onConfirm}
          style={{
            height: 24, padding: '0 12px', borderRadius: 'var(--radius-medium)', border: 'none',
            background: 'var(--danger)', color: '#FFFFFF',
            font: 'var(--type-body)', fontWeight: 'var(--weight-medium)', cursor: 'default',
          }}
        >{confirmLabel}</button>
      </div>
    </div>
  );
}
