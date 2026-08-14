import React from 'react';
import { Icon } from '../core/Icon.jsx';

/**
 * 空状态。
 *
 * 系统的 ContentUnavailableView 一上来就是一个灰色大图标 + 灰字，
 * 每个空状态长得一样，也不告诉人下一步做什么。这里做三件事：
 * 图标放进品牌色的圆底（一屏之内唯一的色块，认得出是驭Git）、
 * 标题说清「现在是什么情况」、说明句给出「下一步做什么」。
 */
export function EmptyState({ icon = 'circle-check', title, description, action, tone = 'brand', compact = false, style }) {
  const fg = tone === 'warn' ? 'var(--warn)' : 'var(--brand)';
  const bg = tone === 'warn' ? 'var(--warn-wash)' : 'var(--brand-wash)';
  return (
    <div
      style={{
        display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
        gap: compact ? 'var(--space-regular)' : 'var(--space-loose)',
        padding: compact ? 'var(--space-section)' : 'var(--space-major)',
        textAlign: 'center', height: '100%', ...style,
      }}
    >
      <span style={{
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        width: compact ? 36 : 48, height: compact ? 36 : 48, borderRadius: '50%',
        background: bg, color: fg,
      }}>
        <Icon name={icon} size={compact ? 18 : 22} />
      </span>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-tight)', maxWidth: 260 }}>
        <span style={{ font: 'var(--type-title)', color: 'var(--text-body)' }}>{title}</span>
        {description ? (
          <span style={{ font: 'var(--type-callout)', color: 'var(--ink-2)', textWrap: 'pretty' }}>{description}</span>
        ) : null}
      </div>
      {action}
    </div>
  );
}
