/* 时间线检查器（右侧 300pt）。
   不只记录「做了什么」，还留着「做之前长什么样」。点一条展开它等价的 git 命令。 */
const { Icon, ToolbarButton, Button, EmptyState } = window.Git_c7d67c;

const HAZARD = {
  none: { icon: 'circle-check', color: 'var(--ink-2)' },
  rewrite: { icon: 'pencil', color: 'var(--merge)' },
  discard: { icon: 'trash-2', color: 'var(--danger)' },
};

function EntryRow({ entry }) {
  const [open, setOpen] = React.useState(false);
  const [hover, setHover] = React.useState(false);
  const skin = HAZARD[entry.hazard] || HAZARD.none;
  return (
    <div
      onClick={() => setOpen(!open)} title="点击查看等价的 git 命令"
      onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
      style={{
        display: 'flex', flexDirection: 'column', gap: 3, padding: '6px var(--space-loose)',
        background: hover ? 'var(--surface-hover)' : 'transparent',
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        <Icon name={skin.icon} size={12} color={entry.failed ? 'var(--warn)' : skin.color} style={{ width: 14 }} />
        <span style={{ font: 'var(--type-body)', minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{entry.summary}</span>
        <span style={{ flex: 1 }} />
        {hover && entry.canUndo ? <Button variant="borderless" size="small">撤销</Button> : null}
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, paddingLeft: 20 }}>
        <span style={{ font: 'var(--type-caption)', color: 'var(--ink-3)' }}>{entry.time}</span>
        {entry.failed ? <span style={{ font: 'var(--type-caption)', color: 'var(--warn)' }}>失败</span> : null}
        {entry.canUndo ? (
          <span style={{ display: 'flex', alignItems: 'center', gap: 1, font: 'var(--type-caption)', color: 'var(--ink-2)' }}>
            <Icon name="undo-2" size={9} />可撤销
          </span>
        ) : null}
      </div>
      {open ? (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4, paddingLeft: 20 }}>
          <code style={{
            display: 'block', padding: 6, borderRadius: 'var(--radius-small)',
            background: 'var(--surface-sunken)', font: 'var(--type-mono)', color: 'var(--ink-2)',
            whiteSpace: 'pre-wrap', overflowWrap: 'anywhere',
          }}>{entry.cmd}</code>
          <span style={{ font: 'var(--type-caption)', color: 'var(--ink-2)' }}>{entry.why}</span>
        </div>
      ) : null}
    </div>
  );
}

function Timeline({ timeline, onClose }) {
  const [hovering, setHovering] = React.useState(null);
  return (
    <div style={{
      width: 'var(--col-inspector)', flex: '0 0 auto', display: 'flex', flexDirection: 'column',
      borderLeft: '1px solid var(--hairline)', background: 'var(--surface-app)', minHeight: 0,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, padding: 'var(--space-loose)' }}>
        <Icon name="rotate-ccw" size={14} color="var(--brand)" />
        <span style={{ font: 'var(--type-title)' }}>时间线</span>
        <span style={{ flex: 1 }} />
        <ToolbarButton icon="refresh-cw" title="刷新时间线" />
        <ToolbarButton icon="x" title="关闭" onClick={onClose} />
      </div>
      <div style={{ borderTop: '1px solid var(--hairline)', overflowY: 'auto', flex: 1, minHeight: 0 }}>
        <div style={{
          height: 22, padding: '0 var(--space-loose)', display: 'flex', alignItems: 'center',
          background: 'var(--surface-sunken)', borderBottom: '1px solid var(--hairline)',
          font: 'var(--type-secondary)', fontWeight: 'var(--weight-semibold)', color: 'var(--ink-2)',
        }}>操作</div>
        {timeline.entries.map((e) => <EntryRow key={e.summary} entry={e} />)}
        <div style={{
          height: 22, padding: '0 var(--space-loose)', display: 'flex', alignItems: 'center',
          background: 'var(--surface-sunken)', borderTop: '1px solid var(--hairline)',
          borderBottom: '1px solid var(--hairline)',
          font: 'var(--type-secondary)', fontWeight: 'var(--weight-semibold)', color: 'var(--ink-2)',
        }}>时间点</div>
        {timeline.snapshots.map((s) => (
          <div
            key={s.summary}
            onMouseEnter={() => setHovering(s.summary)} onMouseLeave={() => setHovering(null)}
            style={{
              display: 'flex', alignItems: 'center', gap: 6, padding: '6px var(--space-loose)',
              background: hovering === s.summary ? 'var(--surface-hover)' : 'transparent',
            }}
          >
            <Icon name="camera" size={12} color="var(--accent)" style={{ width: 14 }} />
            <span style={{ display: 'flex', flexDirection: 'column', gap: 1, minWidth: 0 }}>
              <span style={{ font: 'var(--type-body)' }}>{s.summary}</span>
              <span style={{ font: 'var(--type-caption)', color: 'var(--ink-3)' }}>{s.time}</span>
            </span>
            <span style={{ flex: 1 }} />
            {hovering === s.summary ? <Button variant="borderless" size="small">恢复</Button> : null}
          </div>
        ))}
        <div style={{ padding: 'var(--space-loose)' }}>
          <span style={{ font: 'var(--type-caption)', color: 'var(--ink-3)' }}>
            快照存在 refs/yugit/*，不会混进你的历史。
          </span>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { Timeline });
