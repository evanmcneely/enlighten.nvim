local M = {}

---@param str string
---@param sep string
---@return string[]
function M.split(str, sep)
	if sep == nil then
		sep = "%s"
	end
	local t = {}
	for s in string.gmatch(str, "([^" .. sep .. "]*)") do
		table.insert(t, s)
	end
	table.remove(t) -- Remove the last element, it's always an empty string
	return t
end

return M
