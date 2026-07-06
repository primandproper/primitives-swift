# ENVIRONMENT
PWD := $(shell pwd)

# PATHS
SOURCES_DIR := Sources
TESTS_DIR   := Tests
FORMAT_PATHS := Package.swift $(SOURCES_DIR) $(TESTS_DIR)

# COMMANDS
SWIFT      := swift
XCODEBUILD := xcodebuild

# iOS build/test settings (override on the command line, e.g. `make test-ios IOS_SIM="iPhone 16 Pro"`)
IOS_SIM        := iPhone 16
IOS_BUILD_DEST := generic/platform=iOS
PACKAGE_SCHEME := platform-swift-Package

## PREREQUISITES

.PHONY: setup
setup: resolve

.PHONY: resolve
resolve:
	$(SWIFT) package resolve

.PHONY: clean
clean:
	$(SWIFT) package clean
	@rm -rf .build

## FORMATTING

.PHONY: format
format:
	$(SWIFT) format --recursive --in-place $(FORMAT_PATHS)

.PHONY: fmt
fmt: format

## LINTING

.PHONY: lint
lint:
	$(SWIFT) format lint --recursive --strict $(FORMAT_PATHS)

## EXECUTION

.PHONY: build
build:
	$(SWIFT) build

.PHONY: build-ios
build-ios:
	$(XCODEBUILD) -scheme Observability -destination '$(IOS_BUILD_DEST)' build

.PHONY: test
test:
	$(SWIFT) test

# Runs the test suite with coverage instrumentation and exports an lcov report
# (coverage.lcov) that Codecov understands. Paths (the merged .profdata and the
# instrumented test bundle) are resolved from `.build` so this works regardless
# of the debug/release bin path.
COVERAGE_FILE := coverage.lcov
.PHONY: coverage
coverage:
	$(SWIFT) test --enable-code-coverage
	@bin=$$($(SWIFT) build --show-bin-path); \
	prof="$$bin/codecov/default.profdata"; \
	xctest=$$(find "$$bin" -maxdepth 1 -name '*.xctest' | head -1); \
	if [ -z "$$xctest" ]; then echo "no .xctest bundle in $$bin"; exit 1; fi; \
	if [ -d "$$xctest/Contents/MacOS" ]; then \
		binary="$$xctest/Contents/MacOS/$$(basename "$$xctest" .xctest)"; \
	else \
		binary="$$xctest"; \
	fi; \
	xcrun llvm-cov export -format=lcov -instr-profile "$$prof" "$$binary" > $(COVERAGE_FILE); \
	echo "wrote $(COVERAGE_FILE)"

.PHONY: test-ios
test-ios:
	@udid=$$(xcrun simctl list devices available | grep -m1 "$(IOS_SIM) (" | grep -oE '[0-9A-F-]{36}'); \
	if [ -z "$$udid" ]; then echo "no available simulator named '$(IOS_SIM)' (override with IOS_SIM=...)"; exit 1; fi; \
	$(XCODEBUILD) -scheme $(PACKAGE_SCHEME) -destination "id=$$udid" test
