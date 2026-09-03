APP        := Sirocco
SCHEME     := Sirocco
PROJECT    := $(APP).xcodeproj
BUILD_DIR  := build
DIST_DIR   := dist
XCB        := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS,arch=arm64' -derivedDataPath $(BUILD_DIR)
QUIET      := -quiet

.PHONY: gen dev build run test lint clean notarize

## gen: regenerate the Xcode project from project.yml (never edit the .xcodeproj by hand)
gen:
	xcodegen generate --quiet

## dev: debug build + launch
dev: gen
	$(XCB) -configuration Debug build $(QUIET)
	@pkill -x $(APP) || true
	open $(BUILD_DIR)/Build/Products/Debug/$(APP).app

## build: release build, exported to dist/ as .app and .zip
build: gen
	$(XCB) -configuration Release build $(QUIET)
	rm -rf $(DIST_DIR) && mkdir -p $(DIST_DIR)
	cp -R $(BUILD_DIR)/Build/Products/Release/$(APP).app $(DIST_DIR)/
	cd $(DIST_DIR) && ditto -c -k --keepParent $(APP).app $(APP).zip
	@echo "→ $(DIST_DIR)/$(APP).zip"

## run: launch the last debug build without rebuilding
run:
	open $(BUILD_DIR)/Build/Products/Debug/$(APP).app

## test: unit tests (Metrics, Diagnosis, Processes policy)
test: gen
	$(XCB) -configuration Debug test $(QUIET)

## lint: swiftlint if installed, otherwise strict-concurrency build acts as the linter
lint: gen
	@command -v swiftlint >/dev/null && swiftlint --strict || echo "swiftlint not installed; strict-concurrency build is the lint gate"

clean:
	rm -rf $(BUILD_DIR) $(DIST_DIR) $(PROJECT)

## notarize: phase 2 (M6). Requires a Developer ID certificate.
notarize:
	@echo "notarization is scheduled for M6 (needs Developer ID + notarytool credentials)"; exit 1
