/* 演示数据。取自用户提供的截图：仓库 ai-cloud、当前分支 kino-aigc-chenya。
   只为让界面看起来是真的在用，不含任何逻辑。 */
window.YUGIT_FIXTURES = (function () {
  const LANES = 6;
  const straight = (skip) =>
    Array.from({ length: LANES }, (_, i) => ({ fromLane: i, toLane: i, colorIndex: i })).filter(
      (l) => !skip || !skip.includes(l.fromLane)
    );

  const commits = [
    { hash: '6bb58134', subject: 'feat(积分安全): 赠送积分与年度限额', author: '后端陈亚', date: '4 个月前', day: '今天', lane: 0, links: straight() },
    { hash: '685a312f', subject: 'S2 视频生成采用个人积分预扣', author: 'yangdong', date: '4 个月前', day: '今天', lane: 0, links: straight() },
    { hash: '0e6c4a51', subject: 'S2 生成视频接口不获取团队 id', author: 'yangdong', date: '4 个月前', day: '今天', lane: 0, links: straight() },
    { hash: '53d05aac', subject: 'S2 展示和生成视频接口改为个人维度', author: 'yangdong', date: '4 个月前', day: '昨天', lane: 0, links: straight() },
    {
      hash: 'eeaf2817', subject: "Merge branch 'kino-aigc-new' into kino-aigc-new-seedace2.0",
      author: 'xiaolin@tvjoy.cn', date: '4 个月前', day: '昨天', lane: 2, isMerge: true,
      links: [...straight([3]), { fromLane: 3, toLane: 2, colorIndex: 3 }],
      refs: [{ kind: 'remote', name: 'origin/kino-aigc-new' }],
    },
    { hash: '9eeb041c', subject: '2.0 跳转地址改成正式的', author: 'wangjun', date: '4 个月前', day: '昨天', lane: 1, links: straight() },
    { hash: '01cd06d2', subject: '积分冻结参数转成大写', author: 'wangjun', date: '4 个月前', day: '2026年4月1日', lane: 1, links: straight() },
    {
      hash: '6b054b88', subject: 'fix: 导航新增弹窗', author: '李泽林', date: '4 个月前', day: '2026年4月1日',
      lane: 1, isHead: true,
      links: straight().map((l) => (l.fromLane === 1 ? { ...l, isHead: true } : l)),
      refs: [{ kind: 'local', name: 'kino-aigc-chenya' }],
    },
    { hash: '7dd04b9d', subject: 'fix:修改积分 bug', author: 'wangjun', date: '4 个月前', day: '2026年4月1日', lane: 1, links: straight() },
    { hash: '608a57f4', subject: 'fix: 积分列表添加类型加两个字段', author: 'wangjun', date: '4 个月前', day: '2026年4月1日', lane: 1, links: straight() },
    { hash: '083d3987', subject: '修改积分弹框异常问题', author: 'wangjun', date: '4 个月前', day: '2026年3月31日', lane: 1, links: straight() },
    { hash: '4a16e473', subject: 'fix: 积分迁移入口放开，图片替换', author: '李泽林', date: '4 个月前', day: '2026年3月31日', lane: 1, links: straight() },
    { hash: '5abaff13', subject: 'feat: 1.7 增加 kino claw (kino 爪)', author: '李泽林', date: '4 个月前', day: '2026年3月31日', lane: 1, links: straight() },
    { hash: 'e6746c4c', subject: 'feat: 1.7 增加 ocp 模式 2.0', author: '李泽林', date: '4 个月前', day: '2026年3月31日', lane: 1, links: straight() },
    { hash: '68309aa3', subject: 'feat:1、积分迁移模块对接完成', author: 'wangjun', date: '4 个月前', day: '2026年3月30日', lane: 1, links: straight() },
    { hash: '10d81e19', subject: '积分迁移接口对接', author: 'wangjun', date: '4 个月前', day: '2026年3月30日', lane: 0, links: straight() },
    { hash: 'aaf5bf33', subject: '增加 seedance2.0 视频模块与入口', author: 'xiaolin@tvjoy.cn', date: '4 个月前', day: '2026年3月30日', lane: 4, links: straight() },
    { hash: '2d896a7d', subject: '积分迁移添加登录判断', author: 'xiaolin@tvjoy.cn', date: '4 个月前', day: '2026年3月30日', lane: 4, links: straight() },
    {
      hash: '5c260aa1', subject: "Merge branch 'kino-aigc-new' into kino-aigc-new-dsc", author: 'xiaolin@tvjoy.cn',
      date: '4 个月前', day: '2026年3月29日', lane: 0, isMerge: true,
      links: [...straight([5]), { fromLane: 5, toLane: 0, colorIndex: 5 }],
    },
    { hash: '6566aa24', subject: "Merge branch 'kino-aigc-new-fcw'", author: 'xiaolin@tvjoy.cn', date: '4 个月前', day: '2026年3月29日', lane: 0, isMerge: true, links: straight() },
  ];

  const localBranches = [
    { name: 'kino-aigc-chenya', isCurrent: true, upstream: 'origin/kino-aigc-chenya', last: 'fix: 导航新增弹窗' },
    { name: 'kino-aigc-new', last: 'S2 视频生成采用个人积分预扣' },
    { name: 'kino-aigc-new-dev', last: '积分迁移接口对接' },
    { name: 'kino-aigc-ne…dev-TestDemo', last: '临时验证' },
    { name: 'kino-aigc-new-fix', behind: 1, last: 'fix:修改积分 bug' },
    { name: 'kino-aigc-new-test', last: '压测脚本' },
    { name: 'master', ahead: 3, last: '发布 1.7' },
    { name: 'feat/quota-gone', gone: true, last: 'upstream 已被删除' },
  ];

  const remoteBranches = [
    { name: 'origin/detached' }, { name: 'origin/kino-aigc' },
    { name: 'origin/kino-ai…base 基线版本' }, { name: 'origin/kino-aigc-chenya' },
    { name: 'origin/kino-aigc-new' }, { name: 'origin/kino-aigc-new-144' },
    { name: 'origin/kino-ai…-new-144-dsc' }, { name: 'origin/kino-aigc-new-V1.7.0' },
    { name: 'origin/kino-aigc-new-cg' }, { name: 'origin/kino-aigc-new-dev' },
  ];

  const tags = [
    { name: 'v1.7.0', annotated: true, message: '发布 1.7.0' },
    { name: 'v2.0.0-rc1', annotated: true, message: '预发布' },
    { name: 'tmp-before-rebase', annotated: false },
  ];

  const changes = {
    conflicted: [
      { path: 'ai-web/frontend/src/store/modules/quota.ts', status: 'unmerged' },
    ],
    staged: [
      { path: 'ai-web/frontend/src/layouts/modules/global-menu/components/kino-navigation.vue', status: 'modified' },
      { path: 'ai-web/frontend/src/locales/langs/zh-cn.ts', status: 'modified' },
    ],
    unstaged: [
      { path: 'ai-web/frontend/src/router/elegant/routes.ts', status: 'modified' },
      { path: 'ai-web/frontend/src/views/quota/migrate.vue', status: 'added' },
      { path: 'ai-web/frontend/src/utils/legacy-quota.ts', status: 'deleted' },
      { path: 'ai-web/frontend/.env.local', status: 'untracked' },
    ],
  };

  const commitFiles = [
    { path: 'ai-web/frontend/src/layouts/modules/global-menu/components/kino-navigation.vue', status: 'modified' },
    { path: 'ai-web/frontend/src/locales/langs/zh-cn.ts', status: 'modified' },
    { path: 'ai-web/frontend/src/router/elegant/routes.ts', status: 'modified' },
  ];

  const seg = (text, syn, changed) => ({ text, syn, changed });
  const diff = {
    path: 'ai-web/frontend/src/layouts/modules/global-menu/components/kino-navigation.vue',
    added: 96, deleted: 5,
    hunks: [
      {
        header: '@@ -57,7 +57,7 @@',
        lines: [
          { kind: 'context', oldNumber: 57, newNumber: 57, segments: [seg('    <div style="')] },
          { kind: 'context', oldNumber: 58, newNumber: 58, segments: [seg('      display', 'type'), seg(': flex;')] },
          { kind: 'context', oldNumber: 59, newNumber: 59, segments: [seg('      padding', 'type'), seg(': '), seg('0 1rem', 'number'), seg(';')] },
          { kind: 'deletion', oldNumber: 60, segments: [seg('      padding-bottom', 'type'), seg(': '), seg('1', 'number', true), seg('rem', 'number'), seg(';')] },
          { kind: 'addition', newNumber: 60, segments: [seg('      padding-bottom', 'type'), seg(': '), seg('0.5', 'number', true), seg('rem', 'number'), seg(';')] },
          { kind: 'context', oldNumber: 61, newNumber: 61, segments: [seg('      border-bottom', 'type'), seg(': '), seg('0.0625rem', 'number'), seg(' solid rgba('), seg('var(--base-border-color)', 'keyword'), seg(');')] },
          { kind: 'context', oldNumber: 62, newNumber: 62, segments: [seg('      width', 'type'), seg(': '), seg('100%', 'number'), seg(';')] },
        ],
      },
      {
        header: '@@ -152,6 +152,5 @@',
        lines: [
          { kind: 'context', oldNumber: 152, newNumber: 152, segments: [seg('  '), seg('// 迁移入口，1.7 之后常驻', 'comment')] },
          { kind: 'addition', newNumber: 160, segments: [seg('    <div style="')] },
          { kind: 'addition', newNumber: 161, segments: [seg('      display', 'type'), seg(': flex;')] },
          { kind: 'addition', newNumber: 162, segments: [seg('      padding', 'type'), seg(': '), seg('0 1rem', 'number'), seg(';')] },
          { kind: 'addition', newNumber: 163, segments: [seg('      padding-bottom', 'type'), seg(': '), seg('0.5rem', 'number'), seg(';')] },
          { kind: 'addition', newNumber: 164, segments: [seg('      align-items', 'type'), seg(': center;')] },
          { kind: 'deletion', oldNumber: 158, segments: [seg('    '), seg('const', 'keyword'), seg(' legacy = '), seg('true', 'keyword'), seg(';')] },
        ],
      },
    ],
  };

  // 每条命令都带等价 git 命令：透明命令层，也是教学层
  const commands = [
    { icon: 'sparkles', title: 'AI 起草提交信息', hint: '根据暂存的改动生成，可直接编辑', cmd: '' },
    { icon: 'square.stack.3d.up', title: '分批提交…', hint: '把一大坨改动拆成几次说得清楚的提交', cmd: 'git commit -m … （分多次）' },
    { icon: 'checkmark.shield', title: '提交前自查', hint: '让 AI 通读暂存的改动，按风险分级', cmd: 'git diff --staged' },
    { icon: 'arrow.triangle.merge', title: '整理提交历史…', hint: '拖动重排、squash、reword', cmd: 'git rebase -i HEAD~10' },
    { icon: 'arrow.down.circle', title: '获取', hint: '只更新远程引用，不动工作区', cmd: 'git fetch --all --prune' },
    { icon: 'arrow.up.to.line', title: '推送', hint: '推送到 upstream', cmd: 'git push origin kino-aigc-chenya' },
    { icon: 'tray.and.arrow.down', title: '暂存改动到 stash', hint: '把当前改动收起来，稍后再拿回', cmd: 'git stash push -u' },
    { icon: 'magnifyingglass', title: '搜索仓库', hint: '提交、信息、文件内容、分支', cmd: 'git log -S … / git grep' },
    { icon: 'clock.arrow.circlepath', title: '时间线', hint: '所有写操作都在这里，可逐步撤销', cmd: 'git reflog / refs/yugit/*' },
    { icon: 'square.split.2x1', title: '并行工作区…', hint: '同时开两个分支干活', cmd: 'git worktree add ../ai-cloud-fix' },
    { icon: 'arrow.triangle.pull', title: '新建 Pull Request…', hint: 'GitHub / GitLab / Gitee', cmd: '' },
    { icon: 'arrow.uturn.backward', title: '撤销上一步操作', hint: '退回到那一刻，当前状态会先存下来', cmd: 'git reset --hard refs/yugit/snapshot-…' },
  ];

  const timeline = {
    entries: [
      { summary: '暂存 2 个文件', time: '3 分钟前', hazard: 'none', canUndo: true, cmd: 'git add -- kino-navigation.vue zh-cn.ts', why: '把改动放进索引，提交时只会带上索引里的内容。' },
      { summary: '整理提交历史（rebase -i）', time: '18 分钟前', hazard: 'rewrite', canUndo: true, cmd: 'git rebase -i HEAD~6', why: '重写这 6 条提交，hash 全部会变；开始前已自动打 tag。' },
      { summary: '丢弃 legacy-quota.ts 的改动', time: '1 小时前', hazard: 'discard', canUndo: true, cmd: 'git restore --worktree -- src/utils/legacy-quota.ts', why: '文件回到 HEAD 的内容，未提交的改动会消失 —— 已先拍快照。' },
      { summary: '拉取 origin/kino-aigc-new', time: '2 小时前', hazard: 'none', canUndo: false, failed: true, cmd: 'git pull --ff-only', why: '本地有分叉，fast-forward 失败，什么都没改。' },
    ],
    snapshots: [
      { summary: 'rebase 之前', time: '18 分钟前' },
      { summary: '丢弃改动之前', time: '1 小时前' },
    ],
  };

  return { LANES, commits, localBranches, remoteBranches, tags, changes, commitFiles, diff, commands, timeline };
})();
