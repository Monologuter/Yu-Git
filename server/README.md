# 驭Git 云服务网关

给不想自己申请 API Key 的用户提供的订阅制 AI 服务。**客户端的自带 Key 模式完全不依赖它**——
这套服务挂了，用户填自己 Key 的路径照常工作，本地 Git 功能更是一点不受影响。

## 它做什么，不做什么

只做四件事：验凭据、查额度、把请求转发给上游模型商、按实际用量扣额度。
**自己不做任何推理**，所以是纯 I/O 密集的流式代理——这是它能在 1.6G 内存机器上跑的原因。

不做的事同样要紧：

- **不存任何用户代码，不存请求内容。** `usage_records` 表里只有 token 数和模型名，
  没有一个字节的 prompt 或回复。想审计也审计不出用户写了什么。
- **不存明文凭据。** 数据库里只有 SHA-256 哈希。库泄露了，拿到的哈希也用不了。
- **不暴露上游是谁。** 对外只有 `yugit-standard` / `yugit-pro` 两个模型名，
  换供应商时客户端不用改，已发布的版本也不受影响。

## 为什么只接国内模型

服务器在国内，连不上 OpenAI，Anthropic 按地区拒绝（403）。硬配上去只会让用户选了之后
拿到一个看不懂的超时。所以上游候选只有 DeepSeek / 通义 / 智谱。

顺带也是成本问题：按 Claude 的价算，一个中度使用的用户每月上游成本约 ¥110，
订阅制根本做不平；国内几家能压到 ¥10 上下，才有定价空间。

当前生产用的是**通义**，两档这样分：

| 对外套餐 | 上游模型 | 为什么 |
|---|---|---|
| `yugit-standard` | `qwen-plus` | 提交信息生成、变更解释这类活儿它绰绰有余，单价低 |
| `yugit-pro` | `qwen3-coder-plus` | diff 评审和冲突解析全是代码，代码专用模型比通用旗舰更对口 |

换供应商只需要改 `.env` 重启，客户端一行都不用动——这正是对外只暴露
两个抽象套餐名的意义。

## 部署

### 1. 准备机器

最低配置就够：2 核 1.6G 内存。实测网关常驻 11MB、数据库 26MB。
内存小的机器建议先加 swap，构建镜像时会用到：

```bash
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
echo 'vm.swappiness=10' > /etc/sysctl.d/99-yugit.conf && sysctl --system
```

国内机器还要配 Docker 镜像源，否则拉不动基础镜像：

```bash
cat > /etc/docker/daemon.json <<'EOF'
{"registry-mirrors": ["https://docker.m.daocloud.io", "https://docker.1panel.live"]}
EOF
systemctl restart docker
```

### 2. 配置

```bash
cp .env.example .env
```

必须改的三项：

- `DB_PASSWORD` — 随便一个强密码，用 `openssl rand -base64 24` 生成
- **至少一个上游 API Key** — `DEEPSEEK_API_KEY` / `DASHSCOPE_API_KEY` / `ZHIPU_API_KEY`
  任选。一个都不配的话网关会直接拒绝启动，因为那样它没有存在意义。
- `STANDARD_MODEL` / `PRO_MODEL` — 两个对外套餐各用上游的哪个模型。
  **刻意不给默认值**：默认值只在「默认的那家上游」上是对的，换一家就变成
  一个必然 404 的名字，而且错得很隐蔽。配了多个上游时还要用
  `STANDARD_UPSTREAM` / `PRO_UPSTREAM` 指定各走哪家；只配一个时留空即可。

这几项都在**启动时**校验，配错了网关直接起不来。好过跑起来之后让用户在
发请求时收到一句「不支持的模型」——那时候既看不出是服务端配置问题，
也不知道该找谁。

### 3. 起服务

```bash
docker compose up -d
curl http://127.0.0.1:8080/healthz     # 应该回 ok
```

数据库和网关都只监听 `127.0.0.1`。对外要经 nginx，见下。

### 4. 签发订阅

```bash
./subscriber.sh new "张三 8月" 3000000 30
```

凭据**只打印这一次**，之后数据库里只剩哈希，丢了只能重新签发。这是刻意的。

其他命令：`list` 看用量、`revoke <ID>` 吊销、`reset <ID>` 重置本周期额度。

### 5. nginx + TLS

**先确认云厂商的安全组放行了 80。** 阿里云这类默认只开 22，
而 Let's Encrypt 的 HTTP-01 验证固定从 80 发起——只开 443 是签不下证书的。
这一步没做的话下面的 certbot 会以一个不太好懂的超时失败。

```bash
cp nginx/yugit.conf /etc/nginx/sites-available/
ln -sf /etc/nginx/sites-available/yugit.conf /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

certbot --nginx -d yugit.你的域名
```

配置里**只写 80**，443 交给 certbot 补：它会把 server 块就地改成 ssl、
另建一个 80 跳转块，并原样保留 location 内容。手写 443 块反而容易和自动续期打架。

location 里这三行是流式响应的命门，**不要删**：

```nginx
proxy_buffering off;
proxy_cache off;
proxy_set_header Connection '';
```

少了它们，nginx 会把 SSE 攒在缓冲区里，用户看到的是「卡半天然后一次性蹦出全文」——
网关那边做的逐块 Flush 全白费。

验证是不是真的在流式（时间戳应该是逐条递增，而不是挤在同一毫秒）：

```bash
curl -sN -X POST https://yugit.你的域名/v1/chat/completions \
  -H "Authorization: Bearer yg_..." -H "Content-Type: application/json" \
  -d '{"model":"yugit-standard","stream":true,"messages":[{"role":"user","content":"数到10"}]}' \
  | while IFS= read -r l; do [ -n "$l" ] && echo "$(date +%S.%3N) $l"; done
```

## 接口

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/v1/subscription` | 查剩余额度和续期时间 |
| POST | `/v1/chat/completions` | 转发补全，OpenAI 兼容格式，支持流式 |
| GET | `/healthz` | 健康检查，顺带 ping 数据库 |

前两个都要 `Authorization: Bearer yg_...`。

状态码约定：`401` 凭据无效，`402` 订阅失效或额度用完，`502` 上游出错。
客户端靠 402 区分「该续费了」和「配置错了」。

## 运维

```bash
docker compose logs -f gateway      # 看日志
docker compose ps                   # 看状态
docker stats --no-stream            # 看资源
./subscriber.sh list                # 看用量
```

备份只需要数据库——网关无状态，删了重建就行：

```bash
docker compose exec -T db pg_dump -U yugit yugit | gzip > backup-$(date +%F).sql.gz
```

## 几处容易改错的地方

- **网关没有 `WriteTimeout`。** 这是故意的：流式补全可能跑几十秒，
  设了会在生成中途把连接掐断，用户看到半截回复。
- **记账走后台 goroutine 和独立 context。** 请求结束时 `r.Context()` 就被取消了，
  用它记账这笔账会丢。
- **额度检查在转发之前。** 放在之后的话，超额用户的那次请求已经花掉钱了。
- **`used_tokens` 是累加的，不是从余额里扣。** 这样周期重置只要清零，
  而且随时能拿流水表对账。
