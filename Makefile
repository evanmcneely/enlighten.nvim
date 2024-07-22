prepare:
	git clone git@github.com:nvim-lua/plenary.nvim.git

lint:
	luacheck lua/enlighten tests/
unit:
	@echo "Running unit tests..."
	nvim --headless --noplugin  -c "PlenaryBustedDirectory tests/unit" -u "tests/minimal_init.vim"
	@echo

integration:
	@echo "Running integration tests..."
	nvim --headless --noplugin -c "PlenaryBustedDirectory tests/integration"
	@echo

test: unit integration
