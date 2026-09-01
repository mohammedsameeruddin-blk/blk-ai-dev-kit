---
name: blackstraw-security
description: "Blackstraw security and compliance rules. Use when handling credentials, PII data, external APIs, user input, logging, or deploying to production. Always apply for any code that touches sensitive data or external systems."
---

# Blackstraw Security & Compliance

Security-first rules for all Blackstraw engineering work. These apply on top of general coding standards.

---

## Secrets & Credentials

### Rules
1. **Never hardcode secrets** — no tokens, passwords, API keys, or connection strings in source code
2. **Never log secrets** — do not include credentials in log output, error messages, or tracebacks
3. **Never commit `.env` files** — `.env` is always in `.gitignore`; commit `.env.example` with placeholder values only
4. **Prefer Databricks secrets** over env vars for production workloads

### Correct patterns

```python
# Pattern 1: Databricks Secrets (production)
from databricks.sdk import WorkspaceClient
w = WorkspaceClient()
api_key = w.secrets.get_secret(scope="blk-data-prod", key="openai-api-key").value

# Pattern 2: pydantic-settings (local dev / CI)
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    openai_api_key: str
    database_url: str

    class Config:
        env_file = ".env"

settings = Settings()

# Pattern 3: Environment variable (scripts / containers)
import os
api_key = os.environ["OPENAI_API_KEY"]  # Raises if missing — intentional
```

### Banned patterns
```python
# NEVER — hardcoded credential
client = OpenAI(api_key="sk-proj-abc123...")

# NEVER — secret in f-string logged or printed
logger.info(f"Connecting with token: {token}")

# NEVER — secret passed as notebook widget
dbutils.widgets.text("api_key", "")  # Visible in job run history
```

---

## PII Data Handling

> # TODO: Define Blackstraw's PII classification tiers (e.g., Tier 1: name/email/SSN, Tier 2: IP/device ID, Tier 3: behavioural).

### General rules
- PII must never land in `_sandbox` schemas — use designated PII-approved schemas only
- PII columns must be tagged in Unity Catalog using `COMMENT` or column-level tags
- Mask or hash PII before writing to logs, dashboards, or non-production environments
- Do not pass PII as URL query parameters or in HTTP headers unless required by the API

### Masking pattern
```python
import hashlib

def mask_email(email: str) -> str:
    """One-way hash for PII-safe logging."""
    return hashlib.sha256(email.encode()).hexdigest()[:12]

# In logs
logger.info("Processing user", user_id=mask_email(user_email))
```

> # TODO: Add Blackstraw's approved anonymisation / pseudonymisation library if one is standardised.

---

## Input Validation

Always validate at system boundaries — HTTP handlers, CLI entry points, notebook parameters, job parameters.

```python
from pydantic import BaseModel, field_validator

class QueryRequest(BaseModel):
    warehouse_id: str
    sql: str
    limit: int = 1000

    @field_validator("sql")
    @classmethod
    def no_drop_or_truncate(cls, v: str) -> str:
        banned = ["drop ", "truncate ", "delete from"]
        lower = v.lower()
        if any(kw in lower for kw in banned):
            raise ValueError("Destructive SQL not allowed via this endpoint")
        return v

    @field_validator("limit")
    @classmethod
    def limit_range(cls, v: int) -> int:
        if not 1 <= v <= 10_000:
            raise ValueError("limit must be between 1 and 10,000")
        return v
```

**Never use string formatting to build SQL.** Always use parameterised queries or the Databricks statement execution API with `parameters`.

```python
# NEVER — SQL injection risk
query = f"SELECT * FROM {table} WHERE user_id = '{user_id}'"

# Correct — parameterised
response = w.statement_execution.execute_statement(
    warehouse_id=warehouse_id,
    statement="SELECT * FROM prod_data.sales_gold.orders WHERE user_id = :uid",
    parameters=[{"name": "uid", "value": user_id, "type": "STRING"}],
    wait_timeout="30s",
)
```

---

## Logging Rules

### What to log
- Request IDs and trace IDs (for correlation)
- Operation names, durations, record counts
- Error types and sanitised messages
- Environment and service version on startup

### Never log
- Passwords, tokens, API keys
- Full PII (names, emails, SSNs, phone numbers)
- Raw user-supplied input without sanitisation
- Database connection strings

### Structured logging with structlog
```python
import structlog

logger = structlog.get_logger()

# Good — structured, no PII
logger.info(
    "query_completed",
    warehouse_id=warehouse_id,
    duration_ms=elapsed,
    row_count=len(results),
    user_id_hash=mask_email(user_email),  # Hashed — not raw
)

# Bad — unstructured, may expose PII
print(f"User {user_email} ran query in {elapsed}ms")
```

---

## Dependency Vetting

Before adding a new third-party library:
1. Check it has active maintenance (commit in last 6 months)
2. Check for known CVEs: `uv run pip-audit` or [osv.dev](https://osv.dev)
3. Prefer libraries already in use across Blackstraw repos

> # TODO: Add link to Blackstraw's approved dependency list or internal PyPI mirror if one exists.

---

## Approved External Services

> # TODO: List the external APIs and services that are approved for use in Blackstraw production code (e.g., OpenAI, Azure OpenAI, Snowflake, SendGrid, etc.) and any that are explicitly banned.

When calling external APIs:
- Always set a timeout — never leave HTTP calls without one
- Wrap with retry logic using exponential backoff (use `tenacity`)
- Store API keys in Databricks secrets, not env vars in production

```python
import httpx
from tenacity import retry, stop_after_attempt, wait_exponential

@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=2, max=10))
def call_external_api(url: str, payload: dict) -> dict:
    with httpx.Client(timeout=30.0) as client:
        response = client.post(url, json=payload)
        response.raise_for_status()
        return response.json()
```

---

## Production Deployment Checklist

Before deploying to production:
- [ ] No hardcoded secrets in any file
- [ ] All external inputs validated with Pydantic
- [ ] PII never written to non-approved schemas or logs
- [ ] Destructive operations (DROP, DELETE, TRUNCATE) require manual approval gate
- [ ] Dependencies audited for CVEs (`pip-audit`)
- [ ] Logging does not expose credentials or raw PII
- [ ] Error messages safe to expose externally (no stack traces in API responses)

---

## Related Skills

- **[blackstraw-standards](../blackstraw-standards/SKILL.md)** — General coding conventions
- **[blackstraw-databricks](../blackstraw-databricks/SKILL.md)** — Secret scope naming and access patterns
- **[blackstraw-ai](../blackstraw-ai/SKILL.md)** — Model data governance and evaluation security
- **[python-dev](../python-dev/SKILL.md)** — Input validation and error handling patterns
