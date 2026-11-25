.DEFAULT_GOAL := help
ENV ?= staging

help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

up: ## Run both services + MySQL locally
	docker compose up --build -d
	@echo "orders-api: http://localhost:8000/orders  notify-svc: http://localhost:3000/notify"

down: ## Stop local stack and remove volumes
	docker compose down -v

logs: ## Tail local logs
	docker compose logs -f

test: ## Run unit tests for both services
	cd apps/orders-api && python -m pytest -q
	cd apps/notify-svc && npm test

lint: ## Lint code, Dockerfiles and Terraform
	pre-commit run --all-files

tf-validate: ## terraform fmt + validate for every environment
	terraform fmt -check -recursive infra
	for env in staging production; do \
	  terraform -chdir=infra/envs/$$env init -backend=false -input=false >/dev/null && \
	  terraform -chdir=infra/envs/$$env validate; \
	done

plan: ## terraform plan for ENV (needs TF_STATE_BUCKET and IMAGE_TAG)
	@test -n "$(TF_STATE_BUCKET)" || (echo "Set TF_STATE_BUCKET (output of infra/bootstrap)"; exit 1)
	terraform -chdir=infra/envs/$(ENV) init -input=false -backend-config="bucket=$(TF_STATE_BUCKET)"
	terraform -chdir=infra/envs/$(ENV) plan -input=false -var image_tag=$(or $(IMAGE_TAG),$(shell git rev-parse --short HEAD))

security-scan: ## checkov (Terraform) + trivy (images) + gitleaks (history)
	checkov -d infra --framework terraform --quiet --compact
	trivy image --severity HIGH,CRITICAL --ignore-unfixed --ignorefile .trivyignore orders-api:local
	trivy image --severity HIGH,CRITICAL --ignore-unfixed --ignorefile .trivyignore notify-svc:local
	gitleaks git . --no-banner

.PHONY: help up down logs test lint tf-validate plan security-scan
