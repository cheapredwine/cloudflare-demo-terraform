.PHONY: help deploy deploy-demo reset destroy fresh smoke test latency analytics tf-all tf-state tf-drift

help:
	@printf "Cloudflare Demo Platform\n\n"
	@printf "Lifecycle:\n"
	@printf "  make deploy        Deploy platform\n"
	@printf "  make deploy-demo   Deploy + demo API flow\n"
	@printf "  make reset         Re-seed data, keep infra\n"
	@printf "  make destroy       Tear down infra\n"
	@printf "  make fresh         Destroy + redeploy\n\n"
	@printf "Validation:\n"
	@printf "  make smoke         Fast endpoint + queue consumer checks\n"
	@printf "  make test          Full integration suite\n\n"
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
