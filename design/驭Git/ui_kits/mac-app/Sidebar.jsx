/* 左栏：过滤框 + 本地分支 / 远程分支（可折叠带计数）/ 标签。 */
const { FilterField, SectionHeader, BranchRow, TagRow, Button, Icon, EmptyState } = window.Git_c7d67c;

function Disclosure({ title, count, expanded, onToggle }) {
  return (
    <div
      onClick={onToggle}
      style={{
        display: 'flex', alignItems: 'center', gap: 4, height: 22,
        padding: '0 var(--space-regular)', position: 'sticky', top: 0, zIndex: 1,
        background: 'var(--surface-sunken)', borderBottom: '1px solid var(--hairline)',
        font: 'var(--type-secondary)', fontWeight: 'var(--weight-semibold)', color: 'var(--ink-2)',
      }}
    >
      <Icon name="chevron.right" size={9} style={{ transform: expanded ? 'rotate(90deg)' : 'none', transition: 'transform var(--dur-fast) var(--ease-standard)' }} />
      <span>{title}</span>
      <span style={{ color: 'var(--ink-4)', fontWeight: 'var(--weight-regular)' }}>{count}</span>
    </div>
  );
}

function Sidebar({ fixtures, selected, onSelect }) {
  const [filter, setFilter] = React.useState('');
  const [remoteOpen, setRemoteOpen] = React.useState(false);
  const [tagsOpen, setTagsOpen] = React.useState(false);
  const match = (name) => !filter.trim() || name.toLowerCase().includes(filter.trim().toLowerCase());

  // 当前分支永远置顶：光按最后提交时间排，切到很久没动的分支后它会沉到末尾，
  // 而那恰恰是你此刻站着的地方。
  const locals = fixtures.localBranches.filter((b) => match(b.name));
  const ordered = [...locals.filter((b) => b.isCurrent), ...locals.filter((b) => !b.isCurrent)];
  const remotes = fixtures.remoteBranches.filter((b) => match(b.name));
  const tags = fixtures.tags.filter((t) => match(t.name));

  return (
    <div style={{
      width: 'var(--col-sidebar)', flex: '0 0 auto', display: 'flex', flexDirection: 'column',
      background: 'var(--surface-sidebar)', backdropFilter: 'var(--blur-sidebar)',
      WebkitBackdropFilter: 'var(--blur-sidebar)', borderRight: '1px solid var(--hairline)',
      minHeight: 0,
    }}>
      <div style={{ padding: '6px var(--space-regular)', display: 'flex' }}>
        <FilterField value={filter} onChange={setFilter} placeholder="过滤分支与标签" />
      </div>
      <div style={{ borderTop: '1px solid var(--hairline)', overflowY: 'auto', flex: 1, minHeight: 0 }}>
        <SectionHeader title="本地分支" action={<Button variant="borderless" size="small" icon="plus" title="新建分支" />} />
        <div style={{ padding: 4 }}>
          {ordered.length ? ordered.map((b) => (
            <BranchRow
              key={b.name} name={b.name} isCurrent={b.isCurrent} ahead={b.ahead} behind={b.behind} gone={b.gone}
              selected={selected === b.name} onClick={() => onSelect(b.name)}
              title={[b.name, b.upstream ? 'upstream：' + b.upstream : null, b.last ? '最新提交：' + b.last : null].filter(Boolean).join('\n')}
            />
          )) : <div style={{ padding: '10px var(--space-regular)', font: 'var(--type-callout)', color: 'var(--ink-4)' }}>没有匹配的分支</div>}
        </div>
        <Disclosure title="远程分支" count={remotes.length} expanded={remoteOpen} onToggle={() => setRemoteOpen(!remoteOpen)} />
        {remoteOpen ? (
          <div style={{ padding: 4 }}>
            {remotes.map((b) => (
              <BranchRow key={b.name} name={b.name} isRemote selected={selected === b.name} onClick={() => onSelect(b.name)} />
            ))}
          </div>
        ) : null}
        <Disclosure title="标签" count={tags.length} expanded={tagsOpen} onToggle={() => setTagsOpen(!tagsOpen)} />
        {tagsOpen ? (
          <div style={{ padding: 4 }}>
            {tags.map((t) => <TagRow key={t.name} name={t.name} annotated={t.annotated} title={t.message} />)}
          </div>
        ) : null}
      </div>
    </div>
  );
}

Object.assign(window, { Sidebar });
