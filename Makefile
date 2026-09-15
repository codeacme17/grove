.DEFAULT_GOAL := help
CONFIGURATION ?= release

.PHONY: help build-macos test-macos run-macos release-macos

help:
	@echo "make build-macos [CONFIGURATION=debug|release]"
	@echo "make test-macos"
	@echo "make run-macos [CONFIGURATION=debug|release]"
	@echo "make release-macos"

build-macos:
	bash apps/macos/scripts/build-app.sh "$(CONFIGURATION)"

test-macos:
	bash apps/macos/scripts/test.sh

release-macos:
	bash apps/macos/scripts/package-release.sh

run-macos: build-macos
	open apps/macos/dist/Grove.app
