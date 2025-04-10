prepare:
	git clone git@github.com:nvim-lua/plenary.nvim.git
	git config blame.ignoreRevsFile .git-blame-ignore-revs
	echo "You will also need to install stylua, luacheck, luacov and luacov-console"

lint:
	luacheck lua/ tests/

fmt:
	stylua lua/ tests/ --config-path=.stylua.toml --glob '!lua/enlighten/spinner.lua'

test:
	bash ./scripts/test_runner.sh

testcov:
	export TEST_COV=true && \
	bash ./scripts/test_runner.sh
	@luacov-console lua
	@luacov-console -s
