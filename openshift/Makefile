NIGHTLY_YAML=https://raw.githubusercontent.com/openshift/tektoncd-pipeline/release-next/openshift/release/tektoncd-pipeline-nightly.yaml
STABLE_VERSION=$(shell curl -s https://api.github.com/repos/tektoncd/pipeline/releases | python -c "import sys, json;x=json.load(sys.stdin);print(x[0]['tag_name'])")
RELEASE_YAML=

test-e2e-downstream-nightly:
	@make test-e2e-downstream RELEASE_YAML=$(NIGHTLY_YAML)
.PHONY: test-e2e-downstream-nightly

test-e2e-downstream-stable:
	@make test-e2e-downstream \
		RELEASE_YAML=https://raw.githubusercontent.com/openshift/tektoncd-pipeline/release-$(STABLE_VERSION)/openshift/release/tektoncd-pipeline-$(STABLE_VERSION).yaml
.PHONY: test-e2e-downstream-stable

test-e2e-downstream:
	@make -C ../ bin/tkn
	@env RELEASE_YAML=$(RELEASE_YAML) LOCAL_CI_RUN=true ../test/e2e-tests.sh
.PHONY: test-e2e-downstream
