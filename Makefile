.PHONY: lint help deploy deploy-demo reset destroy fresh smoke test verify fmt validate tftest latency analytics tf-all tf-state tf-drift

help:
	@printf "Cloudflare Demo Platform\n\n"
	@printf "Lifecycle:\n"
	@printf "  make deploy        Deploy platform\n"
	@printf "  make deploy-demo   Deploy + demo API flow\n"
	@printf "  make reset         Re-seed data, keep infra\n"
	@printf "  make destroy       Tear down infra\n"
	@printf "  make fresh         Destroy + redeploy\n\n"
	@printf "Validation:\n"
	@printf "  make verify        lint + config guards + fmt + validate + terraform test (offline)\n"
	@printf "  make lint          shellcheck/shfmt + JS/Python syntax checks\n"
	@printf "  make fmt           terraform fmt -recursive -check\n"
	@printf "  make validate      terraform validate\n"
	@printf "  make tftest        terraform test (mocked, offline)\n"
	@printf "  make smoke         Fast endpoint + queue consumer checks\n"
	@printf "  make test          Full integration suite (requires deployed platform)\n\n"
	@printf "Demos:\n"
	@printf "  make latency       Cache HIT vs MISS latency demo\n"
	@printf "  make analytics     Workers analytics traffic demo\n"
	@printf "  make tf-state      Terraform state inspection demo\n"
	@printf "  make tf-drift      Terraform drift detection demo\n"
	@printf "  make tf-all        Run all Terraform concept demos\n"

deploy:
	./scripts/lifecycle/run-demo.sh deploy

deploy-demo:
	./scripts/lifecycle/run-demo.sh deploy --demo

reset:
	./scripts/lifecycle/run-demo.sh reset

destroy:
	./scripts/lifecycle/run-demo.sh destroy

fresh:
	./scripts/lifecycle/run-demo.sh fresh

smoke:
	./scripts/lifecycle/run-demo.sh test

verify: lint config-checks fmt validate tftest

lint:
	shellcheck $$(git ls-files '*.sh')
	@if command -v shfmt >/dev/null; then shfmt -d $$(git ls-files '*.sh'); else echo "shfmt not installed; skipping format check"; fi
	@for f in $$(git ls-files 'workers/*.js'); do node --check "$$f" || exit 1; done
	python3 -m py_compile scripts/empty-r2.py
	@echo "lint: all checks passed"

config-checks:
	bash scripts/tests/config-checks.sh

fmt:
	terraform fmt -recursive -check

validate:
	terraform validate

tftest:
	terraform test

test:
	./scripts/tests/test.sh

latency:
	./scripts/demos/demo-latency.sh

analytics:
	./scripts/demos/demo-analytics.sh

tf-state:
	./scripts/demos/terraform-demo.sh state-inspect

tf-drift:
	./scripts/demos/terraform-demo.sh drift-detect

tf-all:
	./scripts/demos/terraform-demo.sh all
