/* 中栏 · 历史：搜提交信息 + 作者/时间筛选 + 日期分组的提交列表。 */
const { FilterField, CommitRow, DayGroupRow, ToolbarButton, EmptyState, Button, Icon } = window.Git_c7d67c;

function HistoryPane({ fixtures, selected, onSelect }) {
  const [filter, setFilter] = React.useState('');
  const [author, setAuthor] = React.useState(null);
  const commits = fixtures.commits.filter((c) => {
    const q = filter.trim().toLowerCase();
    const okText = !q || c.subject.toLowerCase().includes(q) || c.hash.includes(q);
    return okText && (!author || c.author === author);
  });

  // 日期变了就插一条分组行 —— 几百条等高的提交里，这是眼睛唯一的落点
  const blocks = [];
  commits.forEach((c) => {
    const last = blocks[blocks.length - 1];
    if (!last || last.day !== c.day) blocks.push({ day: c.day, items: [c] });
    else last.items.push(c);
  });

  return (
    <div style={{ display: 'flex', flexDirection: 'column', flex: 1, minHeight: 0 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 4, padding: '0 var(--space-regular) 6px' }}>
        <FilterField value={filter} onChange={setFilter} placeholder="搜提交信息" />
        <ToolbarButton
          icon={author ? 'person.circle' : 'person'} title="按作者或时间筛选"
          active={!!author} onClick={() => setAuthor(author ? null : 'wangjun')}
        />
      </div>

      {filter || author ? (
        <div style={{ display: 'flex', alignItems: 'center', gap: 4, padding: '0 var(--space-regular) 6px' }}>
          <Icon name="line.3.horizontal.decrease" size={10} color="var(--brand)" />
          <span style={{ font: 'var(--type-secondary)', color: 'var(--ink-2)' }}>
            在整个历史中找到 {commits.length} 条{author ? ' · 作者 ' + author : ''}
          </span>
          <span style={{ flex: 1 }} />
          <Button variant="borderless" size="small" onClick={() => { setFilter(''); setAuthor(null); }}>清除</Button>
        </div>
      ) : null}

      <div style={{ flex: 1, overflowY: 'auto', minHeight: 0, borderTop: '1px solid var(--hairline)' }}>
        {commits.length === 0 ? (
          <EmptyState icon="magnifyingglass" title="没有匹配的提交" description="整个历史里都没有符合这些条件的提交" compact />
        ) : blocks.map((block) => (
          <React.Fragment key={block.day}>
            <DayGroupRow label={block.day} count={block.items.length} />
            {block.items.map((c) => (
              <CommitRow
                key={c.hash} subject={c.subject} hash={c.hash} author={c.author} date={c.date}
                isMerge={c.isMerge} refs={c.refs} laneCount={fixtures.LANES}
                graphRow={{ nodeLane: c.lane, colorIndex: c.lane, isMerge: c.isMerge, isHead: c.isHead, links: c.links }}
                selected={selected === c.hash} onClick={() => onSelect(c.hash)}
              />
            ))}
          </React.Fragment>
        ))}
        {commits.length ? (
          <div style={{ display: 'flex', justifyContent: 'center', padding: 'var(--space-loose)' }}>
            <span style={{ font: 'var(--type-secondary)', color: 'var(--ink-4)' }}>滚动到底部会自动加载更多</span>
          </div>
        ) : null}
      </div>
    </div>
  );
}

Object.assign(window, { HistoryPane });
