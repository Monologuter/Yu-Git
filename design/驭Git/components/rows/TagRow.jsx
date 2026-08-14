import React from 'react';
import { Icon } from '../core/Icon.jsx';

/** 侧栏里的一行 tag。轻量 tag 标出来 —— 工程规范要求发布用附注 tag。 */
export function TagRow({ name, annotated = true, selected = false, title, onClick, style }) {
  const [hover, setHover] = React.useState(false);
  return (
    <div
      onClick={onClick} title={title || name}
      onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
      style={{
        display: 'flex', alignItems: 'center', gap: 6, height: 24,
        padding: '0 var(--space-regular)', borderRadius: 'var(--radius-medium)',
        background: selected ? 'var(--selection-bg)' : hover ? 'var(--surface-hover)' : 'transparent',
        color: selected ? 'var(--selection-fg)' : 'var(--text-body)', ...style,
      }}
    >
      <Icon name="tag" size={12} color={selected ? 'var(--selection-fg)' : 'var(--ink-2)'} />
      <span style={{
        flex: 1, minWidth: 0, font: 'var(--type-body)',
        overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
      }}>{name}</span>
      {!annotated ? (
        <span style={{ font: 'var(--type-caption)', color: selected ? 'var(--selection-fg)' : 'var(--ink-4)' }}>轻量</span>
      ) : null}
    </div>
  );
}
