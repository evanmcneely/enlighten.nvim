prepare:
	git clone git@github.com:nvim-lua/plenary.nvim.git
	git config blame.ignoreRevsFile .git-blame-ignore-revs

lint:
	luacheck lua/enlighten tests/

fmt:
	stylua lua/enlighten tests/ --config-path=.stylua.toml

unit:
	echo "Running unit tests..."
	nvim --headless --noplugin  -c "PlenaryBustedDirectory tests/unit" -u "tests/minimal_init.vim"

integration:
	echo "Running integration tests..."
	nvim --headless --noplugin -c "PlenaryBustedDirectory tests/integration"

test: unit integration
