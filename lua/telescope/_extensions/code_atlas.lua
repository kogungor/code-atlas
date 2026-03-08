local function functions_picker(opts)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  opts = opts or {}

  local entries, err = require("code-atlas.picker").function_entries(vim.api.nvim_get_current_buf())
  if not entries then
    vim.notify("code-atlas: " .. tostring(err), vim.log.levels.WARN)
    return
  end

  pickers.new(opts, {
    prompt_title = "CodeAtlas Functions",
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        return {
          value = entry,
          ordinal = entry.name,
          display = string.format("%s [%s]", entry.name, entry.lang),
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if not selection or not selection.value then
          return
        end
        require("code-atlas").run_for_function_name(selection.value.name, selection.value.bufnr)
      end)
      return true
    end,
  }):find()
end

return require("telescope").register_extension({
  exports = {
    functions = functions_picker,
  },
})
