import React from 'react';
import { Icon } from '../core/Icon.jsx';

/** 分支的 ahead / behind 指示。upstream 被删了单独警示 —— 那会让 push 直接失败。 */
export function TrackingBadge({ ahead = 0, behind = 0, gone = false, emphasized = false, style }) {
  if (gone) {
    return (
      <span
        title="upstream 已在远程被删除"
        style={{ display: 'inline-flex', color: emphasized ? 'var(--selection-fg)' : 'var(--warn)', ...style }}
      >
        <Icon name="triangle-alert" size={11} />
      </span>
    );
  }
  if (!ahead && !behind) return null;
  return (
    <span
      title={'领先 ' + ahead + '，落后 ' + behind}
      style={{
        display: 'inline-flex', alignItems: 'center', gap: 5, font: 'var(--type-caption)',
        color: emphasized ? 'var(--selection-fg)' : 'var(--ink-2)',
        fontVariantNumeric: 'tabular-nums', ...style,
      }}
    >
      {ahead ? (
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 1 }}>
          <Icon name="arrow-up" size={9} />{ahead}
        </span>
      ) : null}
      {behind ? (
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 1 }}>
          <Icon name="arrow-down" size={9} />{behind}
        </span>
      ) : null}
    </span>
  );
}
