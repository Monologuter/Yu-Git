import React from 'react';
import { Icon } from '../core/Icon.jsx';
import { LaneGraph } from '../graph/LaneGraph.jsx';
import { RefBadge } from '../badges/RefBadge.jsx';

/**
 * 历史列表里的一行：分支图 + 两行文字。行高 44。
 *
 * 元信息拆成三个独立文本而不是拼成一个字符串：拼字符串省事，但那样三样东西
 * 必然同字号同颜色 —— 想让 hash 更淡、时间右对齐都做不到，眼睛扫下来也分不出
 * 哪个重要。时间右对齐：不这么做，每行的视觉右边界随作者名长短参差不齐。
 */
export function CommitRow({
  subject, hash, author, date, refs = [], isMerge = false, isHead = false,
  graphRow, laneCount = 1, selected = false, onClick, style,
}) {
  const [hover, setHover] = React.useState(false);
  const background = selected ? 'var(--selection-bg)' : hover ? 'var(--surface-hover)' : 'var(--surface-app)';
  const faded = selected ? 'color-mix(in srgb, var(--selection-fg) 72%, transparent)' : 'var(--ink-3)';
  return (
    <div
      onClick={onClick}
      onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
      style={{
        display: 'flex', alignItems: 'stretch', gap: 'var(--space-regular)',
        height: 44, paddingRight: 'var(--space-regular)', paddingLeft: 'var(--space-tight)',
        background, color: selected ? 'var(--selection-fg)' : 'var(--text-body)', ...style,
      }}
    >
      {graphRow ? (
        <LaneGraph
          row={graphRow} laneCount={laneCount} height={44}
          emphasized={selected} rowBackground={background}
        />
      ) : null}
      <div style={{ display: 'flex', flexDirection: 'column', justifyContent: 'center', gap: 2, minWidth: 0, flex: 1 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, minWidth: 0 }}>
          {isMerge ? (
            <Icon name="arrow.triangle.merge" size={11} title="合并提交" color={selected ? 'var(--selection-fg)' : 'var(--merge)'} />
          ) : null}
          <span style={{
            font: 'var(--type-body)', minWidth: 0, overflow: 'hidden',
            textOverflow: 'ellipsis', whiteSpace: 'nowrap',
          }}>{subject}</span>
          {refs.length ? (
            <span style={{ display: 'flex', gap: 4, flex: '0 0 auto' }}>
              {refs.map((ref, i) => (
                <RefBadge key={i} kind={ref.kind} emphasized={selected}>{ref.name}</RefBadge>
              ))}
            </span>
          ) : null}
        </div>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 'var(--space-regular)', minWidth: 0 }}>
          <span style={{ font: 'var(--type-mono)', color: faded, flex: '0 0 auto' }}>{hash}</span>
          <span style={{
            font: 'var(--type-secondary)',
            color: selected ? 'color-mix(in srgb, var(--selection-fg) 85%, transparent)' : 'var(--ink-2)',
            minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
          }}>{author}</span>
          <span style={{ flex: 1 }} />
          <span style={{ font: 'var(--type-secondary)', color: faded, flex: '0 0 auto' }}>{date}</span>
        </div>
      </div>
    </div>
  );
}
