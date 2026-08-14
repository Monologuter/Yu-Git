package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var errNotFound = errors.New("not found")

// Subscriber 是一位订阅者。
type Subscriber struct {
	ID          int64
	Status      string
	TotalTokens int64
	UsedTokens  int64
	RenewsAt    *time.Time
}

// Store 是数据库访问层。
type Store struct {
	pool *pgxpool.Pool
}

// FindByCredentialHash 按凭据哈希查订阅者。
//
// 顺带处理过期：到了续期时间还没续的，状态自动落到 expired。
// 靠定时任务改状态的话，任务挂了就会有人白嫖到下次任务跑起来。
func (s *Store) FindByCredentialHash(ctx context.Context, hash string) (*Subscriber, error) {
	const query = `
        SELECT id, status, total_tokens, used_tokens, renews_at
        FROM subscribers
        WHERE credential_hash = $1
    `

	var sub Subscriber
	err := s.pool.QueryRow(ctx, query, hash).Scan(
		&sub.ID, &sub.Status, &sub.TotalTokens, &sub.UsedTokens, &sub.RenewsAt)

	if errors.Is(err, pgx.ErrNoRows) {
		return nil, errNotFound
	}
	if err != nil {
		return nil, err
	}

	if sub.Status == "active" && sub.RenewsAt != nil && sub.RenewsAt.Before(time.Now()) {
		sub.Status = "expired"
	}

	return &sub, nil
}

// RecordUsage 记一笔用量并累加已用额度。
//
// 两条语句放同一个事务：只写流水不扣额度会让人白用，
// 只扣额度不写流水则对不上账。
func (s *Store) RecordUsage(
	ctx context.Context,
	subscriberID int64,
	model string,
	inputTokens, outputTokens int,
	estimated bool,
) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx) //nolint:errcheck // 已提交时这里是 no-op

	_, err = tx.Exec(ctx, `
        INSERT INTO usage_records
            (subscriber_id, model, input_tokens, output_tokens, estimated)
        VALUES ($1, $2, $3, $4, $5)
    `, subscriberID, model, inputTokens, outputTokens, estimated)
	if err != nil {
		return err
	}

	_, err = tx.Exec(ctx, `
        UPDATE subscribers
        SET used_tokens = used_tokens + $2
        WHERE id = $1
    `, subscriberID, int64(inputTokens+outputTokens))
	if err != nil {
		return err
	}

	return tx.Commit(ctx)
}

// ── HTTP 辅助 ───────────────────────────────────────────────────────

// apiError 是一个能安全回给客户端的错误。
//
// 内部错误（数据库连不上之类）不走这里——那些只记日志，
// 对外统一说「服务暂时不可用」，免得把内部细节漏出去。
type apiError struct {
	status  int
	message string
}

func (e *apiError) Error() string { return e.message }

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func writeError(w http.ResponseWriter, err error) {
	var apiErr *apiError
	if errors.As(err, &apiErr) {
		writeJSON(w, apiErr.status, map[string]any{
			"error": map[string]string{"message": apiErr.message},
		})
		return
	}

	// 认不出的错误一律当成内部错误，只说一句笼统的话
	writeJSON(w, http.StatusInternalServerError, map[string]any{
		"error": map[string]string{"message": "服务暂时不可用"},
	})
}
