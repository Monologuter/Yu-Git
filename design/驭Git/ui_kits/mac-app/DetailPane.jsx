/* 右栏：选中文件时显示 diff，选中提交时显示提交信息 + 改动的文件（下半部分是该文件的 diff）。 */
const { Icon, Button, CopyButton, CountPill, RefBadge, StatusLetter, EmptyState,
  ExplanationPanel, DiffLine, HunkHeader, SelectionBar, ToolbarButton } = window.Git_c7d67c;

function DiffBody({ diff, selection, onToggleLine, wrap }) {
  const widest = diff.hunks.flatMap((h) => h.lines).reduce((m, l) => Math.max(m, l.oldNumber || 0, l.newNumber || 0), 0);
  const gutter = Math.max(String(widest).length, 2) * 7 + 10;
  return (
    <div style={{ flex: 1, overflow: 'auto', minHeight: 0, background: 'var(--surface-app)' }}>
      {diff.hunks.map((hunk, hi) => (
        <React.Fragment key={hunk.header}>
          <HunkHeader header={hunk.header} action={<Button variant="borderless" size="small">暂存此块</Button>} />
          {hunk.lines.map((line, li) => (
            <DiffLine
              key={hi + '-' + li} {...line} gutterWidth={gutter} wrap={wrap}
              selected={(selection[hi] || []).includes(li)}
              onClick={() => onToggleLine(hi, li)}
            />
          ))}
        </React.Fragment>
      ))}
    </div>
  );
}

function FileDetail({ diff, isStaged, onBlame }) {
  const [selection, setSelection] = React.useState({});
  const [wrap, setWrap] = React.useState(false);
  const count = Object.values(selection).reduce((n, lines) => n + lines.length, 0);
  const toggleLine = (hi, li) => {
    const lines = selection[hi] || [];
    const next = lines.includes(li) ? lines.filter((l) => l !== li) : [...lines, li];
    setSelection({ ...selection, [hi]: next });
  };
  return (
    <div style={{ display: 'flex', flexDirection: 'column', flex: 1, minHeight: 0 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '8px var(--space-loose)' }}>
        <Icon name="file-text" size={13} color="var(--ink-2)" />
        <span style={{
          font: 'var(--type-body)', minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis',
          whiteSpace: 'nowrap', direction: 'rtl', textAlign: 'left',
        }}>{diff.path}</span>
        <span style={{ display: 'flex', gap: 4, font: 'var(--type-mono)', flex: '0 0 auto' }}>
          <span style={{ color: 'var(--diff-add-fg)' }}>+{diff.added}</span>
          <span style={{ color: 'var(--diff-del-fg)' }}>−{diff.deleted}</span>
        </span>
        <span style={{ flex: 1 }} />
        <Button variant="borderless" size="small" onClick={onBlame} title="逐行看这段代码是谁写的：人，还是哪个 AI 工具">查看归因</Button>
        <Button variant="borderless" size="small">{isStaged ? '取消暂存整个文件' : '暂存整个文件'}</Button>
        <ToolbarButton icon={wrap ? 'text-align-start' : 'move-horizontal'} title={wrap ? '改为不折行（长行横向滚动）' : '折行显示长行'} onClick={() => setWrap(!wrap)} />
      </div>
      <div style={{ borderTop: '1px solid var(--hairline)' }} />
      <div style={{ padding: '8px var(--space-loose) 0' }}>
        <ExplanationPanel title="用中文讲讲这份改动"
          text="这份改动把导航栏弹窗的下边距从 1rem 收到 0.5rem，并新增了一段常驻的迁移入口容器；删掉的 legacy 开关说明旧入口已经不再需要。都是展示层改动，没有触碰接口。" />
      </div>
      {count > 0 ? (
        <div style={{ paddingTop: 8 }}>
          <SelectionBar count={count} primaryLabel={isStaged ? '取消暂存选中的行' : '暂存选中的行'}
            onClear={() => setSelection({})} onApply={() => setSelection({})} />
        </div>
      ) : <div style={{ height: 8 }} />}
      <DiffBody diff={diff} selection={selection} onToggleLine={toggleLine} wrap={wrap} />
    </div>
  );
}

function MetaRow({ label, value, secondary, mono, trailing }) {
  return (
    <div style={{ display: 'flex', gap: 'var(--space-loose)' }}>
      <span style={{
        flex: '0 0 auto', width: 52, textAlign: 'right', paddingTop: 1,
        font: 'var(--type-secondary)', color: 'var(--ink-2)',
      }}>{label}</span>
      <span style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
        <span style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-tight)' }}>
          <span style={{ font: mono ? 'var(--type-mono)' : 'var(--type-body)' }}>{value}</span>
          {trailing}
        </span>
        {secondary ? <span style={{ font: 'var(--type-secondary)', color: 'var(--ink-3)' }}>{secondary}</span> : null}
      </span>
    </div>
  );
}

function CommitDetail({ commit, files, diff, selectedFile, onSelectFile }) {
  const [split, setSplit] = React.useState(0.48);
  const dragging = React.useRef(false);
  const wrapRef = React.useRef(null);

  React.useEffect(() => {
    const move = (e) => {
      if (!dragging.current || !wrapRef.current) return;
      const box = wrapRef.current.getBoundingClientRect();
      setSplit(Math.min(0.78, Math.max(0.22, (e.clientY - box.top) / box.height)));
    };
    const up = () => { dragging.current = false; };
    window.addEventListener('mousemove', move);
    window.addEventListener('mouseup', up);
    return () => { window.removeEventListener('mousemove', move); window.removeEventListener('mouseup', up); };
  }, []);

  const summary = (
    <div style={{ overflowY: 'auto', minHeight: 0, flex: selectedFile ? 'none' : 1, height: selectedFile ? (split * 100) + '%' : 'auto' }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-section)', padding: 'var(--space-section)' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-regular)' }}>
          <span style={{ font: 'var(--type-title)', textWrap: 'pretty' }}>{commit.subject}</span>
          {commit.refs && commit.refs.length ? (
            <span style={{ display: 'flex', gap: 4 }}>
              {commit.refs.map((r) => <RefBadge key={r.name} kind={r.kind}>{r.name}</RefBadge>)}
            </span>
          ) : null}
        </div>

        <ExplanationPanel title="用中文讲讲这次 commit"
          text="这次提交只改了导航栏的弹窗样式：下边距收窄一档，并补齐了三处语言包文案。属于纯展示层调整，不影响接口与数据。" />

        <div style={{ borderTop: '1px solid var(--hairline)' }} />

        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-regular)' }}>
          <MetaRow label="提交" value={commit.hash} mono trailing={<CopyButton text={commit.hash + '9d0e4a1b'} title="复制完整 commit hash" />} />
          <MetaRow label="作者" value={commit.author} secondary={'15304991+li-zlincold@user.noreply.gitee.com · 2026年3月31日 1:29'} />
          <MetaRow label={commit.isMerge ? '父提交（合并）' : '父提交'} value={commit.isMerge ? '7dd04b9dd  ebdeefc6d' : '7dd04b9dd'} mono />
        </div>

        <div style={{ borderTop: '1px solid var(--hairline)' }} />

        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-regular)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-tight)' }}>
            <span style={{ font: 'var(--type-title)' }}>改动的文件</span>
            <CountPill>{files.length}</CountPill>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column' }}>
            {files.map((f) => {
              const selected = selectedFile === f.path;
              return (
                <div
                  key={f.path} onClick={() => onSelectFile(selected ? null : f.path)}
                  style={{
                    display: 'flex', alignItems: 'center', gap: 'var(--space-regular)',
                    padding: '5px var(--space-regular)', borderRadius: 'var(--radius-small)',
                    background: selected ? 'var(--selection-bg)' : 'transparent',
                    color: selected ? 'var(--selection-fg)' : 'var(--text-body)',
                  }}
                >
                  <StatusLetter status={f.status} emphasized={selected} />
                  <span style={{
                    font: 'var(--type-body)', minWidth: 0, overflow: 'hidden',
                    textOverflow: 'ellipsis', whiteSpace: 'nowrap', direction: 'rtl', textAlign: 'left',
                  }}>{f.path}</span>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );

  if (!selectedFile) return <div style={{ display: 'flex', flexDirection: 'column', flex: 1, minHeight: 0 }}>{summary}</div>;

  return (
    <div ref={wrapRef} style={{ display: 'flex', flexDirection: 'column', flex: 1, minHeight: 0 }}>
      {summary}
      <div
        onMouseDown={() => { dragging.current = true; }}
        style={{ height: 5, cursor: 'row-resize', background: 'var(--hairline)', flex: '0 0 auto' }}
      />
      <div style={{ display: 'flex', flexDirection: 'column', flex: 1, minHeight: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-regular)', padding: '8px var(--space-loose)' }}>
          <span style={{
            font: 'var(--type-body)', minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis',
            whiteSpace: 'nowrap', direction: 'rtl', textAlign: 'left',
          }}>{selectedFile}</span>
          <span style={{ display: 'flex', gap: 4, font: 'var(--type-mono)', flex: '0 0 auto' }}>
            <span style={{ color: 'var(--diff-add-fg)' }}>+{diff.added}</span>
            <span style={{ color: 'var(--diff-del-fg)' }}>−{diff.deleted}</span>
          </span>
          <span style={{ flex: 1 }} />
          <Button variant="borderless" size="small" onClick={() => onSelectFile(null)}>收起</Button>
        </div>
        <div style={{ borderTop: '1px solid var(--hairline)' }} />
        <DiffBody diff={diff} selection={{}} onToggleLine={() => {}} wrap={false} />
      </div>
    </div>
  );
}

function DetailPane({ fixtures, selectedFile, isStaged, selectedCommit, onBlame }) {
  const [commitFile, setCommitFile] = React.useState(fixtures.commitFiles[0].path);
  const commit = fixtures.commits.find((c) => c.hash === selectedCommit);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', flex: 1, minWidth: 0, background: 'var(--surface-app)' }}>
      {selectedFile ? (
        <FileDetail diff={{ ...fixtures.diff, path: selectedFile }} isStaged={isStaged} onBlame={onBlame} />
      ) : commit ? (
        <CommitDetail
          commit={commit} files={fixtures.commitFiles} diff={fixtures.diff}
          selectedFile={commitFile} onSelectFile={setCommitFile}
        />
      ) : (
        <EmptyState icon="panel-right" title="未选择内容" description="在左侧选择一个文件或提交" />
      )}
    </div>
  );
}

Object.assign(window, { DetailPane, CommitDetail, FileDetail, DiffBody, MetaRow });
