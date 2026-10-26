.PHONY: generate build test run agent-help release-build release screenshots audit clean

generate:
	xcodegen generate

build: generate
	xcodebuild -project ManuscriptMatrix.xcodeproj -scheme ManuscriptMatrix -configuration Debug -destination 'platform=macOS' -derivedDataPath '$(CURDIR)/DerivedData' CODE_SIGNING_ALLOWED=NO build

test:
	env SWIFTPM_MODULECACHE_OVERRIDE='$(CURDIR)/.build/ModuleCache' CLANG_MODULE_CACHE_PATH='$(CURDIR)/.build/ModuleCache' swift test --disable-sandbox --package-path Packages/ManuscriptKit

run: build
	open '$(CURDIR)/DerivedData/Build/Products/Debug/Manuscript Matrix.app' --args --demo

agent-help:
	env SWIFTPM_MODULECACHE_OVERRIDE='$(CURDIR)/.build/ModuleCache' CLANG_MODULE_CACHE_PATH='$(CURDIR)/.build/ModuleCache' swift run --disable-sandbox --package-path Packages/ManuscriptKit manuscript-matrix-agent help

release-build:
	bash scripts/build-release.sh

release:
	bash scripts/package-release.sh

screenshots:
	bash scripts/screenshots.sh

audit:
	python3 scripts/audit-release.py

clean:
	swift package --package-path Packages/ManuscriptKit clean
	xcodebuild -project ManuscriptMatrix.xcodeproj -scheme ManuscriptMatrix clean
