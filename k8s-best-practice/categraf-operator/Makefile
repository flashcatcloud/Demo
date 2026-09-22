.PHONY: build test docker dockerx lint clean deploy undeploy

IMG ?= flashcat/categraf-operator:latest
PLATFORMS ?= linux/amd64,linux/arm64

build:
	go build -o bin/categraf-operator ./cmd/operator

test:
	go test -v -race -count=1 ./...

docker:
	docker build -t $(IMG) .

dockerx:
	docker buildx build --platform $(PLATFORMS) -t $(IMG) --push .

lint:
	golangci-lint run ./...

clean:
	rm -rf bin/

deploy:
	kubectl apply -f deploy/rbac.yaml
	kubectl apply -f deploy/configmap.yaml
	kubectl apply -f deploy/deployment.yaml

undeploy:
	kubectl delete -f deploy/deployment.yaml
	kubectl delete -f deploy/configmap.yaml
	kubectl delete -f deploy/rbac.yaml
