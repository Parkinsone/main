.PHONY: help all setup install cluster preload deploy verify clean

help:
	@echo "Команды:"
	@echo "  make all       — полное развёртывание с нуля"
	@echo "  make install   — установка K8s"
	@echo "  make cluster   — создание кластера"
	@echo "  make preload   — доставка образов через Docker"
	@echo "  make deploy    — развёртывание всех компонентов"
	@echo "  make verify    — проверка приложения, метрик, логов"
	@echo "  make clean     — удалить все ресурсы"

all: install cluster preload deploy verify

install:
	sudo ./install.sh

cluster:
	./init-cluster.sh

preload:
	./preload-images.sh nginx:stable-alpine envoyproxy/gateway:v1.1.0 envoyproxy/envoy:distroless-v1.31.0 prom/prometheus:v2.55.0 fluent/fluent-bit:3.1.0

deploy:
	./deploy.sh

verify:
	@echo "===> Приложение"
	kubectl exec -n default deploy/nginx -- curl -s http://localhost/ ; echo
	@echo ""
	@echo "===> Gateway"
	kubectl get gateway,httproute -n default
	@echo ""
	@echo "===> Поды во всех namespace"
	kubectl get pods -A

clean:
	kubectl delete -f manifests/app/ --ignore-not-found
	kubectl delete -f manifests/monitoring/ --ignore-not-found
	kubectl delete -f manifests/logging/ --ignore-not-found
	kubectl delete -f gateway/gatewayclass.yaml gateway/gateway.yaml gateway/httproute.yaml --ignore-not-found
