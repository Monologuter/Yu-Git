import React from 'react';
import { Icon } from '../core/Icon.jsx';

/**
 * 横幅。卡在 rebase 半途是 Git 里最容易让人懵的状态：
 * 命令行下只有一段 hint，关掉终端就没了。所以这条横幅只要状态还在就一直挂着，
 * 并且把出路直接做成按钮。它横跨三栏，切到哪一栏都看得见。
 */
const TONES = {
  warn: { fg: 'var(--warn)', bg: 'var(--warn-wash)', icon: 'exclamationmark.triangle' },
  danger: { fg: 'var(--danger)', bg: 'var(--danger-wash)', icon: 'exclamationmark.triangle' },
  info: { fg: 'var(--brand)', bg: 'var(--brand-wash)', icon: 'info.circle' },
  ok: { fg: 'var(--ok)', bg: 'var(--ok-wash)', icon: 'checkmark.circle' },
};

export function Banner({ tone = 'warn', headline, detail, actions, footnote, style }) {
  const skin = TONES[tone];
  return (
    <div
      style={{
        display: 'flex', flexDirection: 'column', gap: 'var(--space-regular)',
        padding: 'var(--space-regular) var(--space-regular)',
        background: skin.bg, borderBottom: '1px solid var(--hairline)', ...style,
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-regular)' }}>
        <Icon name={skin.icon} size={14} color={skin.fg} />
        <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
          <span style={{ font: 'var(--type-callout)', fontWeight: 'var(--weight-medium)', color: 'var(--text-body)' }}>{headline}</span>
          {detail ? <span style={{ font: 'var(--type-secondary)', color: 'var(--ink-2)' }}>{detail}</span> : null}
        </div>
        <span style={{ flex: 1 }} />
        {actions ? <span style={{ display: 'flex', gap: 'var(--space-regular)', flex: '0 0 auto' }}>{actions}</span> : null}
      </div>
      {footnote ? (
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, font: 'var(--type-caption)', color: 'var(--ink-2)' }}>
          <Icon name="shield" size={10} />{footnote}
        </div>
      ) : null}
    </div>
  );
}
