package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

// CompletionRequest 是客户端发来的补全请求。
//
// 字段刻意留得很少：网关不解释语义，只做转发。多余的字段用 raw 原样带走，
// 这样上游新增参数时网关不必跟着改。
type CompletionRequest struct {
	Model    string    `json:"model"`
	Messages []Message `json:"messages"`
	Stream   bool      `json:"stream"`

	raw map[string]any
}

type Message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

func (r *CompletionRequest) UnmarshalJSON(data []byte) error {
	type alias CompletionRequest
	var shadow alias
	if err := json.Unmarshal(data, &shadow); err != nil {
		return err
	}
	*r = CompletionRequest(shadow)
	return json.Unmarshal(data, &r.raw)
}

// textForEstimate 把所有输入拼起来，供上游不返回 usage 时估算用量。
func (r *CompletionRequest) textForEstimate() string {
	var builder strings.Builder
	for _, message := range r.Messages {
		builder.WriteString(message.Content)
	}
	return builder.String()
}

// UsageResult 是一次转发的记账结果。
type UsageResult struct {
	InputTokens  int
	OutputTokens int
	// 上游没回 usage 时，用收集到的正文估算长度。
	CollectedText string
	// 响应头是否已经发出。发出之后就不能再改状态码了。
	HeadersSent bool
}

// Upstream 是一个上游模型服务。
type Upstream struct {
	Name    string
	BaseURL string
	APIKey  string
	client  *http.Client
}

// loadUpstreams 从环境变量读上游配置。
//
// 只配国内可直连的：这台机器连不上 OpenAI，Anthropic 也被按地区拒绝（403）。
// 硬配上去只会让用户选了之后拿到一个看不懂的超时。
func loadUpstreams() map[string]Upstream {
	client := &http.Client{
		// 不设整体 Timeout：流式补全可能跑很久，设了会在中途掐断。
		// 用 Transport 层的超时控制建连和响应头阶段就够。
		Transport: &http.Transport{
			ResponseHeaderTimeout: 60 * time.Second,
			IdleConnTimeout:       90 * time.Second,
			MaxIdleConnsPerHost:   32,
		},
	}

	candidates := []struct{ name, urlEnv, keyEnv, defaultURL string }{
		{"deepseek", "DEEPSEEK_BASE_URL", "DEEPSEEK_API_KEY", "https://api.deepseek.com/v1"},
		{"dashscope", "DASHSCOPE_BASE_URL", "DASHSCOPE_API_KEY",
			"https://dashscope.aliyuncs.com/compatible-mode/v1"},
		{"zhipu", "ZHIPU_BASE_URL", "ZHIPU_API_KEY", "https://open.bigmodel.cn/api/paas/v4"},
	}

	upstreams := make(map[string]Upstream)
	for _, candidate := range candidates {
		key := os.Getenv(candidate.keyEnv)
		if key == "" {
			continue // 没配 key 就不启用，不要留一个必然失败的选项
		}
		upstreams[candidate.name] = Upstream{
			Name:    candidate.name,
			BaseURL: envOr(candidate.urlEnv, candidate.defaultURL),
			APIKey:  key,
			client:  client,
		}
	}
	return upstreams
}

// publicModels 是对外暴露的两个套餐。
//
// 对外只有 yugit-standard / yugit-pro 两个名字，不暴露底层用的是谁：
// 换供应商时客户端不用改，涨价或降级也不影响已发布的版本。
var publicModels = []struct{ model, upstreamEnv, modelEnv string }{
	{"yugit-standard", "STANDARD_UPSTREAM", "STANDARD_MODEL"},
	{"yugit-pro", "PRO_UPSTREAM", "PRO_MODEL"},
}

// Route 是一个对外套餐的落点。
type Route struct {
	Upstream string // 上游名，对应 loadUpstreams 的 key
	Model    string // 上游那边真正的模型名
}

// resolveRouting 决定两个对外套餐分别落到哪个上游的哪个模型。
//
// **在启动时校验，不在请求时**。配错了就拒绝启动——
// 让它跑起来的话，用户要等到真的发请求才收到一句「不支持的模型」，
// 那时候既看不出是服务端配置问题，也不知道该找谁。
func resolveRouting(upstreams map[string]Upstream) (map[string]Route, error) {
	// 只配了一个上游时不必再指定路由：那是最常见的部署形态，
	// 逼人再配一遍只会制造「明明配了 key 却说模型不支持」的坑。
	var only string
	if len(upstreams) == 1 {
		for name := range upstreams {
			only = name
		}
	}

	routing := make(map[string]Route, len(publicModels))
	for _, item := range publicModels {
		upstream := envOr(item.upstreamEnv, only)
		if upstream == "" {
			return nil, fmt.Errorf(
				"配了多个上游，必须用 %s 指定 %s 走哪个", item.upstreamEnv, item.model)
		}
		if _, ok := upstreams[upstream]; !ok {
			return nil, fmt.Errorf(
				"%s 指向的上游 %q 没有配 API key", item.upstreamEnv, upstream)
		}

		// 模型名不给默认值：默认值只在「默认的那家上游」上是对的，
		// 换一家就变成一个必然 404 的名字，而且错得很隐蔽。
		model := os.Getenv(item.modelEnv)
		if model == "" {
			return nil, fmt.Errorf("必须设置 %s，指定 %s 用上游的哪个模型",
				item.modelEnv, item.model)
		}
		routing[item.model] = Route{Upstream: upstream, Model: model}
	}
	return routing, nil
}

// Forward 把请求转给上游，并把响应流原样透传给客户端。
func (u Upstream) Forward(
	ctx context.Context,
	w http.ResponseWriter,
	req *CompletionRequest,
	upstreamModel string,
) (UsageResult, error) {
	var result UsageResult

	// 原样带上客户端的其余参数，只改模型名和 usage 开关
	payload := make(map[string]any, len(req.raw)+1)
	for key, value := range req.raw {
		payload[key] = value
	}
	payload["model"] = upstreamModel

	if req.Stream {
		// 要上游在最后一个块里报真实用量。不要的话只能按字符估，
		// 而估算误差会直接变成计费误差。
		payload["stream_options"] = map[string]any{"include_usage": true}
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return result, err
	}

	upstreamReq, err := http.NewRequestWithContext(
		ctx, http.MethodPost, u.BaseURL+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		return result, err
	}
	upstreamReq.Header.Set("Content-Type", "application/json")
	upstreamReq.Header.Set("Authorization", "Bearer "+u.APIKey)
	upstreamReq.Header.Set("Accept", "text/event-stream")

	response, err := u.client.Do(upstreamReq)
	if err != nil {
		return result, &apiError{
			status:  http.StatusBadGateway,
			message: "上游连接失败：" + err.Error(),
		}
	}
	defer response.Body.Close()

	if response.StatusCode < 200 || response.StatusCode >= 300 {
		detail, _ := io.ReadAll(io.LimitReader(response.Body, 4096))
		// 上游的错误原样透传状态码，但不透传报文——
		// 那里面可能带着我们的 API key 或内部地址。
		return result, &apiError{
			status:  response.StatusCode,
			message: "上游返回错误：" + summarizeUpstreamError(detail),
		}
	}

	if !req.Stream {
		return u.forwardWhole(w, response, &result)
	}
	return u.forwardStream(ctx, w, response, &result)
}

// forwardStream 逐块透传 SSE。
//
// 这里最容易写错的是**缓冲**：不逐块 Flush 的话，Go 的 http 会攒够
// 缓冲区才发出去，客户端看到的就是「卡半天然后一次性蹦出全文」——
// 流式的意义全没了。
func (u Upstream) forwardStream(
	ctx context.Context,
	w http.ResponseWriter,
	response *http.Response,
	result *UsageResult,
) (UsageResult, error) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		return *result, &apiError{status: http.StatusInternalServerError, message: "响应不支持流式"}
	}

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	// 关掉 nginx 的代理缓冲，否则前面做的 Flush 会在 nginx 那一层又被攒起来
	w.Header().Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)
	result.HeadersSent = true
	flusher.Flush()

	var collected strings.Builder
	scanner := bufio.NewScanner(response.Body)
	// 单行上限调大：一个 SSE 事件里可能有很长的内容块，默认 64KB 会截断
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)

	for scanner.Scan() {
		line := scanner.Text()

		// 原样转发，一个字节都不改——客户端的 SSE 解析器按标准格式写的
		if _, err := fmt.Fprintf(w, "%s\n", line); err != nil {
			// 客户端断开了。不是错误，是常态（用户切走了界面）。
			return *result, nil
		}
		flusher.Flush()

		// 顺路把用量和正文抠出来记账，不影响转发
		if payload, found := strings.CutPrefix(line, "data: "); found {
			if payload != "[DONE]" {
				inspectChunk([]byte(payload), result, &collected)
			}
		}

		select {
		case <-ctx.Done():
			return *result, nil
		default:
		}
	}

	result.CollectedText = collected.String()
	if err := scanner.Err(); err != nil {
		return *result, err
	}
	return *result, nil
}

// forwardWhole 转发非流式响应。
func (u Upstream) forwardWhole(
	w http.ResponseWriter,
	response *http.Response,
	result *UsageResult,
) (UsageResult, error) {
	body, err := io.ReadAll(io.LimitReader(response.Body, 8<<20))
	if err != nil {
		return *result, err
	}

	var collected strings.Builder
	inspectChunk(body, result, &collected)
	result.CollectedText = collected.String()

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	result.HeadersSent = true
	_, _ = w.Write(body)
	return *result, nil
}

// inspectChunk 从一个响应块里抠出用量和正文。
//
// 解析失败一律忽略：记账出错不该影响用户拿到回复。
// 拿不到真实用量时上层会按字符估算。
func inspectChunk(payload []byte, result *UsageResult, collected *strings.Builder) {
	var chunk struct {
		Choices []struct {
			Delta   struct{ Content string } `json:"delta"`
			Message struct{ Content string } `json:"message"`
		} `json:"choices"`
		Usage *struct {
			PromptTokens     int `json:"prompt_tokens"`
			CompletionTokens int `json:"completion_tokens"`
		} `json:"usage"`
	}

	if err := json.Unmarshal(payload, &chunk); err != nil {
		return
	}

	if chunk.Usage != nil {
		result.InputTokens = chunk.Usage.PromptTokens
		result.OutputTokens = chunk.Usage.CompletionTokens
	}
	for _, choice := range chunk.Choices {
		collected.WriteString(choice.Delta.Content)
		collected.WriteString(choice.Message.Content)
	}
}

// summarizeUpstreamError 从上游错误里取一句人话。
//
// 只取 message 字段，不回传整个报文：那里面可能带着我们的 key 或内部地址。
func summarizeUpstreamError(body []byte) string {
	var parsed struct {
		Error struct {
			Message string `json:"message"`
		} `json:"error"`
		Message string `json:"message"`
	}
	if err := json.Unmarshal(body, &parsed); err == nil {
		if parsed.Error.Message != "" {
			return parsed.Error.Message
		}
		if parsed.Message != "" {
			return parsed.Message
		}
	}
	return "上游服务暂时不可用"
}

// estimateTokens 按字符数粗估 token 数。
//
// 只在上游不返回 usage 时用。中文约 1.5 字符/token，英文约 4 字符/token，
// 代码介于两者之间。取 2 是**偏保守的**——宁可多扣一点也不要少扣，
// 少扣的那部分是实打实的亏损，而多扣会被用户发现并投诉，能纠正。
func estimateTokens(text string) int {
	if text == "" {
		return 0
	}
	count := len([]rune(text)) / 2
	if count < 1 {
		return 1
	}
	return count
}
