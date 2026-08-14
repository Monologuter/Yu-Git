/* 窗口工具栏。红绿灯 + 仓库名/分支 + 远程三件套 + 更多。
   工具栏只留四项：可用宽度是被三栏分掉的剩余空间，比看上去窄得多。 */
const { ToolbarButton, TransferIndicator, Icon } = window.Git_c7d67c;

function TrafficLights() {
  const dot = (color) => ({ width: 12, height: 12, borderRadius: '50%', background: color });
  return (
    <div style={{ display: 'flex', gap: 8, paddingRight: 6 }}>
      <span style={dot('#FF5F57')} /><span style={dot('#FEBC2E')} /><span style={dot('#28C840')} />
    </div>
  );
}

function Toolbar({ repo, branch, transferring, onFetch, onPull, onPush, onPalette, onTimeline, timelineOpen, onToggleSidebar, sidebarOpen }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 'var(--space-loose)',
      height: 'var(--toolbar-height)', padding: '0 var(--space-loose) 0 var(--traffic-light-inset)',
      background: 'var(--surface-sidebar)', backdropFilter: 'var(--blur-toolbar)',
      WebkitBackdropFilter: 'var(--blur-toolbar)', borderBottom: '1px solid var(--hairline)',
      flex: '0 0 auto',
    }}>
      <TrafficLights />
      <ToolbarButton icon="panel-left" title={sidebarOpen ? '隐藏侧栏' : '显示侧栏'} onClick={onToggleSidebar} active={sidebarOpen} />
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, paddingLeft: 'var(--space-regular)' }}>
        <ToolbarButton icon="chevron-left" title="回到欢迎页" />
        <div style={{ display: 'flex', flexDirection: 'column', lineHeight: 1.15 }}>
          <span style={{ font: 'var(--type-body)', fontWeight: 'var(--weight-semibold)' }}>{repo}</span>
          <span style={{ display: 'flex', alignItems: 'center', gap: 4, font: 'var(--type-secondary)', color: 'var(--ink-2)' }}>
            <Icon name="git-branch" size={10} color="var(--brand)" />{branch}
          </span>
        </div>
      </div>
      <span style={{ flex: 1 }} />
      {transferring ? <TransferIndicator label="对象 1240 / 3877" /> : null}
      <ToolbarButton icon="circle-arrow-down" title="从远程拉取引用与对象，不改动工作区" disabled={transferring} onClick={onFetch} />
      <ToolbarButton icon="arrow-down-to-line" title="拉取并合并到当前分支" disabled={transferring} onClick={onPull} />
      <ToolbarButton icon="arrow-up-to-line" title="推送到 upstream" disabled={transferring} onClick={onPush} />
      <span style={{ width: 1, height: 20, background: 'var(--hairline)' }} />
      <ToolbarButton icon="rotate-ccw" title="时间线" active={timelineOpen} onClick={onTimeline} />
      <ToolbarButton icon="ellipsis" title="命令面板、搜索、时间线、刷新" onClick={onPalette} />
    </div>
  );
}

Object.assign(window, { Toolbar, TrafficLights });
