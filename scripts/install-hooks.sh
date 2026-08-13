#!/bin/sh
# 安装本仓库的 git hooks 与提交信息模板。
# git 不跟踪 .git/hooks/，因此源文件放在 scripts/hooks/ 由本脚本复制。
# 克隆仓库后执行一次即可；hooks 内容变更后需重新执行。

set -e

root=$(git rev-parse --show-toplevel)
hooks_dir=$(git rev-parse --absolute-git-dir)/hooks
source_dir="$root/scripts/hooks"

mkdir -p "$hooks_dir"

for hook in pre-commit commit-msg pre-push; do
    cp "$source_dir/$hook" "$hooks_dir/$hook"
    chmod +x "$hooks_dir/$hook"
    printf '✓ 安装 %s\n' "$hook"
done

git config --local commit.template .gitmessage
printf '✓ 配置提交信息模板\n'

printf '\n完成。质量门禁：\n'
printf '  pre-commit  暂存的 Swift 文件跑 swift format lint\n'
printf '  commit-msg  校验 Conventional Commits 格式、拦截 AI 署名\n'
printf '  pre-push    跑全量 swift test\n'
