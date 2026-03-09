local root = vim.fn.getcwd()

if vim.fn.exists(":CodeAtlasKnowledge") ~= 2 then
  error("feature23 smoke failed: :CodeAtlasKnowledge command is not registered")
end

local atlas = require("code-atlas")
atlas.setup({
  depth_limit = 2,
})

local index, err = atlas.build_project_index({ root = root })
if not index then
  error("feature23 smoke failed: index build failed: " .. tostring(err))
end

local snapshot_path = vim.fn.tempname() .. ".json"
local graph, graph_err = atlas.run_knowledge_graph({
  snapshot_path = snapshot_path,
  snapshot_format = "jsonl",
  include_tests = true,
  include_imports = true,
  include_types = true,
})
if not graph then
  error("feature23 smoke failed: knowledge graph failed: " .. tostring(graph_err))
end

if graph.schema_version ~= "knowledge_graph.v1" then
  error("feature23 smoke failed: unexpected schema version")
end

if not graph.counts or (graph.counts.total_nodes or 0) == 0 then
  error("feature23 smoke failed: expected non-empty node set")
end

if not graph.counts or (graph.counts.total_edges or 0) == 0 then
  error("feature23 smoke failed: expected non-empty edge set")
end

if not graph.validation or graph.validation.ok ~= true then
  error("feature23 smoke failed: validation should succeed")
end

if (graph.counts.type_nodes or 0) == 0 then
  error("feature23 smoke failed: expected type nodes in sample-rich index")
end

local state = require("code-atlas.window").get_state()
if not state.win or not vim.api.nvim_win_is_valid(state.win) then
  error("feature23 smoke failed: knowledge window was not created")
end

local text = table.concat(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), "\n")
if not text:find("code%-atlas knowledge graph") then
  error("feature23 smoke failed: summary title missing")
end
if not text:find("node_types:", 1, true) then
  error("feature23 smoke failed: node type summary missing")
end
if not text:find("edge_types:", 1, true) then
  error("feature23 smoke failed: edge type summary missing")
end
if not text:find("validation: true", 1, true) then
  error("feature23 smoke failed: validation summary missing")
end

local json_text = table.concat(vim.fn.readfile(snapshot_path), "\n")
if not json_text:find('"record_type":"meta"', 1, true) then
  error("feature23 smoke failed: jsonl snapshot missing meta record")
end
if not json_text:find('"record_type":"node"', 1, true) then
  error("feature23 smoke failed: jsonl snapshot missing node records")
end
if not json_text:find('"record_type":"edge"', 1, true) then
  error("feature23 smoke failed: jsonl snapshot missing edge records")
end

vim.notify("feature23 smoke passed", vim.log.levels.INFO)
