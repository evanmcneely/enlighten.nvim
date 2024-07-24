prepare:
	git clone git@github.com:nvim-lua/plenary.nvim.git
	git config blame.ignoreRevsFile .git-blame-ignore-revs
	echo "You will also need to install stylua and luacheck"

lint:
	luacheck lua/enlighten tests/

fmt:
	stylua lua/enlighten tests/ --config-path=.stylua.toml

unit:
	nvim --headless --noplugin  -c "PlenaryBustedDirectory tests/unit" -u "tests/minimal_init.vim"

integration:
	nvim --headless --noplugin -c "PlenaryBustedDirectory tests/integration" -u "tests/minimal_init.vim"

test: unit integration
