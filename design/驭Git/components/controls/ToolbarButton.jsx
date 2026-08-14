import React from 'react';
import { Icon } from '../core/Icon.jsx';

/**
 * 窗口工具栏上的图标按钮。
 * 工具栏可用宽度是被三栏分掉的剩余空间，比看上去窄得多 ——
 * 所以这里只放图标，文字进 title。
 */
export function ToolbarButton({ icon, title, disabled = false, active = false, onClick, badge, style }) {
  const [hover, setHover] = React.useState(false);
  return (
    <button
      type="button" title={title} disabled={disabled} onClick={disabled ? undefined : onClick}
      onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
      style={{
        position: 'relative', display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        width: 28, height: 24, border: 'none', borderRadius: 'var(--radius-small) ',
        background: active ? 'var(--surface-press)' : hover && !disabled ? 'var(--surface-hover)' : 'transparent',
        color: active ? 'var(--text-body)' : 'var(--ink-2)',
        opacity: disabled ? 0.35 : 1, cursor: 'default', padding: 0,
        transition: 'background var(--dur-fast) var(--ease-standard)', ...style,
      }}
    >
      <Icon name={icon} size={16} />
      {badge ? (
        <span style={{
          position: 'absolute', top: 1, right: 1, width: 6, height: 6, borderRadius: '50%',
          background: 'var(--warn)',
        }} />
      ) : null}
    </button>
  );
}
