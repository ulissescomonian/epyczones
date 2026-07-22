APP_NAME := EpycZones
APP_BUNDLE := .build/$(APP_NAME).app

.PHONY: build debug icon bundle run dmg clean

debug:
	swift build

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
