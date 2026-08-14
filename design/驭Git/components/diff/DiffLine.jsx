import React from 'react';

/**
 * diff 里的一行：双列行号 + 标记 + 内容。
 *
 * 语法高亮和行内变化底色是两个正交的维度，叠在一起而不是二选一：
 * 语法色管「这是什么」，行内底色管「这里改了」。只留一个的话，
 * 要么看不出改在哪，要么代码读起来费劲。
 * 选中时两者都关掉 —— 此刻用户关心的是「我选了哪些行」。
 */
const SYNTAX = {
  keyword: 'var(--syn-keyword)', string: 'var(--syn-string)', comment: 'var(--syn-comment)',
  number: 'var(--syn-number)', type: 'var(--syn-type)', plain: 'var(--syn-plain)',
};

export function DiffLine({
  kind = 'context', oldNumber, newNumber, text, segments,
  selected = false, gutterWidth = 34, wrap = false, onClick, style,
}) {
  const [hover, setHover] = React.useState(false);
  const selectable = kind !== 'context';
  const rowBackground = selected
    ? 'color-mix(in srgb, var(--accent) 22%, transparent)'
    : hover && selectable
      ? 'var(--surface-hover)'
      : kind === 'addition' ? 'var(--diff-add-row)' : kind === 'deletion' ? 'var(--diff-del-row)' : 'transparent';
  const marker = kind === 'addition' ? '+' : kind === 'deletion' ? '−' : ' ';
  const markerColor = kind === 'addition' ? 'var(--diff-add-fg)' : kind === 'deletion' ? 'var(--diff-del-fg)' : 'var(--ink-3)';
  const wordBackground = kind === 'addition' ? 'var(--diff-add-word)' : 'var(--diff-del-word)';

  const number = (value) => (
    <span style={{
      flex: '0 0 auto', width: gutterWidth, paddingRight: 6, textAlign: 'right',
      font: 'var(--type-mono)', color: 'var(--ink-3)', fontVariantNumeric: 'tabular-nums',
      userSelect: 'none',
    }}>{value == null ? '' : value}</span>
  );

  return (
    <div
      onClick={selectable && onClick ? onClick : undefined}
      onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
      title={selectable ? '点击选中此行，按住 Shift 可连选' : undefined}
      style={{
        position: 'relative', display: 'flex',
        alignItems: wrap ? 'flex-start' : 'center',
        minHeight: 18, padding: '1px 0', background: rowBackground, ...style,
      }}
    >
      {selected ? (
        <span style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: 3, background: 'var(--accent)' }} />
      ) : null}
      {number(oldNumber)}
      {number(newNumber)}
      <span style={{
        flex: '0 0 auto', width: 14, textAlign: 'center', font: 'var(--type-mono)',
        color: markerColor, userSelect: 'none',
      }}>{marker}</span>
      <code style={{
        font: 'var(--type-mono)', color: 'var(--syn-plain)',
        whiteSpace: wrap ? 'pre-wrap' : 'pre',
        overflowWrap: wrap ? 'anywhere' : 'normal', minWidth: 0,
      }}>
        {segments
          ? segments.map((segment, i) => (
              <span key={i} style={{
                color: selected ? 'inherit' : SYNTAX[segment.syn || 'plain'],
                background: segment.changed && !selected ? wordBackground : 'transparent',
              }}>{segment.text}</span>
            ))
          : text}
      </code>
    </div>
  );
}
