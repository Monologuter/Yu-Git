import React from 'react';
import { Icon } from '../core/Icon.jsx';
import { TrackingBadge } from '../badges/TrackingBadge.jsx';

/**
 * 侧栏里的一行分支。
 * 当前分支：名字加粗 + 图标换品牌青 + 左侧一根 2px 品牌色标记。
 * 「我现在在哪个分支上」是侧栏里最高频要确认的一件事，光靠加粗还不够快。
 * 名字从中间截断：origin/feature/... 两头都有信息。
 */
export function BranchRow({
  name, isRemote = false, isCurrent = false, selected = false,
  ahead = 0, behind = 0, gone = false, title, onClick, style,
}) {
  const [hover, setHover] = React.useState(false);
  return (
    <div
      onClick={onClick} title={title || name}
      onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
      style={{
        position: 'relative', display: 'flex', alignItems: 'center', gap: 6,
        height: 24, padding: '0 var(--space-regular)', borderRadius: 'var(--radius-medium)',
        background: selected ? 'var(--selection-bg)' : hover ? 'var(--surface-hover)' : 'transparent',
        color: selected ? 'var(--selection-fg)' : 'var(--text-body)', ...style,
      }}
    >
      {isCurrent && !selected ? (
        <span style={{
          position: 'absolute', left: 0, top: 5, bottom: 5, width: 2,
          borderRadius: 2, background: 'var(--brand)',
        }} />
      ) : null}
      <Icon
        name={isRemote ? 'cloud' : 'git-branch'} size={12}
        color={selected ? 'var(--selection-fg)' : isCurrent ? 'var(--brand)' : 'var(--ink-2)'}
      />
      <span style={{
        flex: 1, minWidth: 0, font: 'var(--type-body)',
        fontWeight: isCurrent ? 'var(--weight-semibold)' : 'var(--weight-regular)',
        overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', direction: 'rtl', textAlign: 'left',
      }}>{name}</span>
      <TrackingBadge ahead={ahead} behind={behind} gone={gone} emphasized={selected} />
    </div>
  );
}
