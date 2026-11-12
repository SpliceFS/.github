check:
	sh scripts/change-scope-test.sh
	sh scripts/next-version-test.sh
	sh scripts/set-version-test.sh
	sh scripts/rebase-branch-test.sh

lint:
	shellcheck --shell=sh scripts/*.sh

.PHONY: check lint
