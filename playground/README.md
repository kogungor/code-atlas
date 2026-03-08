# code-atlas playground

Use this folder to test each feature incrementally in a clean Neovim session.

## Quick start

From the repository root:

```bash
nvim --clean -u playground/minimal_init.lua playground/samples/lua_sample.lua
```

Then run:

```vim
:CodeAtlas
```

Make sure the cursor is inside a function to test Feature 2 detection.

## Extended use-case sample

For a richer graph (checkout flow), open:

```bash
nvim --clean -u playground/minimal_init.lua playground/samples/checkout_flow.lua
```

Suggested cursor positions for testing:

- `M.checkout` for top-level orchestration
- `calculate_total` for pricing chain
- `charge_payment` for payment chain

## TypeScript sample for LSP graph tests

To test call hierarchy with `ts_ls`, open:

```bash
nvim --clean -u playground/minimal_init.lua playground/samples/ts_checkout_flow.ts
```

Suggested cursor positions:

- `checkout` for full orchestration
- `calculateTotal` for pricing chain
- `applyDiscountRules` for coupon/VIP path

For receiver/type-aware call resolution testing, open:

```bash
nvim --clean -u playground/minimal_init.lua playground/samples/lua_method_resolution.lua
```

Suggested cursor position:

- `calculate_with_receivers` to verify method disambiguation across services

Additional language samples for receiver disambiguation:

```bash
nvim --clean -u playground/minimal_init.lua playground/samples/py_method_resolution.py
nvim --clean -u playground/minimal_init.lua playground/samples/go_method_resolution.go
nvim --clean -u playground/minimal_init.lua playground/samples/rust_method_resolution.rs
```

For polymorphic callsite behavior testing, open:

```bash
nvim --clean -u playground/minimal_init.lua playground/samples/lua_polymorphic.lua
```

Suggested cursor position:

- `calculate_dynamic` to see one callsite fan out to multiple targets

To preview the unified knowledge graph summary and write a snapshot:

```vim
:CodeAtlasKnowledge
:CodeAtlasKnowledge path=/tmp/code-atlas-knowledge.json
:CodeAtlasKnowledge path=/tmp/code-atlas-knowledge.jsonl format=jsonl include_tests=false
```

## Workflow for each new feature

1. Add or update a sample file in `playground/samples/`.
2. Open Neovim with `minimal_init.lua`.
3. Run the command(s) introduced by the feature.
4. Capture any regressions in `playground/notes.md`.
