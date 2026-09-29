.PHONY: app install run demo preview icons extension-zip clean

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

extension-zip:
	mkdir -p build && rm -f build/touchtabs-extension.zip
	cd extension && zip -qr ../build/touchtabs-extension.zip . -x '.*'

clean:
	rm -rf build app/.build
