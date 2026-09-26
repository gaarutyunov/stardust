build: ## Compile for MacOS
	@nasm -f macho64 hello.s
	@ld hello.o -macos_version_min 13.7 -o hello -L /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/lib -lSystem -no_pie

run: build ## Run the compiled program
	./hello

help: ## Prints help for targets with comments
	@cat $(MAKEFILE_LIST) | grep -E '^[a-zA-Z_-]+:.*?## .*$$' | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
