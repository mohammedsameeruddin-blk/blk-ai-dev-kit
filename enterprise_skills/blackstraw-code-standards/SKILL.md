---
name: blackstraw-code-standards
description: >-
  Blackstraw Python coding standards — applies Pythonic best practices when writing,
  reviewing, or refactoring Python code for any Blackstraw project. Use when writing
  new Python code, reviewing a pull request, refactoring existing code, or setting up
  a new Python project. Triggers on "write python", "code review", "refactor",
  "python standards", "code quality", "review this code", "follow our standards",
  "blackstraw coding style". Do NOT use for non-Python languages.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# Blackstraw Python Code Standards

## Purpose

Ensures all Python code written or reviewed in Blackstraw projects follows
a consistent, idiomatic, and maintainable style. Applies PEP 8, PEP 484 (type hints),
and modern Pythonic patterns. The goal is code that is readable to any engineer on
the team without explanation.

## When to Use

**Use this skill when:**
- Writing new Python modules, classes, or functions
- Reviewing Python code for a pull request
- Refactoring existing Python code
- Setting up a new Python project scaffold

**Do NOT use this skill when:**
- Working with Jupyter notebooks — use the `python-dev` skill instead
- The file is a config file (`.toml`, `.yaml`, `.cfg`) — no Python standards apply
- The task is SQL, shell scripts, or Terraform

---

## Hard Rules

These are non-negotiable. Claude must enforce them on every piece of Python code.

- **ALWAYS** add type annotations to every function signature and class attribute
- **ALWAYS** use `dataclasses` or `TypedDict` for structured data — never bare `dict`
- **ALWAYS** raise specific exception types — never bare `raise Exception("msg")`
- **NEVER** use `except:` or `except Exception:` without re-raising or logging
- **NEVER** use mutable default arguments (`def f(x=[])`) — use `None` sentinel
- **NEVER** use `*` wildcard imports (`from module import *`)
- **PREFER** composition over inheritance — a class with one `__init__` calling `super()` in a 5-level hierarchy is a red flag
- **PREFER** `pathlib.Path` over `os.path` for all filesystem operations
- **PREFER** `Enum` over bare string constants for categorical values

---

## Naming Conventions

Follow PEP 8 strictly. No exceptions.

| Thing | Convention | Example |
|---|---|---|
| Variables / functions | `snake_case` | `user_id`, `get_config()` |
| Classes | `PascalCase` | `PipelineConfig`, `DataLoader` |
| Constants | `UPPER_SNAKE` | `MAX_RETRIES`, `DEFAULT_TIMEOUT` |
| Private members | `_single_underscore` | `_cache`, `_validate()` |
| Dunder methods | `__double_underscore__` | `__init__`, `__repr__` |
| Type aliases | `PascalCase` | `UserId = str`, `RecordList = list[dict]` |
| Modules / packages | `lowercase` (no hyphens) | `data_loader.py`, `utils/` |

---

## Type Annotations

**Required on all public functions, class attributes, and module-level variables.**

```python
# Good — explicit, self-documenting
def fetch_records(
    table_name: str,
    limit: int = 100,
    filters: dict[str, str] | None = None,
) -> list[dict[str, object]]:
    ...

# Bad — no hints, caller must read implementation
def fetch_records(table_name, limit=100, filters=None):
    ...
```

Use `from __future__ import annotations` at the top of every file — it enables
forward references and defers annotation evaluation (required for self-referential types).

**Key annotation patterns:**
- Optional values: `str | None` (Python 3.10+) — not `Optional[str]`
- Collections: `list[str]`, `dict[str, int]` — not `List[str]`, `Dict[str, int]`
- Callables: `Callable[[int, str], bool]`
- Structural interfaces: `Protocol` (see `references/pythonic-patterns.md`)
- Unknown/dynamic: `Any` — use sparingly, document why

For detailed type annotation patterns, read `references/pythonic-patterns.md` → **Type Annotations** section.

---

## Data Modeling

Use the right tool for structured data:

| Use case | Tool |
|---|---|
| Immutable config / value object | `@dataclass(frozen=True)` |
| Mutable data container with validation | `@dataclass` |
| Dict-shaped data passed to/from APIs | `TypedDict` |
| Rows from a database result | `NamedTuple` |
| Categorical options / status values | `Enum` |
| External data with validation | `pydantic.BaseModel` |

```python
from dataclasses import dataclass, field
from enum import Enum

class PipelineStatus(Enum):
    PENDING = "pending"
    RUNNING = "running"
    FAILED  = "failed"
    SUCCESS = "success"

@dataclass(frozen=True)
class PipelineConfig:
    name: str
    catalog: str
    schema: str
    max_retries: int = 3
    tags: frozenset[str] = field(default_factory=frozenset)
```

---

## Function Design

**Single responsibility:** one function does one thing. If the function name
contains "and", split it.

**Guard clauses over nesting:** validate inputs and return/raise early.
The happy path should be the last thing in the function, at the lowest indent level.

```python
# Good — guard clauses, flat structure
def process_record(record: dict[str, object], schema: str) -> str:
    if not record:
        raise ValueError("record cannot be empty")
    if schema not in ALLOWED_SCHEMAS:
        raise ValueError(f"unknown schema: {schema!r}")

    # happy path at the bottom, unindented
    return _transform(record, schema)

# Bad — pyramid of doom
def process_record(record, schema):
    if record:
        if schema in ALLOWED_SCHEMAS:
            result = _transform(record, schema)
            return result
```

**Pure functions where possible:** functions that take inputs and return outputs
without touching global state are easier to test and reason about.

**Max function length:** aim for under 30 lines. If longer, extract helpers.

---

## Class Design

Prefer **composition** over inheritance. Use `Protocol` for structural interfaces
instead of abstract base classes unless shared implementation is truly needed.

```python
from typing import Protocol, runtime_checkable

@runtime_checkable
class Loader(Protocol):
    def load(self, path: str) -> list[dict]: ...
    def validate(self, records: list[dict]) -> bool: ...

# Any class with .load() and .validate() satisfies Loader — no inheritance required
class CsvLoader:
    def load(self, path: str) -> list[dict]: ...
    def validate(self, records: list[dict]) -> bool: ...
```

Use `__slots__` on data-heavy classes to reduce memory overhead.

---

## Error Handling

**Build a shallow exception hierarchy** for the module/package. Every custom
exception descends from a single base.

```python
class BlackstrawError(Exception):
    """Base for all Blackstraw exceptions."""

class ConfigError(BlackstrawError):
    """Invalid or missing configuration."""

class PipelineError(BlackstrawError):
    """Pipeline execution failure."""
    def __init__(self, message: str, pipeline_name: str) -> None:
        super().__init__(message)
        self.pipeline_name = pipeline_name
```

**Chain exceptions with `raise ... from`** to preserve original context:

```python
try:
    result = external_api.call()
except requests.HTTPError as exc:
    raise PipelineError("API call failed", pipeline_name=name) from exc
```

**Catch specific, handle specifically:**

```python
# Good
try:
    config = load_config(path)
except FileNotFoundError:
    logger.warning("Config not found at %s, using defaults", path)
    config = DEFAULT_CONFIG

# Bad — swallows everything
try:
    config = load_config(path)
except Exception:
    config = DEFAULT_CONFIG
```

---

## Collections and Iteration

**Comprehensions for simple transforms** — list, dict, set, generator.
**Loops for complex logic** — more than one condition or side effect: use a for loop.

```python
# Good — clear intent
active_ids = [r["id"] for r in records if r["status"] == "active"]
lookup     = {r["id"]: r for r in records}

# Good — generator for large data (lazy, memory-efficient)
def iter_batches(records: list[dict], size: int):
    for i in range(0, len(records), size):
        yield records[i : i + size]

# Bad — comprehension with nested logic is unreadable
result = [transform(r) if r["x"] else fallback(r) for r in records if r and r.get("y")]
```

Use `itertools` for chaining, slicing, and grouping iterables — don't re-implement
standard combinators.

---

## Constants and Configuration

Use `Enum` for categorical constants. Use `Final` for true constants.

```python
from typing import Final
from enum import Enum

MAX_BATCH_SIZE: Final = 1000

class Environment(str, Enum):
    DEV     = "dev"
    STAGING = "staging"
    PROD    = "prod"
```

Inheriting from `str` (or `int`) makes the Enum directly usable as a string
value — no `.value` access needed in most contexts.

---

## Module Structure

Every Python module follows this order:

```python
"""Module docstring — one line summary, then blank line, then detail if needed."""
from __future__ import annotations

# 1. stdlib imports
import os
import sys
from pathlib import Path

# 2. third-party imports
import pydantic
import requests

# 3. first-party imports
from blackstraw.core import config
from blackstraw.utils import logging

# 4. type-checking-only imports (never executed at runtime)
from typing import TYPE_CHECKING
if TYPE_CHECKING:
    from blackstraw.pipeline import Pipeline

# 5. module-level constants
DEFAULT_TIMEOUT: Final = 30

# 6. public API declaration
__all__ = ["PublicClass", "public_function"]
```

---

## Testing

- **Framework:** `pytest` only — no `unittest`
- **Location:** `tests/` at project root, mirroring `src/` structure
- **Coverage:** every public function and class needs at least one test
- **Fixtures:** use `@pytest.fixture` for setup, not `setUp/tearDown`
- **Parametrize:** use `@pytest.mark.parametrize` for multiple input variations
- **Naming:** `test_<function>_<scenario>` — e.g. `test_fetch_records_empty_table`

```python
import pytest
from mymodule import process_record

@pytest.mark.parametrize("record,schema,expected", [
    ({"id": 1}, "bronze", "bronze_1"),
    ({"id": 2}, "silver", "silver_2"),
])
def test_process_record_valid(record, schema, expected):
    assert process_record(record, schema) == expected

def test_process_record_empty_raises():
    with pytest.raises(ValueError, match="cannot be empty"):
        process_record({}, "bronze")
```

---

## Workflow: Applying Standards to Existing Code

When asked to review or refactor existing Python code:

### Step 1: Read and categorise issues

Scan the file for violations in this order:
1. Missing type annotations (highest priority)
2. Mutable default arguments
3. Bare `except:` blocks
4. Wildcard imports
5. Long functions (>30 lines)
6. Bare `dict`/`list` used as structured data (candidate for `dataclass`/`TypedDict`)

### Step 2: Fix hard rule violations first

Address the Hard Rules list above before stylistic improvements.

### Step 3: Apply naming and structure

- Rename symbols that violate conventions
- Reorder imports to match the module structure section above
- Extract helper functions from long functions

### Step 4: Run tooling

```bash
uv run ruff check --fix .   # lint + auto-fix
uv run ruff format .        # format
uv run pyright              # type check
uv run pytest               # verify tests still pass
```

See `references/tooling.md` for ruff/pyright/uv configuration.

---

## References

- **pythonic-patterns.md** — deep-dive code examples: Protocol, TypeVar, generators, context managers, async patterns
- **tooling.md** — `pyproject.toml` config for ruff, pyright, uv; pre-commit setup
