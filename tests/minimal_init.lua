if os.getenv('TEST_COV') then
  -- start collecting coverage data
  local runner = require('luacov')
  -- flush coverage data when neovim exists
  vim.api.nvim_create_autocmd("VimLeave", {
    callback = function()
      runner.shutdown()
    end,
  })
end

vim.cmd([[
  set noswapfile
  set rtp+=.
  set rtp+=plenary.nvim
  runtime plugin/plenary.vim
]])
