---
name: blackstraw-databricks
description: "Blackstraw-specific Databricks conventions including Unity Catalog namespaces, warehouse sizing, secret scopes, cluster policies, and environment separation. Use when working with any Databricks resource in a Blackstraw workspace."
---

# Blackstraw Databricks Conventions

Blackstraw-specific rules layered on top of the `databricks-python-sdk` skill. Always apply both together when working in a Blackstraw Databricks workspace.

---

## Unity Catalog — Namespace Conventions

### Catalog structure
```
{env}_{team}           # e.g., dev_data, prod_ml, staging_platform
```

| Environment | Catalog prefix |
|-------------|----------------|
| Development | `dev_` |
| Staging     | `staging_` |
| Production  | `prod_` |

> # TODO: Replace the catalog naming pattern above with the actual Blackstraw catalog names (e.g., `blk_dev`, `blk_prod`, specific team catalogs).

### Schema structure
```
{catalog}.{domain}_{purpose}     # e.g., prod_data.sales_raw
```

Common schema tiers:

| Tier | Suffix | Purpose |
|------|--------|---------|
| Raw / Landing | `_raw` | Unmodified source data |
| Cleaned / Bronze | `_bronze` | Validated, typed |
| Silver | `_silver` | Joined, enriched |
| Gold / Serving | `_gold` | Aggregated, BI-ready |
| Sandbox | `_sandbox` | Exploration, never production |

> # TODO: Confirm Blackstraw's medallion layer naming and which teams own which schemas.

### Always use 3-part names in code
```python
# Correct
df = spark.table("prod_data.sales_silver.customer_events")

# Wrong — relies on default catalog/schema
df = spark.table("customer_events")
```

---

## SQL Warehouses

### Sizing tiers

| Size | Use case |
|------|---------|
| `X-Small` | Ad-hoc exploration, low concurrency |
| `Small` | Standard workloads, dashboards |
| `Medium` | High-concurrency BI or ETL |
| `Large` | Heavy batch processing |

> # TODO: Add Blackstraw's actual approved warehouse IDs or names per environment.

### Always set auto-stop
```python
w.warehouses.create_and_wait(
    name="blk-dev-adhoc",
    cluster_size="X-Small",
    max_num_clusters=1,
    auto_stop_mins=15,   # Required — never set to 0 in dev/staging
)
```

Production warehouses: auto-stop must be reviewed and approved before disabling.

---

## Secret Scopes

### Naming pattern
```
blk-{team}-{environment}      # e.g., blk-data-prod, blk-ml-dev
```

> # TODO: Confirm the exact secret scope naming convention used in Blackstraw workspaces.

### Accessing secrets in code
```python
from databricks.sdk import WorkspaceClient

w = WorkspaceClient()

# Correct — use SDK
secret = w.secrets.get_secret(scope="blk-data-prod", key="postgres-password")

# Correct — use dbutils in notebooks
value = dbutils.secrets.get(scope="blk-data-prod", key="postgres-password")

# Wrong — never hardcode or pass as plain env var in production
password = "super_secret_123"
```

Never log secret values. Never pass secrets as notebook widget parameters.

---

## Cluster Conventions

### Naming pattern
```
{env}-{team}-{purpose}        # e.g., dev-ml-training, prod-etl-ingest
```

### Spark version
- Always use the current **LTS** version unless a specific feature requires otherwise
- Check available versions: `w.clusters.select_spark_version(latest=True, long_term_support=True)`

> # TODO: Pin the currently approved Spark/DBR version for Blackstraw (e.g., `14.3.x-scala2.12`).

### Node types
- Development: prefer `i3.xlarge` (local disk, cost-effective)
- Production ETL: confirm with platform team before provisioning `r5` or GPU instances
- Use cluster policies when available — do not create unrestricted clusters in production

> # TODO: Add Blackstraw cluster policy IDs for each environment.

---

## Jobs & Pipelines

### Job naming
```
{team}-{project}-{trigger}    # e.g., data-customer-daily, ml-scoring-hourly
```

### Required job tags
All production jobs must include these tags:
```python
from databricks.sdk.service.jobs import CreateJob

w.jobs.create(
    name="data-customer-daily",
    tags={
        "team": "data",           # TODO: your team name
        "environment": "prod",
        "owner": "user@blackstraw.ai",  # TODO: use actual owner email
        "cost-center": "eng",     # TODO: confirm cost-center values
    },
    ...
)
```

> # TODO: Confirm required job tags and allowed values for `cost-center`.

### Email notifications
All production jobs must configure `on_failure` notifications:
```python
from databricks.sdk.service.jobs import JobEmailNotifications

email_notifications = JobEmailNotifications(
    on_failure=["data-alerts@blackstraw.ai"],  # TODO: actual alert email/group
    no_alert_for_skipped_runs=True,
)
```

---

## Environment Separation

| Rule | Dev | Staging | Prod |
|------|-----|---------|------|
| Auto-start clusters | Allowed | Allowed | Requires approval |
| Manual SQL execution | Allowed | Allowed | Read-only by default |
| Drop tables | Allowed (sandbox only) | Requires PR | Never via code |
| Access production secrets | Not allowed | Read-only | Service principals only |

> # TODO: Adjust the environment access matrix to match Blackstraw's actual access control policy.

---

## Related Skills

- **[databricks-python-sdk](../databricks-python-sdk/SKILL.md)** — Full SDK reference, async patterns, all API examples
- **[blackstraw-standards](../blackstraw-standards/SKILL.md)** — General Blackstraw coding conventions
- **[blackstraw-security](../blackstraw-security/SKILL.md)** — Credential and PII handling
- **[blackstraw-ai](../blackstraw-ai/SKILL.md)** — MLflow, model serving, and AI conventions
