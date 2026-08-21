# whitelimo — a Nature Remo menu bar app for macOS.
#
# The interesting targets:
#
#   make test        run the unit tests
#   make app         build whitelimo.app in dist/ (VERSION=v1.2.3 to stamp it)
#   make run         build and launch the app bundle
#   make package     zip the app bundle for a release
#   make lint        format check plus the shell script tests

VERSION ?= dev
DIST ?= dist
# A single-architecture build is much quicker while developing; releases are
# universal.
UNIVERSAL ?= 0

.PHONY: build test app run package lint format clean

build:
	swift build

test:
	swift test
	sh Scripts/next-version_test.sh

app:
	VERSION=$(VERSION) DIST=$(DIST) UNIVERSAL=$(UNIVERSAL) sh Scripts/bundle.sh

run: app
	open $(DIST)/whitelimo.app

package:
	VERSION=$(VERSION) DIST=$(DIST) UNIVERSAL=1 sh Scripts/package.sh

lint:
	swift build --build-tests
	sh Scripts/next-version_test.sh

clean:
	swift package clean
	rm -rf $(DIST) .build
