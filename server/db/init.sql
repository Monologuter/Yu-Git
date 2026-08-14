-- 驭Git 云服务的数据模型。
--
-- 刻意做得很小：这个服务只管订阅、额度和转发，**不存任何用户代码，
-- 也不存请求内容**。用户的 diff 经过这里但不落盘——这是隐私承诺的一部分，
-- 也让数据库泄露的后果小得多。

-- 订阅者
CREATE TABLE IF NOT EXISTS subscribers (
    id              BIGSERIAL   PRIMARY KEY,

    -- 凭据只存 SHA-256 哈希，不存明文。数据库泄露也拿不到能用的凭据，
    -- 代价是凭据无法找回，只能重新签发——这个取舍是对的。
    credential_hash TEXT        NOT NULL UNIQUE,

    -- 给运维看的备注（谁的订阅），不参与鉴权
    label           TEXT,

    status          TEXT        NOT NULL DEFAULT 'active',

    -- 本周期额度。用「已用」累加而不是「剩余」递减：
    -- 重置周期只要把 used_tokens 清零，而且能和流水表对上账。
    -- 递减的话一旦某次扣减出错，就再也对不回来了。
    total_tokens    BIGINT      NOT NULL DEFAULT 0,
    used_tokens     BIGINT      NOT NULL DEFAULT 0,

    renews_at       TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT status_valid CHECK (status IN ('active', 'expired', 'invalid'))
);

-- 用量流水。对账与排查用，同样不含任何请求内容。
CREATE TABLE IF NOT EXISTS usage_records (
    id            BIGSERIAL   PRIMARY KEY,
    subscriber_id BIGINT      NOT NULL REFERENCES subscribers(id) ON DELETE CASCADE,
    model         TEXT        NOT NULL,
    input_tokens  INTEGER     NOT NULL DEFAULT 0,
    output_tokens INTEGER     NOT NULL DEFAULT 0,

    -- 上游没返回 usage 时按字符估算。标出来，免得对账时把估算值当成精确值。
    estimated     BOOLEAN     NOT NULL DEFAULT FALSE,

    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_usage_subscriber_time
    ON usage_records (subscriber_id, created_at DESC);
