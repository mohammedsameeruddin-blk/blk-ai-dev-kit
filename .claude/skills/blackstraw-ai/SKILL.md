---
name: blackstraw-ai
description: "Blackstraw AI and MLOps standards. Use when working with MLflow experiments, model training, model registry, serving endpoints, LLM integration, prompt management, or AI evaluation in a Blackstraw environment."
---

# Blackstraw AI / MLOps Standards

Conventions for all AI and machine learning work at Blackstraw. Apply alongside `databricks-python-sdk` for SDK usage and `blackstraw-databricks` for resource naming.

---

## MLflow Experiments

### Naming convention
```
/Users/{user}/@experiments/{project}          # Personal / exploratory
/Shared/blackstraw/{team}/{project}           # Team experiments
/Shared/blackstraw/{team}/{project}/prod      # Production training runs
```

> # TODO: Replace the path prefix `/Shared/blackstraw/` with Blackstraw's actual MLflow experiment root path.

### Required tags on every run
```python
import mlflow

with mlflow.start_run(run_name="training-v1") as run:
    mlflow.set_tags({
        "team": "ml",                        # TODO: your team
        "project": "customer-churn",         # TODO: your project
        "environment": "dev",                # dev | staging | prod
        "data_version": "2024-09-01",        # Date or hash of training data
        "owner": "user@blackstraw.ai",       # TODO: actual owner
    })
    mlflow.log_params({...})
    mlflow.log_metrics({...})
```

### Data lineage — required
Log the Unity Catalog table(s) used for training:
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

> # TODO: Confirm Blackstraw's model naming convention and confirm whether Unity Catalog Model Registry or Workspace Model Registry is the standard.

### Stage / alias conventions

| Alias | Meaning |
|-------|---------|
| `champion` | Currently serving in production |
| `challenger` | Canary / A-B test candidate |
| `staging` | Passed evaluation, pending production approval |
| `archived` | Retired, kept for audit |

```python
from mlflow import MlflowClient

client = MlflowClient()

# Register model
model_uri = f"runs:/{run.info.run_id}/model"
mv = mlflow.register_model(model_uri, "blk-ml-churn-xgboost")

# Promote to staging
client.set_registered_model_alias(
    name="blk-ml-churn-xgboost",
    alias="staging",
    version=mv.version
)
```

### Required model description fields
Every registered model version must have:
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

> # TODO: Add Blackstraw's approved compute sizes per endpoint tier (dev / staging / prod).

### Querying endpoints
```python
from databricks.sdk import WorkspaceClient
import asyncio

w = WorkspaceClient()

# For ML model endpoints
async def predict(inputs: list[dict]) -> dict:
    return await asyncio.to_thread(
        w.serving_endpoints.query,
        name="blk-ml-churn-prod",
        inputs=inputs
    )

# For LLM / chat endpoints (OpenAI-compatible)
async def chat(messages: list[dict]) -> str:
    client = w.serving_endpoints.get_open_ai_client()
    response = await asyncio.to_thread(
        client.chat.completions.create,
        model="blk-data-llm-prod",   # TODO: actual endpoint name
        messages=messages,
        max_tokens=1024,
    )
    return response.choices[0].message.content
```

### Production endpoint requirements
- Must have `auto_capture_config` enabled for inference logging
- Must have `scale_to_zero_enabled=False` for latency-sensitive endpoints
- Throughput / workload size reviewed by platform team before launch

> # TODO: Add the minimum `workload_size` for production endpoints and the inference table target schema.

---

## LLM Integration

### Approved models

> # TODO: List the LLM models approved for use at Blackstraw (e.g., `databricks-meta-llama-3-3-70b-instruct`, Azure OpenAI GPT-4o endpoint, etc.) and whether each is approved for data containing PII.

### Prompt management

- Prompts are versioned in source control — no magic strings in application code
- Store prompt templates as `.jinja2` or `.txt` files in `src/{package}/prompts/`
- Version prompts with semantic versioning in filename: `system_prompt_v1_2.txt`
- Log prompt template name and version as MLflow tags on every LLM experiment run

```python
from pathlib import Path
from jinja2 import Template

def load_prompt(name: str) -> Template:
    path = Path(__file__).parent / "prompts" / name
    return Template(path.read_text())

system_prompt = load_prompt("classification_v1_0.jinja2")
rendered = system_prompt.render(context=user_context)
```

### Token budgeting
- Always set `max_tokens` — never leave it unbounded
- Log `prompt_tokens` and `completion_tokens` as MLflow metrics for cost tracking
- For batch workloads, estimate token usage before running large-scale inference

---

## Evaluation Standards

### Minimum quality gates before production promotion

| Model type | Minimum metric | Gate |
|------------|---------------|------|
| Classification | AUC-ROC | ≥ 0.75 |
| Regression | R² | ≥ 0.70 |
| LLM task | LLM-judge score | ≥ 4.0 / 5.0 |
| Retrieval (RAG) | NDCG@10 | ≥ 0.60 |

> # TODO: Replace the table above with Blackstraw's actual quality gates per model type and business domain.

### Evaluation runs must log
```python
mlflow.log_metrics({
    "eval/auc_roc": 0.82,
    "eval/f1_weighted": 0.79,
    "eval/precision": 0.81,
    "eval/recall": 0.77,
    "eval/dataset_size": 50_000,
})
```

### LLM evaluation
Use Databricks `mlflow.evaluate` with a judge model:
```python
import mlflow

results = mlflow.evaluate(
    data=eval_df,
    model_type="question-answering",
    evaluators="default",
    evaluator_config={
        "judge_model": "endpoints:/blk-data-llm-prod",  # TODO: judge endpoint
    }
)
mlflow.log_metrics(results.metrics)
```

---

## Model Cards (Required for Production)

Every model promoted to `champion` must have a model card documenting:
1. **Purpose**: What decision/action does this model inform?
2. **Training data**: Sources, date range, known biases
3. **Evaluation results**: Metrics, benchmark datasets
4. **Limitations**: Known failure modes, out-of-distribution risks
5. **PII / fairness**: Does the model use or affect protected classes?
6. **Owner**: Team and individual responsible for monitoring

> # TODO: Link to Blackstraw's model card template (Confluence page, repo, or Google Doc).

---

## Related Skills

- **[databricks-python-sdk](../databricks-python-sdk/SKILL.md)** — SDK reference for serving endpoints, vector search, secrets
- **[blackstraw-databricks](../blackstraw-databricks/SKILL.md)** — Catalog namespaces, warehouse sizing, cluster policies
- **[blackstraw-security](../blackstraw-security/SKILL.md)** — PII handling in training data and inference logs
- **[blackstraw-standards](../blackstraw-standards/SKILL.md)** — Project structure and naming conventions
