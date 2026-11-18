# syntax=docker/dockerfile:1.6
ARG CADDY_VERSION=2
FROM caddy:${CADDY_VERSION}-builder AS builder

RUN xcaddy build \
    --with github.com/mholt/caddy-l4

FROM caddy:${CADDY_VERSION}-alpine

COPY --from=builder /usr/bin/caddy /usr/bin/caddy

# WebSockets ride the site's shared HTTP/2 connection (RFC 8441 extended CONNECT). Go's HTTP/2
# server announces it only with this switch. Without it a browser opens each WebSocket on its own
# HTTP/1.1 connection, which counts against the browser's six per site, so a few stuck
# connections queue every new WebSocket behind them (task khwbf3).
ENV GODEBUG=http2xconnect=1
