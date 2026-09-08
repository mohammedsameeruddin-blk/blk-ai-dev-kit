# Naming Conventions Reference

Quick-reference table for every Databricks resource type at Blackstraw.
Load this file when you need to verify or generate a resource name.

---

## Pattern Summary

| Resource | Pattern | Example |
|---|---|---|
| Catalog | `{env}_{team}` | `dev_data`, `prod_ml`, `staging_platform` |
| Schema | `{catalog}.{domain}_{tier}` | `prod_data.sales_silver` |
| Table | `{catalog}.{schema}.{entity}` | `prod_data.sales_silver.customer_events` |
| Warehouse | `blk-{team}-{purpose}` | `blk-data-reporting`, `blk-ml-training` |
| Secret scope | `blk-{team}-{env}` | `blk-data-prod`, `blk-ml-dev` |
| Cluster | `{env}-{team}-{purpose}` | `dev-ml-training`, `prod-etl-ingest` |
| Job | `{team}-{project}-{trigger}` | `data-customer-daily`, `ml-scoring-hourly` |
| Pipeline (DLT) | `{team}-{project}-{layer}` | `data-sales-bronze`, `ml-features-silver` |
| Model | `blk-{team}-{project}-{type}` | `blk-ml-churn-xgboost` |
| Serving endpoint | `blk-{team}-{project}-{env}` | `blk-ml-churn-prod`, `blk-data-embed-dev` |

---

## Environment Prefixes

| Environment | Catalog prefix | Endpoint suffix | Scope suffix |
|---|---|---|---|
| Development | `dev_` | `-dev` | `-dev` |
| Staging | `staging_` | `-staging` | `-staging` |
| Production | `prod_` | `-prod` | `-prod` |

---

## Schema Tier Suffixes

| Tier | Suffix | Owner | SLA |
|---|---|---|---|
| Raw / Landing | `_raw` | Ingest team | Best-effort |
| Bronze | `_bronze` | Data Engineering | Daily |
| Silver | `_silver` | Data Engineering | Daily |
| Gold | `_gold` | Data / ML team | SLA-backed |
| Sandbox | `_sandbox` | Individual engineer | None |

> **TODO:** Fill in actual owner teams and SLA tiers for each layer at Blackstraw.

---

## TODOs (replace before shipping to production)

- [ ] Confirm catalog naming: `{env}_{team}` or a fixed set like `blk_dev`, `blk_prod`?
- [ ] Confirm approved warehouse IDs/names per environment
- [ ] Confirm DBR / Spark LTS version to pin
- [ ] Confirm cluster policy IDs per environment
- [ ] Confirm `cost-center` tag allowed values
- [ ] Confirm alert email / PagerDuty routing for job `on_failure`
