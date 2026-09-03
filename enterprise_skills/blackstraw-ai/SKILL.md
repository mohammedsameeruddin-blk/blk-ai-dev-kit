---
name: blackstraw-ai
description: >-
  Blackstraw AI and MLOps standards for MLflow experiments, model training, model
  registry, serving endpoints, LLM integration, prompt management, and AI evaluation.
  Use when working on any ML or AI workload in a Blackstraw environment.
  Triggers on "mlflow experiment", "model training", "model registry", "register model",
  "serving endpoint", "llm integration", "prompt management", "ai evaluation",
  "model card", "model promotion", "champion model", "inference logging", "token budget".
  Always load alongside `blackstraw-databricks` for resource naming and
  `databricks-python-sdk` for SDK patterns.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# Blackstraw AI / MLOps Standards

Conventions for all AI and machine learning work at Blackstraw.
Apply alongside `databricks-python-sdk` for SDK usage and `blackstraw-databricks`
for resource naming and workspace configuration.

## Purpose

Enforces consistent MLflow experiment tracking, model registry usage, serving
endpoint configuration, LLM prompt hygiene, and evaluation quality gates across
all Blackstraw AI projects. Prevents common problems: untagged runs that can't
be audited, prompt strings hardcoded in application code, models promoted to
production without passing quality gates, and LLM inference without cost tracking.

## When to Use

**Use this skill when:**
- Setting up or running MLflow experiments
- Registering or promoting models in the model registry
- Creating or querying serving endpoints
- Integrating an LLM into a Blackstraw application
- Running evaluation before a model promotion
- Writing a model card for a production promotion

**Do NOT use this skill when:**
- Working on non-ML code (ETL, dashboards, SQL queries without a model)
- Using a non-Databricks ML platform

---

## Hard Rules

Non-negotiable on every AI/ML workload.

- **ALWAYS** set the required MLflow tags (`team`, `project`, `environment`, `data_version`, `owner`) on every run
- **ALWAYS** log the Unity Catalog training table via `mlflow.log_input` — data lineage is mandatory
- **ALWAYS** set `max_tokens` on every LLM call — never leave it unbounded
- **ALWAYS** log `prompt_tokens` and `completion_tokens` as MLflow metrics on every LLM experiment run
- **NEVER** put prompt templates as string literals in application code — use versioned files in `src/{package}/prompts/`
- **NEVER** promote a model to `champion` without a completed model card
- **NEVER** deploy a production serving endpoint without `auto_capture_config` enabled
- **NEVER** set `scale_to_zero_enabled=True` on latency-sensitive production endpoints
- **PREFER** `mlflow.evaluate` with a judge model over manual evaluation scripts

---

## MLflow Experiments

### Experiment path naming
```
/Users/{user}/@experiments/{project}          # Personal / exploratory
/Shared/blackstraw/{team}/{project}           # Team experiments
/Shared/blackstraw/{team}/{project}/prod      # Production training runs
```

> **TODO:** Replace `/Shared/blackstraw/` with Blackstraw's actual MLflow experiment root path.

### Required tags on every run

```python
import mlflow

with mlflow.start_run(run_name="training-v1") as run:
    mlflow.set_tags({
        "team":         "ml",                      # TODO: your team
        "project":      "customer-churn",          # TODO: your project
        "environment":  "dev",                     # dev | staging | prod
        "data_version": "2024-09-01",              # date or hash of training data
        "owner":        "user@blackstraw.ai",      # TODO: actual owner
    })
    mlflow.log_params({...})
    mlflow.log_metrics({...})
```

### Data lineage — required

Log the Unity Catalog table(s) used for training on every run:

```python
mlflow.log_input(
    mlflow.data.from_spark(
        df,
        table_name="prod_ml.features_gold.customer_features",
        version="latest"
    ),
    context="training"
)
```

---

## Model Registry

### Model naming convention
```
blk-{team}-{project}-{model-type}    # e.g., blk-ml-churn-xgboost
```

> **TODO:** Confirm Blackstraw's model naming convention and whether Unity Catalog
> Model Registry or Workspace Model Registry is the standard.

### Alias lifecycle

| Alias | Meaning |
|---|---|
| `champion` | Currently serving in production |
| `challenger` | Canary / A-B test candidate |
| `staging` | Passed evaluation, pending production approval |
| `archived` | Retired, kept for audit |

### Registering and promoting a model

```python
from mlflow import MlflowClient

client = MlflowClient()

# Register
model_uri = f"runs:/{run.info.run_id}/model"
mv = mlflow.register_model(model_uri, "blk-ml-churn-xgboost")

# Promote to staging
client.set_registered_model_alias(
    name="blk-ml-churn-xgboost",
    alias="staging",
    version=mv.version,
)
```

### Required fields on every registered model version
- `description`: what the model does, input/output schema
- Training data date range
- Key evaluation metrics (AUC, F1, RMSE, etc.)
- Link to the MLflow experiment run

---

## Serving Endpoints

### Naming convention
```
blk-{team}-{project}-{env}    # e.g., blk-ml-churn-prod, blk-data-embed-dev
```

### Querying endpoints

```python
from databricks.sdk import WorkspaceClient
import asyncio

w = WorkspaceClient()

# ML model endpoints
async def predict(inputs: list[dict]) -> dict:
    return await asyncio.to_thread(
        w.serving_endpoints.query,
        name="blk-ml-churn-prod",
        inputs=inputs,
    )

# LLM / chat endpoints (OpenAI-compatible)
async def chat(messages: list[dict]) -> str:
    client = w.serving_endpoints.get_open_ai_client()
    response = await asyncio.to_thread(
        client.chat.completions.create,
        model="blk-data-llm-prod",    # TODO: actual endpoint name
        messages=messages,
        max_tokens=1024,              # required — never omit
    )
    return response.choices[0].message.content
```

### Production endpoint requirements
- `auto_capture_config` enabled — inference logging is mandatory
- `scale_to_zero_enabled=False` for latency-sensitive endpoints
- `workload_size` reviewed and approved by platform team before launch

> **TODO:** Add the minimum `workload_size` for production endpoints and the
> inference table target schema.

---

## LLM Integration

### Approved models

> **TODO:** List the LLM models approved for use at Blackstraw (e.g.,
> `databricks-meta-llama-3-3-70b-instruct`, Azure OpenAI GPT-4o, etc.) and
> whether each is approved for data containing PII.

### Prompt management — versioned files only

Prompts live in `src/{package}/prompts/` as `.jinja2` or `.txt` files.
Version in the filename: `system_prompt_v1_2.jinja2`.
Log prompt template name and version as MLflow tags on every LLM run.

```python
from pathlib import Path
from jinja2 import Template

def load_prompt(name: str) -> Template:
    path = Path(__file__).parent / "prompts" / name
    return Template(path.read_text())

system_prompt = load_prompt("classification_v1_0.jinja2")
rendered = system_prompt.render(context=user_context)
```

### Token budgeting — required

```python
# Always set max_tokens
response = client.chat.completions.create(
    model="blk-data-llm-prod",
    messages=messages,
    max_tokens=1024,                  # never omit
)

# Always log token usage
mlflow.log_metrics({
    "llm/prompt_tokens":     response.usage.prompt_tokens,
    "llm/completion_tokens": response.usage.completion_tokens,
    "llm/total_tokens":      response.usage.total_tokens,
})
```

---

## Evaluation Standards

### Minimum quality gates before production promotion

| Model type | Metric | Minimum |
|---|---|---|
| Classification | AUC-ROC | ≥ 0.75 |
| Regression | R² | ≥ 0.70 |
| LLM task | LLM-judge score | ≥ 4.0 / 5.0 |
| Retrieval (RAG) | NDCG@10 | ≥ 0.60 |

> **TODO:** Replace with Blackstraw's actual quality gates per model type and business domain.

### Required evaluation metrics to log

```python
mlflow.log_metrics({
    "eval/auc_roc":       0.82,
    "eval/f1_weighted":   0.79,
    "eval/precision":     0.81,
    "eval/recall":        0.77,
    "eval/dataset_size":  50_000,
})
```

### LLM evaluation with judge model

```python
import mlflow

results = mlflow.evaluate(
    data=eval_df,
    model_type="question-answering",
    evaluators="default",
    evaluator_config={
        "judge_model": "endpoints:/blk-data-llm-prod",  # TODO: judge endpoint name
    },
)
mlflow.log_metrics(results.metrics)
```

---

## Model Cards (Required for `champion` Promotion)

Every model promoted to `champion` must have a model card covering:

1. **Purpose** — what decision or action does this model inform?
2. **Training data** — sources, date range, known biases
3. **Evaluation results** — metrics, benchmark datasets
4. **Limitations** — known failure modes, out-of-distribution risks
5. **PII / fairness** — does the model use or affect protected classes?
6. **Owner** — team and individual responsible for monitoring

> **TODO:** Link to Blackstraw's model card template (Confluence page, repo, or Google Doc).

---

## Workflow: Promoting a Model to Production

### Step 1: Run evaluation against quality gates

Run `mlflow.evaluate` with the agreed judge model and scorer suite.
All metrics in the quality gates table above must pass.

**Checkpoint:** `mlflow.log_metrics` called, all `eval/*` metrics meet the minimum thresholds.

### Step 2: Complete the model card

Fill in all six sections. Link the experiment run ID.

**Checkpoint:** model card committed to the repo or linked in the registry description.

### Step 3: Promote alias to `staging`

```python
client.set_registered_model_alias(name=model_name, alias="staging", version=version)
```

**Checkpoint:** platform team review complete.

### Step 4: Promote to `champion`

```python
client.set_registered_model_alias(name=model_name, alias="champion", version=version)
client.set_registered_model_alias(name=model_name, alias="archived", version=old_version)
```

### Step 5: Verify endpoint configuration

Confirm `auto_capture_config` is enabled and `scale_to_zero_enabled=False`
for latency-sensitive endpoints before routing production traffic.

---

## References

- **mlflow-patterns.md** — detailed MLflow experiment, registry, and evaluation code patterns
- **[blackstraw-databricks](../blackstraw-databricks/SKILL.md)** — catalog namespaces, warehouse sizing, cluster policies
- **[databricks-python-sdk](../databricks-python-sdk/SKILL.md)** — SDK reference for serving endpoints, vector search, secrets
