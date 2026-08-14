import React from 'react';

/**
 * 文件状态字母。等宽 + 固定 14px 宽，好让后面的路径左边界对齐成一列；
 * 不固定的话 A/M/D 宽度不同，整列会呈锯齿状。
 * 状态永远同时由字母和颜色表达 —— 只靠颜色的话色盲用户什么都读不到。
 */
const MAP = {
  added: { letter: 'A', color: 'var(--ok)', name: '新增' },
  modified: { letter: 'M', color: 'var(--accent)', name: '修改' },
  deleted: { letter: 'D', color: 'var(--danger)', name: '删除' },
  renamed: { letter: 'R', color: 'var(--merge)', name: '改名' },
  copied: { letter: 'C', color: 'var(--merge)', name: '复制' },
  untracked: { letter: '?', color: 'var(--ink-2)', name: '未跟踪' },
  unmerged: { letter: '!', color: 'var(--warn)', name: '有冲突' },
  ignored: { letter: '·', color: 'var(--ink-4)', name: '已忽略' },
  typechange: { letter: 'T', color: 'var(--accent)', name: '类型变化' },
};

export function StatusLetter({ status, emphasized = false, style }) {
  const entry = MAP[status] || MAP.modified;
  return (
    <span
      title={entry.name}
      style={{
        display: 'inline-block', width: 14, textAlign: 'center', flex: '0 0 auto',
        font: 'var(--type-mono)',
        color: emphasized ? 'var(--selection-fg)' : entry.color, ...style,
      }}
    >
      {entry.letter}
    </span>
  );
}
