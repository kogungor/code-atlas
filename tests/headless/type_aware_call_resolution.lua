local root = vim.fn.getcwd()
local sample = root .. "/playground/samples/lua_method_resolution.lua"

local atlas = require("code-atlas")
local index, err = atlas.build_project_index({ root = root })
if not index then
  error("feature21 smoke failed: " .. tostring(err))
end

local source_symbol = nil
for _, symbol in ipairs(index.by_path[sample] or {}) do
  if symbol.short_name == "calculate_with_receivers" then
    source_symbol = symbol
    break
  end
end

if not source_symbol then
  error("feature21 smoke failed: calculate_with_receivers symbol not found")
end

local resolutions = index.call_resolutions[source_symbol.id] or {}
local checkout_match = nil
local audit_match = nil

for _, item in ipairs(resolutions) do
  if item.receiver == "checkout_service" and item.call_name == "apply_discount_rules" then
    checkout_match = item
  elseif item.receiver == "audit_service" and item.call_name == "apply_discount_rules" then
    audit_match = item
  end
end

if not checkout_match or checkout_match.unresolved then
  error("feature21 smoke failed: checkout_service:apply_discount_rules should resolve")
end

if not audit_match or audit_match.unresolved then
  error("feature21 smoke failed: audit_service:apply_discount_rules should resolve")
end

if not checkout_match.best or checkout_match.best.name ~= "CheckoutService.apply_discount_rules" then
  error("feature21 smoke failed: checkout_service call should resolve to CheckoutService.apply_discount_rules")
end

if not audit_match.best or audit_match.best.name ~= "AuditService.apply_discount_rules" then
  error("feature21 smoke failed: audit_service call should resolve to AuditService.apply_discount_rules")
end

if checkout_match.best.confidence ~= "high" or audit_match.best.confidence ~= "high" then
  error("feature21 smoke failed: receiver-disambiguated method calls should have high confidence")
end

vim.cmd("edit " .. vim.fn.fnameescape(sample))
local line = vim.fn.search("^local function calculate_with_receivers", "nw")
if line == 0 then
  error("feature21 smoke failed: calculate_with_receivers line not found")
end
vim.api.nvim_win_set_cursor(0, { line, 2 })

local original_get_clients = vim.lsp.get_clients
local original_buf_request_sync = vim.lsp.buf_request_sync

local uri = vim.uri_from_fname(vim.fs.normalize(sample))
local function item(name, at_line)
  return {
    name = name,
    uri = uri,
    range = {
      start = { line = at_line, character = 0 },
      ["end"] = { line = at_line + 1, character = 0 },
    },
    selectionRange = {
      start = { line = at_line, character = 0 },
      ["end"] = { line = at_line, character = #name },
    },
  }
end

vim.lsp.get_clients = function(_)
  return {
    {
      id = 321,
      name = "mock-lua",
      offset_encoding = "utf-16",
      workspace_folders = {
        { uri = vim.uri_from_fname(vim.fs.normalize(root)) },
      },
      supports_method = function(_, method)
        return method == "textDocument/prepareCallHierarchy"
          or method == "callHierarchy/outgoingCalls"
      end,
    },
  }
end

vim.lsp.buf_request_sync = function(_, method, params, _)
  if method == "textDocument/prepareCallHierarchy" then
    return {
      [321] = {
        result = {
          item("calculate_with_receivers", line - 1),
        },
      },
    }
  end

  if method == "callHierarchy/outgoingCalls" then
    local name = params.item and params.item.name
    if name == "calculate_with_receivers" then
      return {
        [321] = {
          result = {
            { to = item("CheckoutService.apply_discount_rules", 7) },
            { to = item("AuditService.apply_discount_rules", 17) },
          },
        },
      }
    end
    return { [321] = { result = {} } }
  end

  return { [321] = { result = {} } }
end

atlas.run_project_call_graph()

vim.lsp.get_clients = original_get_clients
vim.lsp.buf_request_sync = original_buf_request_sync

local state = require("code-atlas.window").get_state()
local text = table.concat(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), "\n")
if not text:find("backend: mixed%(index%+lsp%)") then
  error("feature21 smoke failed: graph should report mixed(index+lsp) backend")
end
if not text:find("resolution_candidates:", 1, true) then
  error("feature21 smoke failed: graph output missing resolution candidate section")
end
if not text:find("mixed%(index%+lsp%)|high") then
  error("feature21 smoke failed: mixed-source confidence output missing")
end
if not text:find("CheckoutService%.apply_discount_rules") then
  error("feature21 smoke failed: graph output missing CheckoutService.apply_discount_rules")
end
if not text:find("AuditService%.apply_discount_rules") then
  error("feature21 smoke failed: graph output missing AuditService.apply_discount_rules")
end

vim.notify("feature21 smoke passed", vim.log.levels.INFO)
