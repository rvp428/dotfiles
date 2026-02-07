-- lua/repo/localconfig.lua
vim.api.nvim_create_autocmd("SourcePre", {
  callback = function(args)
    if args.file:match("%.nvim%.lua$") then
      vim.notify("Sourcing local config: " .. args.file, vim.log.levels.DEBUG)
    end
  end,
})

