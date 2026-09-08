---
name: blackstraw-databricks
description: >-
  Blackstraw-specific Databricks conventions for Unity Catalog namespaces, warehouse
  sizing, secret scopes, cluster policies, job configuration, and environment separation.
  Use when creating or reviewing any Databricks resource — catalogs, schemas, tables,
  warehouses, clusters, jobs, or pipelines — in a Blackstraw workspace.
  Triggers on "create catalog", "create schema", "create table", "create warehouse",
  "create cluster", "create job", "databricks resource", "blackstraw workspace",
  "unity catalog", "secret scope", "cluster policy", "job tags", "environment separation".
  Always load alongside `databricks-python-sdk` for SDK usage patterns.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# Blackstraw Databricks Conventions

Blackstraw-specific rules layered on top of the `databricks-python-sdk` skill.
**Always load both skills together** when working in a Blackstraw Databricks workspace.

## Purpose

Enforces consistent naming, access control, and configuration across all Databricks
resources in Blackstraw workspaces. Prevents common mistakes like hardcoded secrets,
missing job tags, uncontrolled cluster sizes, and missing auto-stop — which cause
cost overruns, security incidents, and broken CI pipelines.

## When to Use

**Use this skill when:**
- Creating or configuring any Databricks resource (catalog, schema, table, warehouse, cluster, job, pipeline)
- Writing Python or SQL code that references Databricks tables or schemas
- Reviewing code that interacts with a Blackstraw workspace
- Setting up a new project that will run on Databricks

**Do NOT use this skill when:**
- Working on a non-Databricks data platform
- Writing generic PySpark code with no workspace-specific references

---

## Hard Rules

Non-negotiable. Enforce on every resource and every line of code.

- **ALWAYS** use 3-part fully-qualified names: `catalog.schema.table` — never bare table names
- **ALWAYS** set `auto_stop_mins` on every warehouse — never `0` in dev or staging
- **NEVER** hardcode secrets or passwords — use secret scopes via SDK or `dbutils.secrets`
- **NEVER** pass secrets as notebook widget parameters
- **NEVER** log secret values — not to MLflow, not to stdout, not to Delta
- **NEVER** drop tables in staging or production via code — requires a PR
- **ALWAYS** tag every production job with `team`, `environment`, `owner`, `cost-center`
- **ALWAYS** configure `on_failure` email notifications on production jobs
- **PREFER** cluster policies over unrestricted clusters in production

---

## Unity Catalog — Namespace Conventions

### Catalog naming
```
{env}_{team}    # e.g., dev_data, prod_ml, staging_platform
```

| Environment | Catalog prefix |
|---|---|
| Development | `dev_` |
| Staging | `staging_` |
| Production | `prod_` |

> **TODO:** Replace the catalog naming pattern with the actual Blackstraw catalog names
> (e.g., `blk_dev`, `blk_prod`, specific team catalogs).

### Schema naming
```
{catalog}.{domain}_{tier}    # e.g., prod_data.sales_silver
```

| Tier | Suffix | Purpose |
|---|---|---|
| Raw / Landing | `_raw` | Unmodified source data |
| Bronze | `_bronze` | Validated, typed |
| Silver | `_silver` | Joined, enriched |
| Gold / Serving | `_gold` | Aggregated, BI-ready |
| Sandbox | `_sandbox` | Exploration only — never production |

> **TODO:** Confirm Blackstraw's medallion layer naming and which teams own which schemas.

### 3-part names in code — always

```python
# Correct
df = spark.table("prod_data.sales_silver.customer_events")

# Wrong — relies on session default catalog/schema
df = spark.table("customer_events")
```

---

## SQL Warehouses

### Sizing guide

| Size | Use case |
|---|---|
| `X-Small` | Ad-hoc exploration, low concurrency |
| `Small` | Standard workloads, dashboards |
| `Medium` | High-concurrency BI or ETL |
| `Large` | Heavy batch processing |

> **TODO:** Add Blackstraw's actual approved warehouse IDs or names per environment.

### Required: auto-stop on every warehouse

```python
from databricks.sdk import WorkspaceClient

w = WorkspaceClient()

w.warehouses.create_and_wait(
    name="blk-dev-adhoc",
    cluster_size="X-Small",
    max_num_clusters=1,
    auto_stop_mins=15,    # required — never 0 in dev or staging
)
```

Production warehouses: disabling auto-stop requires platform team approval.

---

## Secret Scopes

### Naming pattern
```
blk-{team}-{environment}    # e.g., blk-data-prod, blk-ml-dev
```

> **TODO:** Confirm the exact secret scope naming convention used in Blackstraw workspaces.

### Accessing secrets — correct patterns

```python
from databricks.sdk import WorkspaceClient

w = WorkspaceClient()

# In Python code — use SDK
secret = w.secrets.get_secret(scope="blk-data-prod", key="postgres-password")

# In notebooks — use dbutils
value = dbutils.secrets.get(scope="blk-data-prod", key="postgres-password")

# WRONG — never do this
password = "super_secret_123"
```

---

## Cluster Conventions

### Naming pattern
```
{env}-{team}-{purpose}    # e.g., dev-ml-training, prod-etl-ingest
```

### Spark / DBR version
- Always use the current **LTS** version unless a specific feature requires otherwise

```python
# Get the current recommended LTS version
version = w.clusters.select_spark_version(latest=True, long_term_support=True)
```

> **TODO:** Pin the currently approved DBR version for Blackstraw (e.g., `14.3.x-scala2.12`).

### Node type guidance
- **Development:** `i3.xlarge` (local disk, cost-effective)
- **Production ETL:** confirm with platform team before provisioning `r5` or GPU instances
- Use cluster policies where available — do not create unrestricted clusters in production

> **TODO:** Add Blackstraw cluster policy IDs per environment.

---

## Jobs and Pipelines

### Job naming
```
{team}-{project}-{trigger}    # e.g., data-customer-daily, ml-scoring-hourly
```

### Required tags on every production job

```python
from databricks.sdk.service.jobs import CreateJob, JobEmailNotifications

w.jobs.create(
    name="data-customer-daily",
    tags={
        "team":         "data",                   # TODO: your team name
        "environment":  "prod",
        "owner":        "user@blackstraw.ai",     # TODO: actual owner email
        "cost-center":  "eng",                    # TODO: confirm cost-center values
    },
    email_notifications=JobEmailNotifications(
        on_failure=["data-alerts@blackstraw.ai"], # TODO: actual alert email/group
        no_alert_for_skipped_runs=True,
    ),
    ...
)
```

> **TODO:** Confirm required job tags and allowed values for `cost-center`.

---

## Environment Separation

| Rule | Dev | Staging | Prod |
|---|---|---|---|
| Auto-start clusters | Allowed | Allowed | Requires approval |
| Manual SQL execution | Allowed | Allowed | Read-only by default |
| Drop tables | Allowed (sandbox only) | Requires PR | Never via code |
| Access production secrets | Not allowed | Read-only | Service principals only |

> **TODO:** Adjust this matrix to match Blackstraw's actual access control policy.

---

## Workflow: Setting Up a New Databricks Resource

### Step 1: Choose the correct catalog and schema

Identify the environment (`dev` / `staging` / `prod`) and data tier (`_raw`, `_bronze`, etc.).
Confirm the catalog exists before creating schemas under it.

```python
w.catalogs.get("dev_data")   # verify before proceeding
```

**Checkpoint:** catalog name follows `{env}_{team}` pattern and exists in the workspace.

### Step 2: Apply naming convention

Name the resource following the patterns above. If unsure, check `references/naming-conventions.md`.

### Step 3: Configure required settings

- Warehouses → set `auto_stop_mins`
- Jobs → add all required tags + `on_failure` notifications
- Clusters → confirm LTS DBR version, apply cluster policy if available

### Step 4: Verify no secrets are hardcoded

Grep the code before committing:
```bash
grep -rE "(password|secret|token|key)\s*=\s*['\"][^'\"]{8,}" . --include="*.py"
```

---

## References

- **naming-conventions.md** — full naming patterns for every resource type in one place
- **[databricks-python-sdk](../databricks-python-sdk/SKILL.md)** — SDK reference, async patterns, full API examples
