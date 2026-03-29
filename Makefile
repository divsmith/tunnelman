# ── Configuration ─────────────────────────────────────────────────────────────
APP_NAME      := TunnelMan
BUNDLE_ID     := com.tunnelman.app
VERSION       := 1.0.0
OUTPUT_DIR    := output
BUNDLE_DIR    := $(OUTPUT_DIR)/$(APP_NAME).app
CONTENTS_DIR  := $(BUNDLE_DIR)/Contents
MACOS_DIR     := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources
BINARY        := .build/release/$(APP_NAME)

define PLIST_CONTENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$(APP_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(BUNDLE_ID)</string>
    <key>CFBundleName</key>
    <string>$(APP_NAME)</string>
    <key>CFBundleDisplayName</key>
    <string>$(APP_NAME)</string>
    <key>CFBundleVersion</key>
    <string>$(VERSION)</string>
    <key>CFBundleShortVersionString</key>
    <string>$(VERSION)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
endef
export PLIST_CONTENT

.PHONY: all build debug test clean run open help

all: build

build:
	@echo "▸ Building $(APP_NAME) (release)…"
	swift build -c release
	@[ -f "$(BINARY)" ] || { echo "✗ Build failed — binary not found at $(BINARY)" >&2; exit 1; }
	@RSRC=$$(find .build -path "*/release/$(APP_NAME)_TunnelManServer.bundle" -type d | head -1); \
	[ -n "$$RSRC" ] || { echo "✗ Resource bundle not found in .build/" >&2; exit 1; }; \
	echo "▸ Creating $(APP_NAME).app bundle…"; \
	rm -rf "$(BUNDLE_DIR)"; \
	mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"; \
	cp "$(BINARY)" "$(MACOS_DIR)/$(APP_NAME)"; \
	cp -R "$$RSRC" "$(BUNDLE_DIR)/$(APP_NAME)_TunnelManServer.bundle"; \
	echo "$$PLIST_CONTENT" > "$(CONTENTS_DIR)/Info.plist"; \
	APP_SIZE=$$(du -sh "$(BUNDLE_DIR)" | cut -f1); \
	printf '\n✔ %s (%s)\n\n  Run:  open %s\n  Or:   %s/%s\n' \
		"$(BUNDLE_DIR)" "$$APP_SIZE" "$(BUNDLE_DIR)" "$(MACOS_DIR)" "$(APP_NAME)"

debug:
	@echo "▸ Building $(APP_NAME) (debug)…"
	swift build

test:
	@echo "▸ Running tests…"
	swift test

clean:
	@echo "▸ Cleaning…"
	rm -rf .build $(OUTPUT_DIR)
	@echo "✔ Cleaned"

run: build
	"$(MACOS_DIR)/$(APP_NAME)"

open: build
	open "$(BUNDLE_DIR)"

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  build   Build release .app bundle (default)"
	@echo "  debug   Build debug binary"
	@echo "  test    Run tests"
	@echo "  run     Build and run the app"
	@echo "  open    Build and open the .app"
	@echo "  clean   Remove .build and $(OUTPUT_DIR)/"
