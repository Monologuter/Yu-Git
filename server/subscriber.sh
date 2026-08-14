#!/usr/bin/env bash
# 订阅者管理。
#
# 凭据在这里生成、给出一次，之后**只有哈希留在数据库里**——
# 丢了只能重新签发，找不回来。这是刻意的：数据库泄露拿不到能用的凭据。
set -euo pipefail

cd "$(dirname "$0")"
COMPOSE=(docker compose)

usage() {
    cat <<'EOF'
用法：
  ./subscriber.sh new <备注> [额度] [有效天数]   签发一个新订阅，打印凭据
  ./subscriber.sh list                          列出所有订阅及用量
  ./subscriber.sh revoke <ID>                   吊销
  ./subscriber.sh reset <ID>                    重置本周期已用额度

额度单位是 token，默认 3000000（约 ¥10 的 DeepSeek 用量）。
有效天数默认 30。
EOF
}

# 在数据库容器里跑 SQL。-qtA 去掉表头和对齐，方便脚本处理。
psql_run() {
    "${COMPOSE[@]}" exec -T db psql -U yugit -d yugit -v ON_ERROR_STOP=1 "$@"
}

case "${1:-}" in
new)
    label="${2:?需要一个备注，例如 '张三 8月'}"
    quota="${3:-3000000}"
    days="${4:-30}"

    # 这两个是直接拼进 SQL 的，必须确认是纯数字
    case "$quota" in ''|*[!0-9]*) echo "额度必须是数字" >&2; exit 1 ;; esac
    case "$days"  in ''|*[!0-9]*) echo "天数必须是数字" >&2; exit 1 ;; esac

    # 32 字节随机数走 base64url。不用 uuid：uuid 只有 122 位熵且格式可预测。
    credential="yg_$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-40)"
    # 先探测命令存在与否，不要靠管道退出码：管道的退出码是最后一个命令
    # （cut）的，而 cut 对空输入也返回 0，fallback 永远不会触发，
    # 结果是在没有 shasum 的机器上静默得到空哈希——凭据形同虚设。
    if command -v sha256sum >/dev/null 2>&1; then
        hash=$(printf '%s' "$credential" | sha256sum | cut -d' ' -f1)
    elif command -v shasum >/dev/null 2>&1; then
        hash=$(printf '%s' "$credential" | shasum -a 256 | cut -d' ' -f1)
    else
        echo "找不到 sha256sum 或 shasum，无法计算凭据哈希" >&2
        exit 1
    fi

    if [ ${#hash} -ne 64 ]; then
        echo "哈希长度不对（得到 ${#hash} 位），中止" >&2
        exit 1
    fi

    # label 来自命令行，用 psql 的 :'var' 绑定而不是拼字符串。
    # 注意必须走 stdin：psql 只在读脚本时做变量替换，-c 参数里的 :'var' 是字面量。
    # hash / quota / days 上面都已校验过格式，直接展开是安全的。
    psql_run -v label="$label" >/dev/null <<SQL
INSERT INTO subscribers (credential_hash, label, total_tokens, renews_at)
VALUES ('$hash', :'label', $quota, now() + interval '$days days');
SQL

    cat <<EOF

订阅已创建。凭据只显示这一次，请立刻保存：

  $credential

  备注：$label
  额度：$quota token
  有效：$days 天

把它填进驭Git 的「设置 → AI → 驭Git 云服务 → 订阅凭据」。
EOF
    ;;

list)
    psql_run -c "
        SELECT s.id,
               s.label                                    AS 备注,
               s.status                                   AS 状态,
               s.used_tokens || '/' || s.total_tokens     AS 已用,
               CASE WHEN s.total_tokens > 0
                    THEN round(100.0 * s.used_tokens / s.total_tokens, 1) || '%'
                    ELSE '-' END                          AS 占比,
               to_char(s.renews_at, 'MM-DD')              AS 续期,
               (SELECT count(*) FROM usage_records u WHERE u.subscriber_id = s.id) AS 调用次数
        FROM subscribers s
        ORDER BY s.id"
    ;;

revoke)
    id="${2:?需要订阅 ID}"
    case "$id" in ''|*[!0-9]*) echo "ID 必须是数字" >&2; exit 1 ;; esac
    psql_run -c "UPDATE subscribers SET status = 'invalid' WHERE id = $id"
    echo "订阅 $id 已吊销"
    ;;

reset)
    id="${2:?需要订阅 ID}"
    case "$id" in ''|*[!0-9]*) echo "ID 必须是数字" >&2; exit 1 ;; esac
    # 只清零已用额度，流水保留——那是对账依据，不能删
    psql_run -c "UPDATE subscribers
                 SET used_tokens = 0,
                     status = 'active',
                     renews_at = now() + interval '30 days'
                 WHERE id = $id"
    echo "订阅 $id 已重置"
    ;;

*)
    usage
    exit 1
    ;;
esac
