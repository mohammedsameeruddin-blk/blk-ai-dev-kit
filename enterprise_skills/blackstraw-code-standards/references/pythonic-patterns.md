# Pythonic Patterns Reference

Deep-dive code examples for patterns referenced in `SKILL.md`.
Load this file when you need concrete examples to apply or explain a pattern.

---

## Type Annotations

### TypeVar and Generic classes

```python
from typing import TypeVar, Generic

T = TypeVar("T")

class Repository(Generic[T]):
    def __init__(self) -> None:
        self._store: dict[str, T] = {}

    def save(self, key: str, value: T) -> None:
        self._store[key] = value

    def get(self, key: str) -> T | None:
        return self._store.get(key)

# Usage — type-safe, IDE understands T = str here
repo: Repository[str] = Repository()
repo.save("key", "value")       # fine
repo.save("key", 123)           # type error caught by pyright
```

### Protocol for structural interfaces

```python
from typing import Protocol, runtime_checkable

@runtime_checkable
class Exportable(Protocol):
    def to_dict(self) -> dict[str, object]: ...
    def to_json(self) -> str: ...

# Any class with these methods satisfies Exportable — no inheritance
class PipelineResult:
    def to_dict(self) -> dict[str, object]:
        return {"status": "ok"}

    def to_json(self) -> str:
        import json
        return json.dumps(self.to_dict())

def export(obj: Exportable) -> None:
    print(obj.to_json())

export(PipelineResult())   # works — structural match
```

### TypedDict for dict-shaped data

```python
from typing import TypedDict, NotRequired

class RecordSchema(TypedDict):
    id: str
    name: str
    status: str
    metadata: NotRequired[dict[str, str]]   # optional key

def process(record: RecordSchema) -> str:
    return f"{record['id']}:{record['name']}"
```

### Overload for multiple return types

```python
from typing import overload

@overload
def parse(value: str) -> int: ...
@overload
def parse(value: bytes) -> str: ...

def parse(value: str | bytes) -> int | str:
    if isinstance(value, bytes):
        return value.decode()
    return int(value)
```

---

## Dataclass Patterns

### Frozen (immutable) config

```python
from dataclasses import dataclass, field
from typing import Final

@dataclass(frozen=True)
class ConnectionConfig:
    host: str
    port: int
    database: str
    timeout: int = 30
    options: frozenset[str] = field(default_factory=frozenset)

    def __post_init__(self) -> None:
        if self.port < 1 or self.port > 65535:
            raise ValueError(f"invalid port: {self.port}")
```

### Post-init computed fields (use `field(init=False)`)

```python
from dataclasses import dataclass, field

@dataclass
class Pipeline:
    name: str
    catalog: str
    schema: str
    full_name: str = field(init=False)

    def __post_init__(self) -> None:
        self.full_name = f"{self.catalog}.{self.schema}.{self.name}"
```

---

## Error Handling Patterns

### Exception hierarchy

```python
class BlackstrawError(Exception):
    """Root exception — catch this to handle any Blackstraw error."""

class ConfigError(BlackstrawError):
    """Raised for invalid or missing configuration."""

class PipelineError(BlackstrawError):
    """Raised for pipeline execution failures."""

    def __init__(self, message: str, pipeline: str, step: str | None = None) -> None:
        super().__init__(message)
        self.pipeline = pipeline
        self.step = step

    def __str__(self) -> str:
        if self.step:
            return f"[{self.pipeline}/{self.step}] {super().__str__()}"
        return f"[{self.pipeline}] {super().__str__()}"
```

### Context-preserving exception chaining

```python
def load_pipeline_config(path: str) -> dict:
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError as exc:
        raise ConfigError(f"config file not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ConfigError(f"invalid JSON in config: {path}") from exc
```

---

## Generator Patterns

### Lazy file processing

```python
from pathlib import Path
from typing import Generator

def iter_csv_rows(path: Path) -> Generator[dict[str, str], None, None]:
    import csv
    with path.open() as f:
        reader = csv.DictReader(f)
        yield from reader   # no list() — streams rows one at a time
```

### Batch generator with configurable size

```python
def batched(items: list[T], size: int) -> Generator[list[T], None, None]:
    for i in range(0, len(items), size):
        yield items[i : i + size]

# Usage
for batch in batched(records, size=500):
    write_to_delta(batch)
```

### Generator pipeline (Unix pipe style)

```python
def read_records(path: str):
    with open(path) as f:
        yield from f

def parse_json(lines):
    for line in lines:
        yield json.loads(line)

def filter_active(records):
    for r in records:
        if r.get("status") == "active":
            yield r

# Compose: nothing is evaluated until iteration
pipeline = filter_active(parse_json(read_records("data.jsonl")))
for record in pipeline:
    process(record)
```

---

## Context Manager Patterns

### `contextlib.contextmanager` decorator

```python
from contextlib import contextmanager
from typing import Generator

@contextmanager
def temp_schema(catalog: str, name: str) -> Generator[str, None, None]:
    full = f"{catalog}.{name}"
    spark.sql(f"CREATE SCHEMA IF NOT EXISTS {full}")
    try:
        yield full
    finally:
        spark.sql(f"DROP SCHEMA IF EXISTS {full} CASCADE")

# Usage
with temp_schema("dev_catalog", "test_xyz") as schema:
    run_pipeline(schema)
# schema is dropped after the block exits, even on exception
```

### Class-based context manager

```python
class TimedBlock:
    def __init__(self, label: str) -> None:
        self.label = label
        self._start: float = 0.0

    def __enter__(self) -> "TimedBlock":
        import time
        self._start = time.perf_counter()
        return self

    def __exit__(self, *_: object) -> None:
        import time
        elapsed = time.perf_counter() - self._start
        print(f"{self.label}: {elapsed:.3f}s")
```

---

## Enum Patterns

### String Enum (values usable directly as strings)

```python
from enum import Enum

class WriteMode(str, Enum):
    APPEND    = "append"
    OVERWRITE = "overwrite"
    MERGE     = "merge"

# No .value needed — isinstance check works, string comparison works
mode = WriteMode.APPEND
assert mode == "append"           # True
print(f"Writing with mode: {mode}")  # "Writing with mode: append"
```

### Enum from external values (safe lookup)

```python
def parse_write_mode(value: str) -> WriteMode:
    try:
        return WriteMode(value)
    except ValueError:
        valid = [m.value for m in WriteMode]
        raise ValueError(f"unknown write mode {value!r}; expected one of {valid}")
```

---

## Async Patterns

Use `asyncio` when I/O is the bottleneck (API calls, file reads, DB queries).
Do not use async for CPU-bound work — use `multiprocessing` or Spark instead.

```python
import asyncio
import httpx
from typing import Any

async def fetch_all(urls: list[str]) -> list[dict[str, Any]]:
    async with httpx.AsyncClient(timeout=30) as client:
        tasks = [client.get(url) for url in urls]
        responses = await asyncio.gather(*tasks, return_exceptions=True)

    results = []
    for url, resp in zip(urls, responses):
        if isinstance(resp, Exception):
            raise PipelineError(f"fetch failed: {url}") from resp
        results.append(resp.json())
    return results
```

### Async context manager

```python
from contextlib import asynccontextmanager

@asynccontextmanager
async def managed_connection(dsn: str):
    conn = await asyncpg.connect(dsn)
    try:
        yield conn
    finally:
        await conn.close()
```

---

## Pathlib Over os.path

Always use `pathlib.Path`. Never use `os.path`.

```python
from pathlib import Path

base = Path("/data/pipelines")

# Build paths
config_path = base / "config" / "settings.json"

# Check existence
if not config_path.exists():
    raise ConfigError(f"missing: {config_path}")

# Read / write
content = config_path.read_text(encoding="utf-8")
config_path.write_text(json.dumps(data, indent=2))

# Iterate directory
for yaml_file in base.glob("**/*.yaml"):
    process(yaml_file)

# Extract parts
print(config_path.stem)    # "settings"
print(config_path.suffix)  # ".json"
print(config_path.parent)  # /data/pipelines/config
```
