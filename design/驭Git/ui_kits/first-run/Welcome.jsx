/* 欢迎页：没打开仓库时的入口。
   对应 Repository/RootView.swift 的 WelcomeView —— 品牌标志换成靛底白「驭」的字组，
   这是整个应用里唯一一处可以放品牌的地方（仓库里没有图形 logo）。 */
const { Button, Icon } = window.Git_c7d67c;

const RECENTS = [
  { name: 'ai-cloud', path: '~/Developer/tvjoy' },
  { name: 'Yu-Git', path: '~/Developer/oss' },
  { name: 'kino-web', path: '~/Developer/tvjoy/frontend' },
];

function Welcome({ onOpen }) {
  return (
    <div style={{
      display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
      gap: 'var(--space-major)', height: '100%', padding: 40, background: 'var(--surface-app)',
    }}>
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 'var(--space-regular)' }}>
        <div style={{
          width: 96, height: 96, borderRadius: 22, background: 'var(--brand)',
          color: 'var(--brand-on)', display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontFamily: 'var(--font-ui)', fontSize: 'var(--text-size-mark)', fontWeight: 'var(--weight-semibold)',
        }}>驭</div>
        <span style={{
          fontFamily: 'var(--font-ui)', fontSize: 'var(--text-size-display)',
          fontWeight: 'var(--weight-semibold)', letterSpacing: 'var(--tracking-display)',
        }}>驭Git</span>
        <span style={{ font: 'var(--type-callout)', color: 'var(--ink-2)' }}>AI 帮你写代码，驭Git 帮你驾驭它</span>
      </div>

      <Button variant="default" size="large" icon="folder" onClick={onOpen} title="⌘O" style={{ minWidth: 140 }}>打开仓库…</Button>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 6, width: 360 }}>
        <span style={{ font: 'var(--type-caption)', color: 'var(--ink-2)' }}>最近打开</span>
        {RECENTS.map((r) => (
          <div
            key={r.name} onClick={onOpen}
            style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-regular)', padding: '4px 6px', borderRadius: 'var(--radius-small)' }}
            onMouseEnter={(e) => { e.currentTarget.style.background = 'var(--surface-hover)'; }}
            onMouseLeave={(e) => { e.currentTarget.style.background = 'transparent'; }}
          >
            <Icon name="folder" size={14} color="var(--ink-2)" />
            <span style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
              <span style={{ font: 'var(--type-body)' }}>{r.name}</span>
              <span style={{ font: 'var(--type-caption)', color: 'var(--ink-2)' }}>{r.path}</span>
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

Object.assign(window, { Welcome });
