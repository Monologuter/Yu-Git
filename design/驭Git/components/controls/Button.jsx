import React from 'react';
import { Icon } from '../core/Icon.jsx';

/**
 * 按钮。对应 SwiftUI 的 .bordered / .borderless / .plain 三种 buttonStyle
 * 加上 keyboardShortcut(.defaultAction) 那一档（variant="default"）。
 * 高度按 controlSize 走 20 / 24 / 32，不是随手取的：和系统控件同高才能排在一行里。
 */
const HEIGHT = { small: 20, regular: 24, large: 32 };
const FONT = { small: 'var(--text-size-secondary)', regular: 'var(--text-size-body)', large: 'var(--text-size-body)' };
const PAD = { small: 8, regular: 10, large: 14 };

export function Button({
  children, variant = 'bordered', size = 'regular', icon,
  disabled = false, fullWidth = false, onClick, title, style, ...rest
}) {
  const [pressed, setPressed] = React.useState(false);
  const base = {
    display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
    gap: 'var(--space-tight)', height: HEIGHT[size], padding: '0 ' + PAD[size] + 'px',
    font: 'var(--type-body)', fontSize: FONT[size], fontWeight: 'var(--weight-regular)',
    borderRadius: 'var(--radius-medium)', border: '1px solid transparent',
    background: 'transparent', color: 'var(--text-body)', cursor: disabled ? 'default' : 'default',
    opacity: disabled ? 0.4 : 1, whiteSpace: 'nowrap',
    width: fullWidth ? '100%' : undefined,
    transition: 'background var(--dur-fast) var(--ease-standard)',
    WebkitFontSmoothing: 'antialiased',
  };
  const skins = {
    bordered: {
      background: pressed ? 'var(--surface-press)' : 'var(--surface-app)',
      borderColor: 'var(--border-control)',
      boxShadow: '0 0.5px 1px rgba(0,0,0,0.04)',
    },
    default: {
      background: pressed ? 'var(--brand-hover)' : 'var(--accent)',
      borderColor: 'transparent', color: 'var(--text-on-accent)',
      fontWeight: 'var(--weight-medium)',
    },
    borderless: {
      background: pressed ? 'var(--surface-press)' : 'transparent',
      color: 'var(--accent)', padding: '0 ' + (PAD[size] - 6) + 'px',
    },
    destructive: {
      background: pressed ? 'var(--surface-press)' : 'transparent',
      color: 'var(--danger)', padding: '0 ' + (PAD[size] - 6) + 'px',
    },
  };
  return (
    <button
      type="button" title={title} disabled={disabled} onClick={disabled ? undefined : onClick}
      onMouseDown={() => setPressed(true)} onMouseUp={() => setPressed(false)}
      onMouseLeave={() => setPressed(false)}
      style={{ ...base, ...skins[variant], ...style }} {...rest}
    >
      {icon ? <Icon name={icon} size={size === 'small' ? 11 : 13} /> : null}
      {children}
    </button>
  );
}
