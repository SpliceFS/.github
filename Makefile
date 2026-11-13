check:
	sh processes/check-modes.sh
	for test in $$(find processes -name '*-test.sh' | sort); do sh "$$test" || exit 1; done

lint:
	find processes -name '*.sh' | sort | xargs shellcheck --shell=sh

.PHONY: check lint
