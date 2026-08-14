import React from 'react';

/**
 * 图标。SF Symbols 的替身 —— 见 Icon.prompt.md 里的替换说明与映射表。
 * 用 mask 而不是 <img>：这样 backgroundColor 走 currentColor，
 * 图标颜色跟着文字走，和 SF Symbols 的行为一致。
 */
const DEFAULT_BASE = '../../assets/icons/';

export function Icon({ name, size = 14, color = 'currentColor', title, style, ...rest }) {
  const base = (typeof window !== 'undefined' && window.YUGIT_ICON_BASE) || DEFAULT_BASE;
  const url = 'url("' + base + name + '.svg")';
  return (
    <span
      title={title}
      aria-hidden={title ? undefined : true}
      style={{
        display: 'inline-block',
        flex: '0 0 auto',
        width: size,
        height: size,
        backgroundColor: color,
        maskImage: url,
        WebkitMaskImage: url,
        maskSize: 'contain',
        WebkitMaskSize: 'contain',
        maskRepeat: 'no-repeat',
        WebkitMaskRepeat: 'no-repeat',
        maskPosition: 'center',
        WebkitMaskPosition: 'center',
        ...style,
      }}
      {...rest}
    />
  );
}
