# VIZION — developer entry points. `make help` lists them.
.DEFAULT_GOAL := help
SHELL := /bin/bash

help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

bootstrap: ## One-time setup: secrets template, xcodegen, project generation
	./scripts/bootstrap.sh

generate: ## Regenerate VIZION.xcodeproj from project.yml
	xcodegen generate --spec project.yml

open: generate ## Generate and open in Xcode
	open VIZION.xcodeproj

core-test: ## Run the platform-agnostic core package tests (works on Linux + macOS)
	swift test --package-path Packages/VizionCore

core-build: ## Build the core package
	swift build --package-path Packages/VizionCore

lint: ## swiftlint + swiftformat --lint
	swiftlint --strict
	swiftformat --lint .

format: ## Apply swiftformat
	swiftformat .

ios-build: generate ## Build the app for the iOS Simulator (no signing)
	xcodebuild -project VIZION.xcodeproj -scheme VIZION \
	  -destination 'generic/platform=iOS Simulator' \
	  CODE_SIGNING_ALLOWED=NO build | xcbeautify || true

ios-test: generate ## Run the app's unit tests on a simulator
	xcodebuild -project VIZION.xcodeproj -scheme VIZION \
	  -destination 'platform=iOS Simulator,name=iPhone 17' \
	  CODE_SIGNING_ALLOWED=NO test | xcbeautify || true

clean: ## Remove generated project + build output
	rm -rf VIZION.xcodeproj DerivedData Packages/VizionCore/.build .build

.PHONY: help bootstrap generate open core-test core-build lint format ios-build ios-test clean
