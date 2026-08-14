#!/bin/sh
# 把 CLAUDE.md 同步到 AGENTS.md。
#
# 两份文件内容相同，服务不同的 agent 入口。分开维护必然分叉，
# 而分叉的后果是某个 agent 照着过时的那份做事——AGENTS.md 就曾长期
# 停留在「尚未开始编码」，而项目那时已经发到 v2.1。
set -eu
cd "$(dirname "$0")/.."

{
    printf '<!-- 本文件与 CLAUDE.md 保持一致，供不读 CLAUDE.md 的 agent 使用。\n'
    printf '     改动请同时改两处，或改完跑 scripts/sync-agent-docs.sh。 -->\n\n'
    cat CLAUDE.md
} > AGENTS.md

printf '✓ AGENTS.md 已从 CLAUDE.md 同步\n'
