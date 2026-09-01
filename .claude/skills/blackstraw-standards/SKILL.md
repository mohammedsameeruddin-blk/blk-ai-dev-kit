---
name: blackstraw-standards
description: "Blackstraw internal coding standards and project conventions. Use when creating new Blackstraw projects, writing code for internal repos, reviewing PRs, or setting up project structure."
---

# Blackstraw Coding Standards

Internal standards for all Blackstraw engineering projects. Apply alongside the `python-dev` skill for Python work.

---

## Project Structure

All Blackstraw Python projects follow this layout:

```
{project-name}/
├── src/
│   └── {package_name}/       # Main source package
│       ├── __init__.py
│       └── ...
├── tests/
│   ├── __init__.py
│   ├── unit/
│   └── integration/
├── notebooks/                 # Exploratory / demo notebooks only
├── scripts/                   # One-off operational scripts
├── docs/                      # Architecture decisions, runbooks
├── pyproject.toml
├── .env.example               # Template — never commit .env
└── README.md
```

> # TODO: Add or remove top-level directories to match Blackstraw's actual standard layout.

---

## Naming Conventions

### Python
- Modules and packages: `snake_case`
- Classes: `PascalCase`
- Functions and variables: `snake_case`
- Constants: `UPPER_SNAKE_CASE`
- Private members: `_leading_underscore`

### Files & Directories
- Python source files: `snake_case.py`
- Notebooks: `{YYYYMMDD}_{author_initials}_{short_description}.ipynb`
  - Example: `20240915_js_explore_customer_churn.ipynb`
- Config files: `kebab-case.yaml` / `kebab-case.json`

> # TODO: Confirm Blackstraw's notebook naming convention and author initials policy.

### Databricks Resources
- Jobs: `{team}-{project}-{purpose}` — e.g., `data-pipeline-daily-ingest`
- Clusters: `{env}-{team}-{purpose}` — e.g., `dev-ml-feature-eng`
- See `blackstraw-databricks` skill for full resource naming.

---

## Approved Libraries

### Always use
| Purpose | Library |
|---------|---------|
| HTTP clients | `httpx` (async-native) |
| Data validation | `pydantic` |
| Config management | `pydantic-settings` |
| Logging | `structlog` |
| CLI tools | `typer` |
| Environment / packaging | `uv` |

### Banned / replaced
| Banned | Use instead |
|--------|------------|
| `requests` | `httpx` |
| `argparse` / `click` | `typer` |
| `logging` (stdlib) | `structlog` |
| `pip` / `venv` / `conda` | `uv` |

> # TODO: Add Blackstraw-approved data libraries (pandas vs polars, etc.) and any internal packages.

---

## Git & Branching

### Branch naming
```
feature/{ticket-id}-short-description
fix/{ticket-id}-short-description
chore/short-description
release/v{semver}
```

> # TODO: Confirm ticket prefix format (e.g., BLK-123, JIRA key, GitHub issue #).

### Commit message format
```
{type}({scope}): {short summary}

{optional body — why, not what}
```

Types: `feat`, `fix`, `chore`, `refactor`, `test`, `docs`, `ci`

Example:
```
feat(ingestion): add incremental load support for customer events

Switched from full-refresh to watermark-based incremental to reduce
daily warehouse compute cost by ~60%.
```

### PR requirements
- Title follows commit format
- All CI checks must pass before merge
- Minimum 1 approving review
- Squash merge to `main`

> # TODO: Set actual merge strategy (squash vs rebase) and minimum reviewer count.

---

## Documentation

- **README.md**: Every repo must have one. Include: purpose, quickstart, environment setup, known limitations.
- **ADRs**: Architecture Decision Records go in `docs/adr/` using [MADR format](https://adr.github.io/madr/).
- **Docstrings**: Google-style, required on all public functions and classes. See `python-dev` skill.
- **Notebooks**: First cell must be a markdown cell with purpose, author, and date.

---

## Environment & Secrets

- Use `.env.example` to document required variables — never commit actual values
- Load config via `pydantic-settings` — not raw `os.getenv()`
- Databricks secrets take precedence over env vars in production
- See `blackstraw-security` skill for full credential handling rules

---

## Code Review Checklist

Before requesting review, verify:
- [ ] Type hints on all public functions
- [ ] Tests written and passing (`uv run pytest`)
- [ ] Ruff lint clean (`uv run ruff check .`)
- [ ] No hardcoded secrets or hostnames
- [ ] README updated if behaviour changed
- [ ] No commented-out dead code committed

---

## Related Skills

- **[python-dev](../python-dev/SKILL.md)** — Python code quality, testing, environment management
- **[blackstraw-databricks](../blackstraw-databricks/SKILL.md)** — Databricks resource naming and conventions
- **[blackstraw-security](../blackstraw-security/SKILL.md)** — Credential and PII handling rules
- **[blackstraw-ai](../blackstraw-ai/SKILL.md)** — ML/AI development and MLOps standards
