import React from 'react';
import { Icon } from '../core/Icon.jsx';

/**
 * 复制按钮，点完给 1.5 秒的「已复制」反馈。
 * 没有反馈的复制按钮最让人犯嘀咕：什么都没发生，用户会再点两下。
 */
export function CopyButton({ text, title = '复制', onCopy, style }) {
  const [done, setDone] = React.useState(false);
  return (
    <button
      type="button" title={title}
      onClick={() => {
        if (onCopy) onCopy(text);
        else if (navigator.clipboard) navigator.clipboard.writeText(text);
        setDone(true);
        window.setTimeout(() => setDone(false), 1500);
      }}
      style={{
        display: 'inline-flex', border: 'none', background: 'transparent', padding: 2,
        color: done ? 'var(--ok)' : 'var(--ink-2)', cursor: 'default',
        transition: 'color var(--dur-medium) var(--ease-standard)', ...style,
      }}
    >
      <Icon name={done ? 'check' : 'copy'} size={11} />
    </button>
  );
}
