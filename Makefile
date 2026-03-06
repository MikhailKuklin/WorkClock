APP_NAME = WorkClock
APP_BUNDLE = $(APP_NAME).app
INSTALL_DIR = /Applications
LAUNCH_AGENT = com.workclock.plist
LAUNCH_AGENTS_DIR = $(HOME)/Library/LaunchAgents

.PHONY: build install uninstall autostart clean

build:
	swiftc -o $(APP_NAME) $(APP_NAME).swift -framework Cocoa
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	cp $(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	cp Info.plist $(APP_BUNDLE)/Contents/

install: build
	cp -r $(APP_BUNDLE) $(INSTALL_DIR)/
	open $(INSTALL_DIR)/$(APP_BUNDLE)

autostart:
	mkdir -p $(LAUNCH_AGENTS_DIR)
	sed 's|__APP_PATH__|$(INSTALL_DIR)/$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)|' $(LAUNCH_AGENT) > $(LAUNCH_AGENTS_DIR)/$(LAUNCH_AGENT)
	launchctl load $(LAUNCH_AGENTS_DIR)/$(LAUNCH_AGENT)

uninstall:
	-pkill -f $(APP_BUNDLE)
	-launchctl unload $(LAUNCH_AGENTS_DIR)/$(LAUNCH_AGENT)
	rm -f $(LAUNCH_AGENTS_DIR)/$(LAUNCH_AGENT)
	rm -rf $(INSTALL_DIR)/$(APP_BUNDLE)

clean:
	rm -f $(APP_NAME)
	rm -rf $(APP_BUNDLE)
