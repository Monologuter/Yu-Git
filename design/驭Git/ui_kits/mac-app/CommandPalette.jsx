/* 命令面板。⌘K 唤起，输入即筛选（子序列匹配），右侧显示等价 git 命令。
   560×380，输入框 20pt —— 和应用里一致。 */
const { Icon, EmptyState } = window.Git_c7d67c;

function subsequence(query, text) {
  const haystack = text.toLowerCase();
  let index = 0;
  for (const ch of query.toLowerCase()) {
    const found = haystack.indexOf(ch, index);
    if (found < 0) return false;
    index = found + 1;
  }
  return true;
}

function CommandPalette({ commands, onClose }) {
  const [query, setQuery] = React.useState('');
  const [active, setActive] = React.useState(0);
  const list = commands.filter(
    (c) => !query.trim() || subsequence(query.trim(), c.title) || subsequence(query.trim(), c.hint || '') || subsequence(query.trim(), c.cmd || '')
  );

  React.useEffect(() => {
    const onKey = (e) => {
      if (e.key === 'Escape') onClose();
      if (e.key === 'ArrowDown') { e.preventDefault(); setActive((a) => Math.min(a + 1, list.length - 1)); }
      if (e.key === 'ArrowUp') { e.preventDefault(); setActive((a) => Math.max(a - 1, 0)); }
      if (e.key === 'Enter') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [list.length, onClose]);

  return (
    <div
      onClick={onClose}
      style={{
        position: 'absolute', inset: 0, zIndex: 30, display: 'flex', justifyContent: 'center',
        paddingTop: 80, background: 'rgba(0,0,0,0.10)',
      }}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        style={{
          width: 560, height: 380, display: 'flex', flexDirection: 'column',
          background: 'var(--surface-raised)', borderRadius: 'var(--radius-large)',
          border: '1px solid var(--hairline)', boxShadow: 'var(--shadow-sheet)', overflow: 'hidden',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: 12 }}>
          <Icon name="command" size={16} color="var(--ink-2)" />
          <input
            autoFocus value={query} placeholder="输入命令"
            onChange={(e) => { setQuery(e.target.value); setActive(0); }}
            style={{
              flex: 1, border: 'none', outline: 'none', background: 'transparent',
              fontFamily: 'var(--font-ui)', fontSize: 'var(--text-size-sheet-title)',
              color: 'var(--text-body)',
            }}
          />
        </div>
        <div style={{ borderTop: '1px solid var(--hairline)', overflowY: 'auto', flex: 1, minHeight: 0 }}>
          {list.length ? list.map((c, i) => (
            <div
              key={c.title} onMouseEnter={() => setActive(i)} onClick={onClose}
              style={{
                display: 'flex', alignItems: 'center', gap: 10, minHeight: 38,
                padding: '3px var(--space-loose)',
                background: i === active ? 'color-mix(in srgb, var(--accent) 15%, transparent)' : 'transparent',
              }}
            >
              <Icon name={c.icon} size={16} color="var(--accent)" style={{ width: 18 }} />
              <span style={{ display: 'flex', flexDirection: 'column', gap: 1, minWidth: 0 }}>
                <span style={{ font: 'var(--type-body)' }}>{c.title}</span>
                {c.hint ? (
                  <span style={{ font: 'var(--type-secondary)', color: 'var(--ink-2)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{c.hint}</span>
                ) : null}
              </span>
              <span style={{ flex: 1 }} />
              {c.cmd ? (
                <span style={{
                  font: 'var(--type-mono)', color: 'var(--ink-3)', maxWidth: 200,
                  overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', direction: 'rtl',
                }}>{c.cmd}</span>
              ) : null}
            </div>
          )) : (
            <div style={{ height: 240 }}>
              <EmptyState icon="search" title={'没有匹配「' + query + '」的命令'} description="试试「整理」「暂存」「时间线」" compact />
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { CommandPalette });
