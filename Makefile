APP_NAME := EpycZones
APP_BUNDLE := .build/$(APP_NAME).app

.PHONY: build debug test strict screens icon bundle run dmg clean

debug:
	swift build

test:
	swift test

# Renders the app's screens to .build/screens for design review.
screens:
	EPYCZONES_SCREENS="$(CURDIR)/.build/screens" swift test --filter ScreenRenderTests

# Swift 6 concurrency checking, with every diagnostic treated as an error.
strict:
	swift build --build-path .build/strict -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors

build:
	swift build -c release --arch arm64

icon:
	./scripts/make_icon.sh

bundle:
	./scripts/package_app.sh

run: bundle
	open "$(APP_BUNDLE)"

dmg:
	OVERWRITE=1 ./scripts/package_dmg.sh

clean:
	swift package clean
	rm -rf -- .build/$(APP_NAME).app .build/AppIcon.icns dist
