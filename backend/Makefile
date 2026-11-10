.PHONY: dev real usage test build docker

# Places・認証・保存先をすべてダミーにして起動する
dev:
	AUTH_MODE=fake STORE_MODE=memory go run ./cmd/server

# .env の PLACES_API_KEY で本物の Places API を呼ぶ。認証と保存先はダミーのままなので Firebase はいらない
real:
	set -a; . ./.env; set +a; AUTH_MODE=fake STORE_MODE=memory go run ./cmd/server

# Places API の呼び出し回数と料金の目安を表示する
usage:
	@curl -s localhost:8080/api/usage | python3 -m json.tool --no-ensure-ascii

test:
	go vet ./...
	go test -race ./...

build:
	go build -o bin/server ./cmd/server

docker:
	docker build -t uramichi-api .
