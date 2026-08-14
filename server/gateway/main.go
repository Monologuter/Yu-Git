// 驭Git 云服务网关。
//
// 只做四件事：验凭据、查额度、把请求转发给上游模型商、按实际用量扣额度。
// **自己不做任何推理**，所以是纯 I/O 密集的流式代理——这也是它能在
// 1.6G 内存的机器上跑的原因。
//
// 用 Go 而不是 Swift/Python 写：这台机器只有 1.2G 可用内存，
// Go 的常驻内存是几十 MB 量级，且单二进制部署没有运行时依赖。
package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	ctx := context.Background()

	pool, err := pgxpool.New(ctx, mustEnv("DATABASE_URL"))
	if err != nil {
		log.Fatalf("连不上数据库：%v", err)
	}
	defer pool.Close()

	if err := pool.Ping(ctx); err != nil {
		log.Fatalf("数据库 ping 失败：%v", err)
	}

	store := &Store{pool: pool}
	upstreams := loadUpstreams()
	if len(upstreams) == 0 {
		log.Fatal("一个上游都没配置，网关没有意义")
	}
	for name := range upstreams {
		log.Printf("已加载上游：%s", name)
	}

	server := &Server{store: store, upstreams: upstreams}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /v1/subscription", server.handleSubscription)
	mux.HandleFunc("POST /v1/chat/completions", server.handleCompletions)
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		if err := pool.Ping(r.Context()); err != nil {
			http.Error(w, "数据库不可用", http.StatusServiceUnavailable)
			return
		}
		w.Write([]byte("ok"))
	})

	addr := envOr("LISTEN_ADDR", ":8080")
	log.Printf("网关监听 %s", addr)

	httpServer := &http.Server{
		Addr:    addr,
		Handler: mux,
		// 不设 WriteTimeout：流式补全可能跑几十秒，
		// 设了会在生成中途把连接掐断，用户看到的是半截回复。
		ReadHeaderTimeout: 15 * time.Second,
		IdleTimeout:       90 * time.Second,
	}
	log.Fatal(httpServer.ListenAndServe())
}

// Server 持有请求处理需要的一切。
type Server struct {
	store     *Store
	upstreams map[string]Upstream
}

// ── 订阅查询 ─────────────────────────────────────────────────────────

// handleSubscription 如实报告订阅状态。
//
// 刻意**不**走 authenticate：那个函数对非 active 的订阅返回 402，
// 而查询接口的职责就是报告状态——「已过期」是一个合法状态，不是错误。
// 用 402 表达的话，客户端只能拿到一个 HTTP 错误，没法区分
// 「该续费了」和「配置填错了」，只能给用户看一个红色报错。
//
// 402 留给补全接口，那里才是「你想用但用不了」。
func (s *Server) handleSubscription(w http.ResponseWriter, r *http.Request) {
	sub, err := s.lookupSubscriber(r)
	if err != nil {
		writeError(w, err)
		return
	}

	remaining := sub.TotalTokens - sub.UsedTokens
	if remaining < 0 {
		remaining = 0
	}

	payload := map[string]any{
		"status":           sub.Status,
		"remaining_tokens": remaining,
		"total_tokens":     sub.TotalTokens,
	}
	if sub.RenewsAt != nil {
		payload["renews_at"] = sub.RenewsAt.UTC().Format(time.RFC3339)
	}
	// 每种非正常状态都给客户端一句能直接显示的话。
	// 客户端不该自己拼这些文案——服务端改了续费规则时，
	// 已经发布的客户端版本没法跟着改。
	switch {
	case sub.Status == "expired":
		payload["message"] = "订阅已过期，续费后立即恢复"
	case sub.Status == "invalid":
		payload["message"] = "该凭据已被吊销"
	case remaining == 0:
		payload["message"] = "本周期额度已用完，下次续期后恢复"
	}

	writeJSON(w, http.StatusOK, payload)
}

// ── 补全转发 ─────────────────────────────────────────────────────────

func (s *Server) handleCompletions(w http.ResponseWriter, r *http.Request) {
	sub, err := s.authenticate(r)
	if err != nil {
		writeError(w, err)
		return
	}

	// 额度检查放在转发之前。放在之后的话，超额用户的那次请求已经花掉了钱。
	if sub.TotalTokens > 0 && sub.UsedTokens >= sub.TotalTokens {
		writeError(w, &apiError{
			status:  http.StatusPaymentRequired,
			message: "本周期额度已用完",
		})
		return
	}

	var req CompletionRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxRequestBytes)).Decode(&req); err != nil {
		writeError(w, &apiError{status: http.StatusBadRequest, message: "请求体不是合法 JSON"})
		return
	}

	upstream, ok := s.upstreams[modelToUpstream(req.Model)]
	if !ok {
		writeError(w, &apiError{
			status:  http.StatusBadRequest,
			message: "不支持的模型：" + req.Model,
		})
		return
	}

	// 记账用的输入规模。上游若返回真实 usage 会覆盖它。
	estimatedInput := estimateTokens(req.textForEstimate())

	usage, err := upstream.Forward(r.Context(), w, &req)
	if err != nil {
		// 流已经开始写之后就不能再改状态码了，只能记日志。
		// 客户端会因为流没有正常收尾而报错，这是对的。
		log.Printf("转发失败 subscriber=%d model=%s: %v", sub.ID, req.Model, err)
		if !usage.HeadersSent {
			writeError(w, err)
		}
		return
	}

	// 扣额度用后台 context：客户端此时多半已经断开，
	// 用 r.Context() 会因为请求结束而被取消，这笔账就丢了。
	go func() {
		recordCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		in, out, estimated := usage.InputTokens, usage.OutputTokens, false
		if in == 0 {
			in, estimated = estimatedInput, true
		}
		if out == 0 {
			out, estimated = estimateTokens(usage.CollectedText), true
		}

		if err := s.store.RecordUsage(recordCtx, sub.ID, req.Model, in, out, estimated); err != nil {
			log.Printf("记账失败 subscriber=%d: %v", sub.ID, err)
		}
	}()
}

// ── 鉴权 ────────────────────────────────────────────────────────────

// lookupSubscriber 验凭据，**不**管订阅状态。
//
// 凭据认不出来是真的错误（401）；订阅过期不是——那是一个要如实汇报的状态。
// 两件事分开，查询接口才能把「已过期」当数据返回。
func (s *Server) lookupSubscriber(r *http.Request) (*Subscriber, error) {
	header := r.Header.Get("Authorization")
	credential, found := strings.CutPrefix(header, "Bearer ")
	if !found || strings.TrimSpace(credential) == "" {
		return nil, &apiError{status: http.StatusUnauthorized, message: "缺少订阅凭据"}
	}

	// 只用哈希查库。明文凭据不落库、不进日志。
	sum := sha256.Sum256([]byte(strings.TrimSpace(credential)))
	hash := hex.EncodeToString(sum[:])

	sub, err := s.store.FindByCredentialHash(r.Context(), hash)
	if errors.Is(err, errNotFound) {
		// 刻意不区分「凭据不存在」和「凭据错误」——
		// 区分开等于告诉扫描者哪些凭据是真实存在的。
		return nil, &apiError{status: http.StatusUnauthorized, message: "订阅凭据无效"}
	}
	if err != nil {
		return nil, err
	}
	return sub, nil
}

// authenticate 在验凭据之外要求订阅当前可用。
// 给真正要花钱的接口用。
func (s *Server) authenticate(r *http.Request) (*Subscriber, error) {
	sub, err := s.lookupSubscriber(r)
	if err != nil {
		return nil, err
	}

	if sub.Status != "active" {
		return nil, &apiError{
			status:  http.StatusPaymentRequired,
			message: "订阅已" + statusText(sub.Status),
		}
	}

	return sub, nil
}

// ── 辅助 ────────────────────────────────────────────────────────────

const maxRequestBytes = 4 << 20 // 4MB。脱敏后的 diff 远小于这个数。

func statusText(status string) string {
	switch status {
	case "expired":
		return "过期"
	case "invalid":
		return "失效"
	default:
		return "不可用"
	}
}

func mustEnv(key string) string {
	value := os.Getenv(key)
	if value == "" {
		log.Fatalf("缺少必需的环境变量 %s", key)
	}
	return value
}

func envOr(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
