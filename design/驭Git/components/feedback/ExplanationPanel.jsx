import React from 'react';
import { Icon } from '../core/Icon.jsx';

/**
 * 「用中文讲讲这是什么」面板。
 * 默认收起，展开一次才发一次请求 —— AI 铁律：只有用户主动要，才把内容发出去。
 * 没配 AI 时整块不出现，界面上不留任何 AI 痕迹。
 */
export function ExplanationPanel({ title, text, loading = false, expanded, onToggle, error, style }) {
  const [inner, setInner] = React.useState(false);
  const open = expanded === undefined ? inner : expanded;
  const toggle = () => (onToggle ? onToggle(!open) : setInner(!open));
  return (
    <div
      style={{
        display: 'flex', flexDirection: 'column', gap: 'var(--space-regular)',
        padding: 'var(--space-loose)', borderRadius: 8, background: 'var(--surface-sunken)', ...style,
      }}
    >
      <button
        type="button" onClick={toggle}
        style={{
          display: 'flex', alignItems: 'center', gap: 6, border: 'none', background: 'transparent',
          padding: 0, cursor: 'default', color: 'var(--text-body)',
        }}
      >
        <Icon name="sparkles" size={13} color="var(--brand)" />
        <span style={{ font: 'var(--type-callout)', fontWeight: 'var(--weight-medium)' }}>{title}</span>
        <span style={{ flex: 1 }} />
        <Icon name={open ? 'chevron-up' : 'chevron-down'} size={11} color="var(--ink-2)" />
      </button>
      {open ? (
        error ? (
          <div style={{ display: 'flex', gap: 6, font: 'var(--type-callout)', color: 'var(--warn)' }}>
            <Icon name="triangle-alert" size={12} />{error}
          </div>
        ) : loading && !text ? (
          <span style={{ font: 'var(--type-callout)', color: 'var(--ink-2)' }}>正在阅读改动…</span>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-regular)' }}>
            <span style={{ font: 'var(--type-callout)', color: 'var(--text-body)', textWrap: 'pretty' }}>{text}</span>
            {!loading ? (
              <span style={{ display: 'flex', alignItems: 'center', gap: 5, font: 'var(--type-caption)', color: 'var(--ink-3)' }}>
                <Icon name="info" size={10} />AI 生成的解释可能有误，请以代码为准
              </span>
            ) : null}
          </div>
        )
      ) : null}
    </div>
  );
}
