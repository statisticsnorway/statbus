BINARY   := sb
OUT      := ../$(BINARY)
MODULE   := github.com/statisticsnorway/statbus/cli
VERSION  ?= dev
COMMIT   := $(shell git rev-parse --short=8 HEAD 2>/dev/null || echo unknown)
LDFLAGS  := -s -w -X '$(MODULE)/cmd.version=$(VERSION)' -X '$(MODULE)/cmd.commit=$(COMMIT)'
GOFLAGS  := -trimpath

.PHONY: build build-all test lint clean

build:
	CGO_ENABLED=0 go build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o $(OUT) .

build-all: dist/$(BINARY)-linux-amd64 dist/$(BINARY)-linux-arm64 dist/$(BINARY)-darwin-amd64 dist/$(BINARY)-darwin-arm64

dist/$(BINARY)-linux-amd64:
	@mkdir -p dist
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o $@ .

dist/$(BINARY)-linux-arm64:
	@mkdir -p dist
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o $@ .

dist/$(BINARY)-darwin-amd64:
	@mkdir -p dist
	CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o $@ .

dist/$(BINARY)-darwin-arm64:
	@mkdir -p dist
	CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o $@ .

test:
	go test ./...

lint:
	go vet ./...

clean:
	rm -f $(OUT)
	rm -rf dist/
