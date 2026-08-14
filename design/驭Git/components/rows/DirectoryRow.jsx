import React from 'react';
import { Icon } from '../core/Icon.jsx';

/** 树形变更列表里的目录行。悬停才出现批量暂存按钮。 */
export function DirectoryRow({
  name, count, collapsed = false, depth = 0, action, onToggle, title, style,
}) {
  const [hover, setHover] = React.useState(false);
  return (
    <div
      onClick={onToggle} title={title || name}
      onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
      style={{
        display: 'flex', alignItems: 'center', gap: 6, height: 24,
        padding: '0 var(--space-regular)',
        paddingLeft: 'calc(var(--space-regular) + ' + depth * 12 + 'px)',
        background: hover ? 'var(--surface-hover)' : 'transparent',
        borderRadius: 'var(--radius-small)', color: 'var(--text-body)', ...style,
      }}
    >
      <Icon
        name="chevron.right" size={9} color="var(--ink-2)"
        style={{ transform: collapsed ? 'none' : 'rotate(90deg)', transition: 'transform var(--dur-fast) var(--ease-standard)' }}
      />
      <Icon name="folder" size={12} color="var(--ink-2)" />
      <span style={{
        font: 'var(--type-body)', minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis',
        whiteSpace: 'nowrap', direction: 'rtl', textAlign: 'left',
      }}>{name}</span>
      <span style={{ font: 'var(--type-secondary)', color: 'var(--ink-4)', fontVariantNumeric: 'tabular-nums' }}>{count}</span>
      <span style={{ flex: 1 }} />
      <span style={{ visibility: hover && action ? 'visible' : 'hidden' }}>{action}</span>
    </div>
  );
}
