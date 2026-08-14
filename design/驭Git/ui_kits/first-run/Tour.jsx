/* 新手引导 sheet，520×380。对应 Teaching/OnboardingView.swift，
   文案取自 GitKit 的 OnboardingStep.repositoryTour，一字未改。
   目标不是教会 Git 的全部概念，而是让第一次用的人知道这个界面上哪里能做什么。 */
const { Button, Icon } = window.Git_c7d67c;

const STEPS = [
  { id: 'changes', title: '中间一栏是你改了什么',
    detail: '所有还没提交的改动都在这里。点一个文件，右边会显示具体改了哪几行。',
    concept: '「工作区」就是你正在编辑的这些文件本身。' },
  { id: 'stage', title: '挑出这次要提交的部分',
    detail: '整个文件可以一键暂存；也可以在右边的 diff 上只暂存某一块、甚至某几行。',
    concept: '「暂存区」是一个中转站：先把想一起提交的改动放进去，再一次提交。这让你可以把一次编辑拆成几个独立的提交。' },
  { id: 'commit', title: '写一句话说清这次改了什么',
    detail: '在下面的框里写提交信息。配了 AI 的话可以让它先起个草稿，再自己改。',
    concept: '「提交」是一个存档点。存下之后随时能回到这一刻。' },
  { id: 'history', title: '切到「历史」看走过的路',
    detail: '每一条都是一个存档点。右键某条提交可以直接合并、改写信息或丢弃它。',
    concept: '「分支」是同一份历史上的不同岔路，切换分支就是切换到另一条路上。' },
  { id: 'timeline', title: '做错了从时间线退回来',
    detail: '危险操作执行前会自动留一个可恢复的时间点，⌘Z 能退回上一步之前。',
    concept: '这是驭Git 额外做的事：连「还没提交的改动被覆盖」也能找回来，而这在 git 自己那里是做不到的。' },
  { id: 'palette', title: '记不住在哪就按 ⌘K',
    detail: '命令面板列出当前能做的所有操作，每条旁边写着等价的 git 命令。',
    concept: '看多了那些命令，你就顺带把 Git 学会了。' },
];

function Tour({ onFinish }) {
  const [index, setIndex] = React.useState(0);
  const step = STEPS[index];
  const last = index === STEPS.length - 1;

  return (
    <div style={{
      width: 520, height: 380, display: 'flex', flexDirection: 'column',
      background: 'var(--surface-raised)', borderRadius: 'var(--radius-large)',
      border: '1px solid var(--hairline)', boxShadow: 'var(--shadow-sheet)', overflow: 'hidden',
    }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 14, padding: 20, flex: 1, minHeight: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center' }}>
          <span style={{ font: 'var(--type-caption)', color: 'var(--ink-2)' }}>第 {index + 1} / {STEPS.length} 步</span>
          <span style={{ flex: 1 }} />
          <Button variant="borderless" size="small" onClick={onFinish}>跳过</Button>
        </div>

        <span style={{
          fontFamily: 'var(--font-ui)', fontSize: 'var(--text-size-sheet-title)',
          fontWeight: 'var(--weight-semibold)',
        }}>{step.title}</span>

        <span style={{ font: 'var(--type-callout)', color: 'var(--text-body)', textWrap: 'pretty' }}>{step.detail}</span>

        {step.concept ? (
          <div style={{
            display: 'flex', flexDirection: 'column', gap: 'var(--space-tight)', padding: 10,
            background: 'var(--surface-sunken)', borderRadius: 'var(--radius-medium)',
          }}>
            <span style={{ display: 'flex', alignItems: 'center', gap: 5, font: 'var(--type-caption)', fontWeight: 'var(--weight-medium)', color: 'var(--ink-2)' }}>
              <Icon name="lightbulb" size={11} />顺带一提
            </span>
            <span style={{ font: 'var(--type-callout)', color: 'var(--ink-2)', textWrap: 'pretty' }}>{step.concept}</span>
          </div>
        ) : null}
      </div>

      <div style={{ borderTop: '1px solid var(--hairline)', display: 'flex', alignItems: 'center', gap: 'var(--space-regular)', padding: 12 }}>
        <div style={{ display: 'flex', gap: 5 }}>
          {STEPS.map((s, i) => (
            <span key={s.id} style={{
              width: 6, height: 6, borderRadius: '50%',
              background: i === index ? 'var(--brand)' : 'color-mix(in srgb, var(--ink-2) 30%, transparent)',
            }} />
          ))}
        </div>
        <span style={{ flex: 1 }} />
        <Button disabled={index === 0} onClick={() => setIndex(index - 1)}>上一步</Button>
        {last
          ? <Button variant="default" onClick={onFinish}>开始使用</Button>
          : <Button variant="default" onClick={() => setIndex(index + 1)}>下一步</Button>}
      </div>
    </div>
  );
}

Object.assign(window, { Tour, STEPS });
