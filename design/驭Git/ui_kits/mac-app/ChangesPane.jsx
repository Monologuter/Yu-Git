/* 中栏 · 变更：过滤 + 冲突/已暂存/未暂存三段 + 底部提交面板。 */
const { FilterField, SectionHeader, FileRow, DirectoryRow, Button, Checkbox, EmptyState, Icon, ToolbarButton } = window.Git_c7d67c;

const fileName = (path) => path.split('/').pop();
const dirName = (path) => path.split('/').slice(0, -1).join('/');

function ContextMenu({ x, y, items, onClose }) {
  return (
    <div onClick={onClose} style={{ position: 'fixed', inset: 0, zIndex: 40 }}>
      <div style={{
        position: 'absolute', left: x, top: y, minWidth: 160, padding: 4,
        background: 'var(--surface-raised)', border: '1px solid var(--hairline)',
        borderRadius: 'var(--radius-medium)', boxShadow: 'var(--shadow-popover)',
      }}>
        {items.map((item) => (
          <div
            key={item.label} onClick={item.onClick}
            style={{
              display: 'flex', alignItems: 'center', height: 22, padding: '0 8px',
              borderRadius: 'var(--radius-small)', font: 'var(--type-body)',
              color: item.destructive ? 'var(--danger)' : 'var(--text-body)',
            }}
            onMouseEnter={(e) => { e.currentTarget.style.background = 'var(--surface-hover)'; }}
            onMouseLeave={(e) => { e.currentTarget.style.background = 'transparent'; }}
          >{item.label}</div>
        ))}
      </div>
    </div>
  );
}

function CommitPanel({ message, onMessage, amend, onAmend, staged, onCommit, onDraft, drafting }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 6, padding: 10, borderTop: '1px solid var(--hairline)', flex: '0 0 auto' }}>
      <div style={{ position: 'relative' }}>
        <textarea
          value={message} onChange={(e) => onMessage(e.target.value)} placeholder="提交说明"
          style={{
            width: '100%', height: 72, resize: 'none', boxSizing: 'border-box',
            padding: '6px 8px', borderRadius: 'var(--radius-medium)',
            border: '1px solid var(--hairline-strong)', background: 'var(--surface-app)',
            font: 'var(--type-body)', color: 'var(--text-body)', outline: 'none',
          }}
        />
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-regular)' }}>
        <Checkbox checked={amend} onChange={onAmend} label="修改上一条提交" />
        <span style={{ flex: 1 }} />
        <Button size="small" icon="checkmark.shield" disabled={!staged} title={staged ? '提交前让 AI 通读暂存的改动，按风险分级列出值得确认的地方' : '先暂存一些改动'}>自查</Button>
        <Button size="small" icon="sparkles" onClick={onDraft} disabled={!staged || drafting} title="根据暂存的改动起草提交信息，生成后可直接编辑">{drafting ? '起草中…' : 'AI 起草'}</Button>
        <Button size="small" variant="default" onClick={onCommit} disabled={!staged || !message.trim()}>提交</Button>
      </div>
      {amend ? (
        <span style={{ display: 'flex', alignItems: 'center', gap: 5, font: 'var(--type-caption)', color: 'var(--warn)' }}>
          <Icon name="exclamationmark.triangle" size={10} />修改后 commit hash 会变，若已推送则需要 force push
        </span>
      ) : null}
    </div>
  );
}

function ChangesPane({ fixtures, selected, onSelect, onDiscard, onResolve }) {
  const [filter, setFilter] = React.useState('');
  const [tree, setTree] = React.useState(true);
  const [collapsed, setCollapsed] = React.useState([]);
  const [message, setMessage] = React.useState('');
  const [amend, setAmend] = React.useState(false);
  const [drafting, setDrafting] = React.useState(false);
  const [menu, setMenu] = React.useState(null);

  const { changes } = fixtures;
  const match = (e) => !filter.trim() || e.path.toLowerCase().includes(filter.trim().toLowerCase());
  const staged = changes.staged.filter(match);
  const unstaged = changes.unstaged.filter(match);
  const conflicted = changes.conflicted.filter(match);
  const total = changes.staged.length + changes.unstaged.length;

  const draft = () => {
    setDrafting(true);
    window.setTimeout(() => {
      setMessage('fix(导航): 弹窗下边距收到 0.5rem，并补齐三处语言包文案');
      setDrafting(false);
    }, 900);
  };

  const rowsFor = (entries, isStaged) => {
    if (!tree) {
      return entries.map((e) => (
        <FileRow
          key={e.path} status={e.status} name={e.path} selected={selected === e.path}
          onClick={() => onSelect(e.path, isStaged)}
          style={{ marginBottom: 1 }}
        />
      ));
    }
    // 单子目录链合并成一行：上百个文件的变更列表靠它才读得下来
    const groups = {};
    entries.forEach((e) => { (groups[dirName(e.path)] = groups[dirName(e.path)] || []).push(e); });
    return Object.entries(groups).map(([dir, items]) => (
      <React.Fragment key={dir}>
        <DirectoryRow
          name={dir} count={items.length} collapsed={collapsed.includes(dir)}
          onToggle={() => setCollapsed(collapsed.includes(dir) ? collapsed.filter((d) => d !== dir) : [...collapsed, dir])}
          action={<Button variant="borderless" size="small">{isStaged ? '取消' : '暂存'}</Button>}
        />
        {collapsed.includes(dir) ? null : items.map((e) => (
          <FileRow
            key={e.path} depth={1} status={e.status} name={fileName(e.path)} selected={selected === e.path}
            onClick={() => onSelect(e.path, isStaged)}
            onContextMenu={undefined}
            style={{ marginBottom: 1 }}
          />
        ))}
      </React.Fragment>
    ));
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', flex: 1, minHeight: 0 }}>
      {total > 8 || filter ? (
        <div style={{ display: 'flex', alignItems: 'center', gap: 4, padding: '0 var(--space-regular) 6px' }}>
          <FilterField value={filter} onChange={setFilter} placeholder="过滤文件路径" />
          <ToolbarButton icon={tree ? 'square.stack.3d.up' : 'text.alignleft'} title={tree ? '改为平铺显示完整路径' : '改为按目录分组'} onClick={() => setTree(!tree)} />
        </div>
      ) : null}

      <div
        style={{ flex: 1, overflowY: 'auto', minHeight: 0 }}
        onContextMenu={(e) => {
          e.preventDefault();
          setMenu({ x: e.clientX, y: e.clientY });
        }}
      >
        {!staged.length && !unstaged.length && !conflicted.length ? (
          filter
            ? <EmptyState icon="magnifyingglass" title="没有匹配的文件" description="试试别的关键词" compact />
            : <EmptyState icon="checkmark.circle" title="工作区干净" description="没有待处理的改动" compact />
        ) : null}

        {conflicted.length ? (
          <React.Fragment>
            <SectionHeader title="冲突" count={conflicted.length} tone="warn"
              action={<Button variant="borderless" size="small" onClick={onResolve}>解决…</Button>} />
            <div style={{ padding: 4 }}>{rowsFor(conflicted, false)}</div>
          </React.Fragment>
        ) : null}

        {staged.length ? (
          <React.Fragment>
            <SectionHeader title="已暂存" count={staged.length}
              action={<Button variant="borderless" size="small">{filter ? '取消这 ' + staged.length + ' 个' : '全部取消'}</Button>} />
            <div style={{ padding: 4 }}>{rowsFor(staged, true)}</div>
          </React.Fragment>
        ) : null}

        {unstaged.length ? (
          <React.Fragment>
            <SectionHeader title="未暂存" count={unstaged.length}
              action={<Button variant="borderless" size="small">{filter ? '暂存这 ' + unstaged.length + ' 个' : '全部暂存'}</Button>} />
            <div style={{ padding: 4 }}>{rowsFor(unstaged, false)}</div>
          </React.Fragment>
        ) : null}
      </div>

      <CommitPanel
        message={message} onMessage={setMessage} amend={amend} onAmend={setAmend}
        staged={staged.length > 0} drafting={drafting} onDraft={draft}
        onCommit={() => setMessage('')}
      />

      {menu ? (
        <ContextMenu x={menu.x} y={menu.y} onClose={() => setMenu(null)} items={[
          { label: '暂存', onClick: () => setMenu(null) },
          { label: '在 Finder 中显示', onClick: () => setMenu(null) },
          { label: '丢弃改动…', destructive: true, onClick: () => { setMenu(null); onDiscard(); } },
        ]} />
      ) : null}
    </div>
  );
}

Object.assign(window, { ChangesPane, CommitPanel, ContextMenu });
