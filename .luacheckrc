---@diagnostic disable: lowercase-global

std = luajit
cache = true
codes = true

-- Glorious list of warnings: https://luacheck.readthedocs.io/en/stable/warnings.html
ignore = {
	"212", -- Unused argument, In the case of callback function, _arg_name is easier to understand than _, so this option is set to off.
	"122", -- Indirectly setting a readonly global
}

read_globals = { "vim" }

files = {
	["tests"] = {
		globals = {
			"describe",
			"it",
			"pending",
			"before_each",
			"after_each",
			"clear",
			"assert",
			"print",
		},
	},
}
