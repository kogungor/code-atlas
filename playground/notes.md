# Playground Notes

Track behavior while implementing each feature.

## Feature 1

- `:CodeAtlas` command is available in clean startup via `playground/minimal_init.lua`.
- Current output: info notification confirming Feature 1 readiness.

## Feature 2

- Put cursor inside a function and run `:CodeAtlas`.
- Expected output: function name, language, and range from Tree-sitter detection.

## Feature 3

- `:CodeAtlas` now also prints local calls detected inside the current function.
- In `M.run`, expected local call list includes `greet`.

## Feature 4

- `:CodeAtlas` now opens a centered floating window.
- Expected graph shows root function and local calls as ASCII tree.
- Press `q` or `<Esc>` to close the window.

## Feature 5

- Place cursor on a graph node line and press `<CR>` or `o`.
- Expected behavior: jump back to source window and move cursor to definition.

## Feature 6

- Press `l` on a node (for example `greet`) to expand deeper local calls.
- Press `h` to collapse the node again.

## Feature 7

- `depth_limit` controls how deep traversal can render.
- Example: with `depth_limit = 1`, `run -> greet` is shown but `format_name` stays hidden.

## Feature 8

- `:CodeAtlasPick` opens Telescope picker (if Telescope is installed).
- Select a function to open its call graph without moving cursor manually.

## Feature 9

- `:CodeAtlasIndex` builds a project-wide symbol index.
- `:CodeAtlasIndexRefresh` refreshes that index manually.

## Feature 10

- `:CodeAtlasProjectGraph` uses project index to render cross-file call graph.
- Put cursor on `M.checkout` in `checkout_flow.lua` and inspect deeper nodes.

## Feature 11

- `:CodeAtlasProjectReverseGraph` shows incoming callers for function under cursor.
- Useful for impact analysis before refactor/remove.

## Feature 12

- Cross-file call resolution now keeps scored candidates and best match.
- Project graph includes unresolved call summary for quick quality signal.

## Feature 13

- `:CodeAtlasModuleGraph` shows module-level dependencies.
- `:CodeAtlasPackageGraph` shows package-level dependencies.
- Dependency view includes summary node/edge stats.

## Feature 14

- `:CodeAtlasImportGraph` shows file-level import dependencies.
- `:CodeAtlasImportReverseGraph` shows which files depend on current file.

## Feature 15

- `:CodeAtlasDeadCode` reports functions with zero incoming calls.
- Ignore rules keep tests/playground and common entrypoints out of default report.

## Feature 16

- `:CodeAtlasImpact` reports direct and transitive callers for function under cursor.
- Includes impacted modules/packages and test hints.

## Feature 17

- Interactive tree UI now supports `h/l`, `<Tab>`, `q`, `r`.
- `:CodeAtlasUI ascii` provides fallback non-tree rendering.

## Playground Scenario

- `playground/samples/checkout_flow.lua` provides a realistic function graph.
- Start from `M.checkout` and use `l` to inspect deeper branches.
