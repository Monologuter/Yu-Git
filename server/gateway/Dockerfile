# 两段式构建：编译产物只有一个静态二进制，
# 最终镜像不带 Go 工具链——小、也少一大片攻击面。
FROM golang:1.23-alpine AS build

# 这台机器在国内，proxy.golang.org 连不上。
# GOSUMDB 也得换，否则校验和查询会卡到超时。
ENV GOPROXY=https://goproxy.cn,direct \
    GOSUMDB=sum.golang.google.cn

WORKDIR /src

# 依赖单独一层：go.mod/go.sum 没变时 Docker 直接复用缓存，
# 改一行业务代码不用重新拉依赖。
COPY go.mod go.sum ./
RUN go mod download

COPY *.go ./

# -mod=readonly：构建时绝不隐式改 go.mod/go.sum。
#   少了它，依赖被悄悄换掉也能构建成功——那正是供应链攻击的入口。
# -trimpath：去掉构建机的绝对路径，同样的源码在哪台机器上构建都得到同样的二进制。
# CGO_ENABLED=0：静态链接，才能跑在没有 glibc 的 alpine 上。
RUN CGO_ENABLED=0 go build -mod=readonly -trimpath -ldflags="-s -w" -o /gateway .

FROM alpine:3.20

# ca-certificates：要用 HTTPS 连上游模型服务，没有它所有请求都会证书校验失败。
# tzdata：日志时间戳要按东八区显示。
RUN apk add --no-cache ca-certificates tzdata \
    && adduser -D -u 10001 gateway

# 非 root 运行。网关直接暴露在公网前面，被打穿时不该拿到 root。
USER gateway

COPY --from=build /gateway /usr/local/bin/gateway

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/gateway"]
