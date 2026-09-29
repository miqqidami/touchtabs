.PHONY: app install run demo preview icons extension-zip store store-zip store-assets release clean

app:
	./scripts/build-app.sh

# Opens the app from Finder: it registers itself with your browsers.
run: app
	open build/TouchTabs.app

# Copies the app to /Applications and registers it as the browsers' native
# messaging host. The extension then starts it whenever the browser runs.
install: app
	-pkill -x TouchTabs; sleep 1
	rm -rf /Applications/TouchTabs.app
	cp -R build/TouchTabs.app /Applications/
	/Applications/TouchTabs.app/Contents/MacOS/TouchTabs --install

# Shows sample tabs on the Touch Bar without a browser.
demo:
	cd app && swift run TouchTabs --demo

preview:
	cd app && swift run TouchTabs --render-preview ../docs/preview.png

# Regenerates the extension icons from the vector artwork.
icons:
	cd app && swift build && tmp=$$(mktemp -d) && .build/debug/TouchTabs --render-icons $$tmp && \
		cp $$tmp/icon16.png $$tmp/icon32.png $$tmp/icon48.png $$tmp/icon128.png ../extension/icons/ && rm -rf $$tmp

# Everything for the Chrome Web Store: build/touchtabs-store.zip plus the
# listing images in docs/store/. See docs/store/LISTING.md.
store: store-zip store-assets

# The store rejects a manifest `key`, so upload a copy without it.
store-zip:
	mkdir -p build && rm -rf build/store build/touchtabs-store.zip
	cp -R extension build/store
	python3 -c "import json; p = 'build/store/manifest.json'; m = json.load(open(p)); m.pop('key', None); open(p, 'w').write(json.dumps(m, indent=2, ensure_ascii=False) + '\n')"
	cd build/store && zip -qr ../touchtabs-store.zip . -x '.*'
	rm -rf build/store
	@echo "Built build/touchtabs-store.zip"

store-assets:
	cd app && swift build && .build/debug/TouchTabs --render-store ../docs/store

# The downloadable helper for a GitHub Release: build/TouchTabs.zip.
release: app
	rm -f build/TouchTabs.zip
	ditto -c -k --keepParent build/TouchTabs.app build/TouchTabs.zip
	@echo "Built build/TouchTabs.zip"

extension-zip:
	mkdir -p build && rm -f build/touchtabs-extension.zip
	cd extension && zip -qr ../build/touchtabs-extension.zip . -x '.*'

clean:
	rm -rf build app/.build
