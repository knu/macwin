APP_BUNDLE ?= .build/MacWin.app
CONFIGURATION ?= release
PRODUCT := .build/$(CONFIGURATION)/macwin
SWIFT_BUILD_FLAGS := -c $(CONFIGURATION)
ifeq ($(DISABLE_SANDBOX),1)
SWIFT_BUILD_FLAGS += --disable-sandbox
endif

.PHONY: app build clean-app install-app

build:
	swift build $(SWIFT_BUILD_FLAGS)

app: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp App/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	cp App/MacWin.icns $(APP_BUNDLE)/Contents/Resources/MacWin.icns
	cp $(PRODUCT) $(APP_BUNDLE)/Contents/MacOS/macwin
	cp bin/macwin-cli $(APP_BUNDLE)/Contents/MacOS/macwin-cli
	chmod 755 $(APP_BUNDLE)/Contents/MacOS/macwin $(APP_BUNDLE)/Contents/MacOS/macwin-cli
	codesign --force --sign - --timestamp=none $(APP_BUNDLE)/Contents/MacOS/macwin-cli
	codesign --force --sign - --timestamp=none $(APP_BUNDLE)

install-app: app
	mkdir -p $(HOME)/Applications
	rm -rf $(HOME)/Applications/MacWin.app
	cp -R $(APP_BUNDLE) $(HOME)/Applications/MacWin.app

clean-app:
	rm -rf $(APP_BUNDLE)
