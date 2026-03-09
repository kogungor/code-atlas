# Tests

This directory contains lightweight headless checks that can run without extra dependencies.

Run the current smoke test:

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/current_function_detection.lua" +qall
```

Run local call detection smoke test (Feature 3):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/local_call_detection.lua" +qall
```

Run floating ASCII graph smoke test (Feature 4):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/ascii_graph_render.lua" +qall
```

Run graph node navigation smoke test (Feature 5):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/node_navigation.lua" +qall
```

Run node expansion smoke test (Feature 6):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/expand_graph_nodes.lua" +qall
```

Run depth limit smoke test (Feature 7):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/depth_limit.lua" +qall
```

Run function-selection graph smoke test (Feature 8):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/telescope_integration.lua" +qall
```

Run project index smoke test (Feature 9):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/project_function_index.lua" +qall
```

Run project call graph smoke test (Feature 10):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/project_call_graph.lua" +qall
```

Run reverse project call graph smoke test (Feature 11):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/reverse_call_graph.lua" +qall
```

Run cross-file resolution smoke test (Feature 12):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/cross_file_call_detection.lua" +qall
```

Run module dependency graph smoke test (Feature 13):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/module_dependency_graph.lua" +qall
```

Run import graph smoke test (Feature 14):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/import_graph.lua" +qall
```

Run dead code detection smoke test (Feature 15):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/dead_code_detection.lua" +qall
```

Run impact analysis smoke test (Feature 16):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/impact_analysis.lua" +qall
```

Run interactive tree UI smoke test (Feature 17):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/interactive_tree_ui.lua" +qall
```

Run graph export smoke test (Feature 18):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/graph_export.lua" +qall
```

Run graph layout metadata smoke test (Feature 19):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/graph_layout_algorithms.lua" +qall
```

Run LSP call hierarchy smoke test (Feature 20):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/lsp_call_hierarchy.lua" +qall
```

Run type-aware call resolution smoke test (Feature 21):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/type_aware_call_resolution.lua" +qall
```

Run multi-language receiver disambiguation smoke test:

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/type_aware_call_resolution_langs.lua" +qall
```

Run polymorphism detection smoke test (Feature 22):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/polymorphism_detection.lua" +qall
```

Run knowledge graph smoke test (Feature 23):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/knowledge_graph.lua" +qall
```

Run architecture graph smoke test (Feature 24):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/architecture_graph.lua" +qall
```

Run code evolution graph smoke test (Feature 25):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/code_evolution_graph.lua" +qall
```

Run interactive graph viewer smoke test (Feature 26):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/interactive_graph_viewer.lua" +qall
```

Run hot path detection smoke test (Feature 27):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/hot_path_detection.lua" +qall
```

Run complexity analysis smoke test (Feature 28):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/complexity_analysis.lua" +qall
```

Run risk map report smoke test (Feature 29):

```bash
nvim --headless --clean -u tests/minimal_init.lua +"luafile tests/headless/risk_map_report.lua" +qall
```

As features grow, add one file per feature in `tests/headless/` and keep each check fast.
