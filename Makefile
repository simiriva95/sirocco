APP        := Sirocco
SCHEME     := Sirocco
PROJECT    := $(APP).xcodeproj
BUILD_DIR  := build
DIST_DIR   := dist
XCB        := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS,arch=arm64' -derivedDataPath $(BUILD_DIR)
QUIET      := -quiet

.PHONY: gen dev build run test lint clean notarize unlock-hash release dmg appcast
SPARKLE_BIN := $(BUILD_DIR)/SourcePackages/artifacts/sparkle/Sparkle/bin
RELEASES_DIR := $(BUILD_DIR)/releases-repo
RELEASE_REPO := simiriva95/sirocco-releases
VERSION := $(shell sed -n 's/.*MARKETING_VERSION: //p' project.yml)

## gen: regenerate the Xcode project from project.yml (never edit the .xcodeproj by hand)
gen:
	@[ -f Sources/Licensing/UnlockSecret.swift ] || cp Sources/Licensing/UnlockSecret.swift.example Sources/Licensing/UnlockSecret.swift
	xcodegen generate --quiet

## dev: debug build + launch
dev: gen
	$(XCB) -configuration Debug build $(QUIET)
	@pkill -x $(APP) || true
	open $(BUILD_DIR)/Build/Products/Debug/$(APP).app

## build: release build, exported to dist/ as .app
build: gen
	$(XCB) -configuration Release build $(QUIET)
	rm -rf $(DIST_DIR) && mkdir -p $(DIST_DIR)
	cp -R $(BUILD_DIR)/Build/Products/Release/$(APP).app $(DIST_DIR)/
	@echo "→ $(DIST_DIR)/$(APP).app"

## dmg: the installer — a disk image with the app and a link to /Applications
dmg: build
	rm -rf $(DIST_DIR)/dmg && mkdir -p $(DIST_DIR)/dmg
	cp -R $(DIST_DIR)/$(APP).app $(DIST_DIR)/dmg/
	ln -s /Applications $(DIST_DIR)/dmg/Applications
	hdiutil create -quiet -volname "$(APP) $(VERSION)" -srcfolder $(DIST_DIR)/dmg -ov -format UDZO $(DIST_DIR)/$(APP)-$(VERSION).dmg
	rm -rf $(DIST_DIR)/dmg
	@echo "→ $(DIST_DIR)/$(APP)-$(VERSION).dmg"

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

## unlock-hash: set the owner's unlock password (typed locally, only its PBKDF2 hash is stored)
unlock-hash:
	swift Tools/unlock-hash.swift

## release: dmg → GitHub release in the downloads repo → EdDSA-signed appcast pushed there
release: dmg
	@[ "$$(defaults read $(PWD)/$(DIST_DIR)/$(APP).app/Contents/Info.plist CFBundleShortVersionString)" = "$(VERSION)" ] || { echo "Info.plist version mismatch"; exit 1; }
	gh release create v$(VERSION) $(DIST_DIR)/$(APP)-$(VERSION).dmg -R $(RELEASE_REPO) --title "$(APP) $(VERSION)" \
		--notes "$$(awk '/^## /{n++} n==1' CHANGELOG.md)"
	$(MAKE) appcast

## appcast: regenerate appcast.xml from dist/*.dmg (signs with the EdDSA key in the login keychain)
appcast:
	rm -rf $(RELEASES_DIR) ~/Library/Caches/Sparkle_generate_appcast && gh repo clone $(RELEASE_REPO) $(RELEASES_DIR) -- -q
	rm -f $(RELEASES_DIR)/appcast.xml   # regenerate from dist/ only: one item, the current version
	$(SPARKLE_BIN)/generate_appcast --download-url-prefix https://github.com/$(RELEASE_REPO)/releases/download/v$(VERSION)/ \
		-o $(RELEASES_DIR)/appcast.xml $(DIST_DIR)
	cd $(RELEASES_DIR) && git add appcast.xml && git commit -qm "appcast: $(APP) $(VERSION)" && git push -q origin main
	@echo "→ appcast published"

## notarize: phase 2 (M6). Requires a Developer ID certificate.
notarize:
	@echo "notarization is scheduled for M6 (needs Developer ID + notarytool credentials)"; exit 1
