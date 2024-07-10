vim.api.nvim_create_user_command("AI", function(args)
	require("enlighten/commands").ai(args)
end, {
	range = true,
	nargs = "*",
})
