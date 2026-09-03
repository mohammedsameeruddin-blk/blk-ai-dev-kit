# Tooling Reference

Standard tooling configuration for all Blackstraw Python projects.
All commands use `uv run` — never call `python`, `pip`, or `pytest` directly.

---

## Package Management: uv

`uv` is the only package manager. No `pip`, no `conda`, no `venv`.

```bash
# Set up a new project
uv init my-project
cd my-project

# Add a dependency
uv add requests

# Add a dev-only dependency
uv add --dev pytest ruff pyright

# Install all dependencies from pyproject.toml
uv sync

# Install including dev dependencies
uv sync --all-extras

# Run a script (no activation needed)
uv run python my_script.py

# Run a tool
uv run pytest
uv run ruff check .
uv run pyright
```

---

## pyproject.toml — Standard Blackstraw Config

```toml
[project]
name = "my-blackstraw-project"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = []

[project.optional-dependencies]
dev = [
    "pytest>=8.0",
    "pytest-cov>=5.0",
    "ruff>=0.6",
    "pyright>=1.1.380",
]

# ── Ruff ──────────────────────────────────────────────────────────────────────
[tool.ruff]
target-version = "py311"
line-length    = 100

[tool.ruff.lint]
select = [
    "E",   # pycodestyle errors
    "W",   # pycodestyle warnings
    "F",   # pyflakes
    "I",   # isort
    "B",   # flake8-bugbear
    "C4",  # flake8-comprehensions
    "UP",  # pyupgrade
    "RUF", # ruff-specific rules
    "N",   # pep8-naming
    "SIM", # flake8-simplify
    "TCH", # flake8-type-checking
]
ignore = [
    "E501",  # line too long — handled by formatter
    "B008",  # do not perform function calls in default arguments (false positives)
]

[tool.ruff.lint.isort]
known-first-party = ["blackstraw"]

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
docstring-code-format = true

# ── Pyright ───────────────────────────────────────────────────────────────────
[tool.pyright]
pythonVersion              = "3.11"
typeCheckingMode           = "standard"
reportMissingTypeStubs     = false
reportUnknownMemberType    = false   # too noisy with third-party libs
reportUnknownVariableType  = false

# ── Pytest ────────────────────────────────────────────────────────────────────
[tool.pytest.ini_options]
testpaths    = ["tests"]
addopts      = "-v --tb=short --strict-markers"
markers      = [
    "integration: requires external services",
    "slow: takes >5 seconds",
]

[tool.coverage.run]
source   = ["src"]
omit     = ["tests/*", "**/__init__.py"]

[tool.coverage.report]
fail_under = 80
```

---

## Running the Toolchain

Run these in order before committing:

```bash
# 1. Lint and auto-fix what can be fixed
uv run ruff check --fix .

# 2. Format
uv run ruff format .

# 3. Type check
uv run pyright

# 4. Tests with coverage
uv run pytest --cov --cov-report=term-missing
```

A clean run looks like:
```
ruff check: All checks passed.
ruff format: 0 files reformatted.
pyright: 0 errors, 0 warnings, 0 informations
pytest: N passed in X.XXs
coverage: 82%
```

---

## Pre-commit (Optional but Recommended)

Add `.pre-commit-config.yaml` to the project root to run checks automatically on commit:

```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.6.9
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format

  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-merge-conflict
```

Install:
```bash
uv add --dev pre-commit
uv run pre-commit install
```

---

## CI Snippet (GitHub Actions)

```yaml
- name: Set up uv
  uses: astral-sh/setup-uv@v3

- name: Install dependencies
  run: uv sync --all-extras

- name: Lint
  run: uv run ruff check .

- name: Format check
  run: uv run ruff format --check .

- name: Type check
  run: uv run pyright

- name: Tests
  run: uv run pytest --cov --cov-report=xml
```

---

## Common Ruff Rule Violations and Fixes

| Rule | Message | Fix |
|---|---|---|
| `B006` | Mutable default argument | Use `None` sentinel + `if x is None: x = []` |
| `UP007` | Use `X \| Y` for union type | Replace `Optional[X]` → `X \| None` |
| `UP006` | Use `list` instead of `List` | Replace `List[X]` → `list[X]` |
| `TCH001` | Move import to `TYPE_CHECKING` block | Wrap in `if TYPE_CHECKING:` |
| `SIM108` | Use ternary operator | `x = a if cond else b` |
| `RUF012` | Mutable class attribute default | Use `field(default_factory=...)` |
| `N806` | Variable in function should be lowercase | Rename to `snake_case` |
