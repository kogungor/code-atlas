# Playground Notes

Track behavior while implementing each feature.

## Command bootstrap

- `:CodeAtlas` command is available in clean startup via `playground/minimal_init.lua`.
- Current output: info notification confirming bootstrap readiness.

## Current function detection

- Put cursor inside a function and run `:CodeAtlas`.
- Expected output: function name, language, and range from Tree-sitter detection.

## Local call detection

- `:CodeAtlas` now also prints local calls detected inside the current function.
- In `M.run`, expected local call list includes `greet`.

## ASCII graph render

- `:CodeAtlas` now opens a centered floating window.
- Expected graph shows root function and local calls as ASCII tree.
- Press `q` or `<Esc>` to close the window.

## Node navigation

- Place cursor on a graph node line and press `<CR>` or `o`.
- Expected behavior: jump back to source window and move cursor to definition.

## Expand graph nodes

- Press `l` on a node (for example `greet`) to expand deeper local calls.
- Press `h` to collapse the node again.

## Depth limit

- `depth_limit` controls how deep traversal can render.
- Example: with `depth_limit = 1`, `run -> greet` is shown but `format_name` stays hidden.

## Telescope integration

- `:CodeAtlasPick` opens Telescope picker (if Telescope is installed).
- Select a function to open its call graph without moving cursor manually.

## Project function index

- `:CodeAtlasIndex` builds a project-wide symbol index.
- `:CodeAtlasIndexRefresh` refreshes that index manually.

## Project call graph

- `:CodeAtlasProjectGraph` uses project index to render cross-file call graph.
- Put cursor on `M.checkout` in `checkout_flow.lua` and inspect deeper nodes.

## Reverse call graph

- `:CodeAtlasProjectReverseGraph` shows incoming callers for function under cursor.
- Useful for impact analysis before refactor/remove.

## Cross-file call detection

- Cross-file call resolution now keeps scored candidates and best match.
- Project graph includes unresolved call summary for quick quality signal.

## Module dependency graph

- `:CodeAtlasModuleGraph` shows module-level dependencies.
- `:CodeAtlasPackageGraph` shows package-level dependencies.
- Dependency view includes summary node/edge stats.

## Import graph

- `:CodeAtlasImportGraph` shows file-level import dependencies.
- `:CodeAtlasImportReverseGraph` shows which files depend on current file.

## Dead code detection

- `:CodeAtlasDeadCode` reports functions with zero incoming calls.
- Ignore rules keep tests/playground and common entrypoints out of default report.

## Impact analysis

- `:CodeAtlasImpact` reports direct and transitive callers for function under cursor.
- Includes impacted modules/packages and test hints.

## Interactive tree UI

- Interactive tree UI now supports `h/l`, `<Tab>`, `q`, `r`.
- `:CodeAtlasUI ascii` provides fallback non-tree rendering.

## Graph export

- `:CodeAtlasExport` exports graph snapshots as `json`, `graphviz`, or `mermaid`.

## Graph layout algorithms

- Layout metadata supports hierarchical and force-directed modes.

## LSP call hierarchy

- `:CodeAtlasLSPGraph` and `:CodeAtlasLSPReverseGraph` should work when LSP supports call hierarchy.

## Type-aware call resolution

- Receiver-aware scoring should improve method-target disambiguation.

## Polymorphism detection

- Dynamic callsites can fan out to multiple candidate targets.

## Knowledge graph

- `:CodeAtlasKnowledge` shows schema summary and can export snapshot files.

## Architecture graph

- `:CodeAtlasArchitecture` reports layer/domain dependencies and violations.

## Code evolution graph

- `:CodeAtlasEvolution` reports timeline and churn hotspots from git history.

## Interactive graph viewer

- `:CodeAtlasViewer` supports focus/filter/search plus zoom and pan-like navigation.

## Hot path detection

- `:CodeAtlasHotPath` ranks critical symbols and call chains.

## Complexity analysis

- `:CodeAtlasComplexity` reports SCC/cycle complexity and cluster metrics.

## Risk map report

- `:CodeAtlasRiskMap` combines architecture, centrality, complexity, and churn signals.

## Playground Scenario

- `playground/samples/checkout_flow.lua` provides a realistic function graph.
- Start from `M.checkout` and use `l` to inspect deeper branches.
