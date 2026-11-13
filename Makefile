# Nothing that must stay private may be tracked: no compiled program (it carries the folder
# names of the machine it was built on), no file over 1 MiB, no name of a private machine,
# account or place. The ignore rules help; this check is what stops a mistake.
.PHONY: tracked-files
tracked-files:
	scripts/tracked-files.sh

check: tracked-files
	sh processes/check-modes.sh
	for test in $$(find processes -name '*-test.sh' | sort); do sh "$$test" || exit 1; done

lint:
	find processes -name '*.sh' | sort | xargs shellcheck --shell=sh

.PHONY: check lint
