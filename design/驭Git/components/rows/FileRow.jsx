import React from 'react';
import { StatusLetter } from '../badges/StatusLetter.jsx';

/**
 * 变更列表里的一行文件。
 * 文件名从中间截断（两头都有信息：开头是模块，结尾是文件名）；
 * 目录副行从头部截断，最后一段离文件最近，也最能说明这是哪个目录。
 * 平铺模式才显示目录 —— 树里目录已经由缩进表达了，再显示一遍是噪音。
 */
export function FileRow({
  status, name, directory, selected = false, depth = 0, onClick, title, style,
}) {
  const [hover, setHover] = React.useState(false);
  return (
    <div
      onClick={onClick} title={title || name}
      onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
      style={{
        display: 'flex', alignItems: 'center', gap: 'var(--space-regular)',
        minHeight: directory ? 38 : 30, padding: '4px var(--space-regular)',
        paddingLeft: 'calc(var(--space-regular) + ' + depth * 12 + 'px)',
        borderRadius: 'var(--radius-small)',
        background: selected ? 'var(--selection-bg)' : hover ? 'var(--surface-hover)' : 'transparent',
        color: selected ? 'var(--selection-fg)' : 'var(--text-body)', ...style,
      }}
    >
      <StatusLetter status={status} emphasized={selected} />
      <span style={{ display: 'flex', flexDirection: 'column', gap: 1, minWidth: 0, flex: 1 }}>
        <span style={{
          font: 'var(--type-body)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
        }}>{name}</span>
        {directory ? (
          <span style={{
            font: 'var(--type-caption)',
            color: selected ? 'color-mix(in srgb, var(--selection-fg) 78%, transparent)' : 'var(--ink-2)',
            overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', direction: 'rtl', textAlign: 'left',
          }}>{directory}</span>
        ) : null}
      </span>
    </div>
  );
}
