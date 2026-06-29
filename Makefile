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

.PHONY: test-ios
test-ios:
	@udid=$$(xcrun simctl list devices available | grep -m1 "$(IOS_SIM) (" | grep -oE '[0-9A-F-]{36}'); \
	if [ -z "$$udid" ]; then echo "no available simulator named '$(IOS_SIM)' (override with IOS_SIM=...)"; exit 1; fi; \
	$(XCODEBUILD) -scheme $(PACKAGE_SCHEME) -destination "id=$$udid" test
