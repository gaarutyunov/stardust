build: ## Build and sign executable with entitlements
	@zig build
	@codesign --entitlements ./entitlements.plist --force -s - zig-out/bin/sdctl

run: build ## Run the executable
	./zig-out/bin/sdctl

help: ## Prints help for targets with comments
	@cat $(MAKEFILE_LIST) | grep -E '^[a-zA-Z_-]+:.*?## .*$$' | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
