#!/usr/bin/env bash
# 签发证书并把 nginx 切到 HTTPS。
#
# 前提是 **80 端口从公网可达**——Let's Encrypt 的 HTTP-01 验证固定从 80 发起，
# 只开 443 是签不下来的。云厂商的安全组默认往往只开 22，这一步最容易漏。
set -euo pipefail

DOMAIN="${1:?用法：./enable-tls.sh yugit.你的域名 [邮箱]}"
EMAIL="${2:-}"

echo "▸ 检查 $DOMAIN 解析"
resolved=$(getent hosts "$DOMAIN" | awk '{print $1}' | head -1)
if [ -z "$resolved" ]; then
    echo "  ✗ 解析不到 $DOMAIN，先去 DNS 那边加 A 记录" >&2
    exit 1
fi
echo "  → $resolved"

echo "▸ 检查 80 端口能不能从公网进来"
# 用外部服务回探自己。本机 curl 127.0.0.1 是测不出安全组的，
# 那条路径根本不经过云厂商的网络策略。
if ! curl -s --max-time 15 "https://api.ipify.org" >/dev/null 2>&1; then
    echo "  ! 这台机器出网也有问题，先解决网络" >&2
fi

probe=$(curl -s --max-time 20 -o /dev/null -w "%{http_code}" \
    "http://$DOMAIN/.well-known/acme-challenge/probe" 2>/dev/null || echo "000")
if [ "$probe" = "000" ]; then
    cat >&2 <<EOF

  ✗ 从公网访问 http://$DOMAIN 不通。

    nginx 本机是好的（curl 127.0.0.1 能通），所以问题在云厂商的安全组。
    去控制台给这台机器的安全组加入方向规则：

        协议 TCP / 端口 80   / 源 0.0.0.0/0
        协议 TCP / 端口 443  / 源 0.0.0.0/0

    加完再跑一次这个脚本。

EOF
    exit 1
fi
echo "  → 通（HTTP $probe）"

echo "▸ 签发证书"
if [ -n "$EMAIL" ]; then
    certbot --nginx -d "$DOMAIN" --agree-tos -m "$EMAIL" --non-interactive --redirect
else
    # 不留邮箱就收不到到期提醒。证书 90 天一续，自动续期挂了又没人提醒的话，
    # 服务会在某天早上毫无征兆地全线 TLS 报错。
    echo "  ! 没给邮箱，收不到证书到期提醒"
    certbot --nginx -d "$DOMAIN" --agree-tos --register-unsafely-without-email \
        --non-interactive --redirect
fi

echo "▸ 确认自动续期是活的"
systemctl is-active certbot.timer 2>/dev/null || systemctl enable --now certbot.timer
certbot renew --dry-run 2>&1 | tail -3

echo "▸ 验证 HTTPS"
code=$(curl -s --max-time 15 -o /dev/null -w "%{http_code}" "https://$DOMAIN/healthz")
echo "  https://$DOMAIN/healthz → HTTP $code"

echo "▸ 确认 HTTP 会跳到 HTTPS"
redirect=$(curl -s --max-time 15 -o /dev/null -w "%{http_code}" "http://$DOMAIN/healthz")
echo "  http://$DOMAIN/healthz → HTTP $redirect（301/308 才对）"

cat <<EOF

完成。接下来：

  1. 把客户端 YugitCloudProvider.defaultEndpoint 指向 https://$DOMAIN/v1
  2. 把 isServiceAvailable 翻成 true
  3. ./subscriber.sh new "你的名字" 签一个凭据，填进驭Git 试一下

EOF
