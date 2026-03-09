# Contributing

Thanks for contributing to `code-atlas`.

## Branching Model

- Default branch on GitHub: `dev`
- Feature work: `feature/<short-name>`
- Bug fixes: `bugfix/<short-name>`

## Pull Request Flow

1. Branch from `dev`.
2. Implement changes and run relevant headless tests from `tests/README.md`.
3. Open a PR targeting `dev`.
4. After review and validation, merge into `dev`.
5. Release promotion happens via a separate PR from `dev` to `main`.

## Quality Checklist

- Keep existing commands backward compatible where possible.
- Update docs when behavior or command options change:
  - `README.md`
  - `doc/code-atlas.txt`
  - `tests/README.md`
- Add or update a headless smoke test in `tests/headless/` for new features.

## Commit Guidance

- Keep commits focused and scoped.
- Prefer descriptive commit messages that explain the intent.
