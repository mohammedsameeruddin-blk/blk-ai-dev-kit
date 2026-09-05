# MLflow Patterns Reference

Detailed code patterns for MLflow experiment tracking, model registry, and evaluation.
Load this when you need a concrete implementation beyond the overview in `SKILL.md`.

---

## Experiment Setup

```python
import mlflow
from pathlib import Path

# Set tracking URI (Databricks-managed — usually via env var)
# MLFLOW_TRACKING_URI is set automatically in Databricks notebooks
# For local dev: export MLFLOW_TRACKING_URI=databricks

mlflow.set_experiment("/Shared/blackstraw/ml/customer-churn")  # team experiment path
```

---

## Full Training Run Template

```python
import mlflow
import mlflow.sklearn
from sklearn.ensemble import GradientBoostingClassifier

def train(X_train, y_train, X_eval, y_eval, params: dict) -> str:
    """Train and log a model run. Returns the run ID."""
    with mlflow.start_run(run_name=f"gbm-{params['n_estimators']}") as run:
        # Required tags
        mlflow.set_tags({
            "team":         "ml",
            "project":      "customer-churn",
            "environment":  "dev",
            "data_version": "2024-09-01",
            "owner":        "user@blackstraw.ai",
        })

        # Parameters
        mlflow.log_params(params)

        # Data lineage — required
        mlflow.log_input(
            mlflow.data.from_spark(
                spark.table("prod_ml.features_gold.customer_features"),
                table_name="prod_ml.features_gold.customer_features",
                version="latest",
            ),
            context="training",
        )

        # Train
        model = GradientBoostingClassifier(**params)
        model.fit(X_train, y_train)

        # Evaluation metrics
        from sklearn.metrics import roc_auc_score, f1_score
        preds = model.predict(X_eval)
        proba = model.predict_proba(X_eval)[:, 1]

        mlflow.log_metrics({
            "eval/auc_roc":      roc_auc_score(y_eval, proba),
            "eval/f1_weighted":  f1_score(y_eval, preds, average="weighted"),
            "eval/dataset_size": len(X_train),
        })

        # Log model
        mlflow.sklearn.log_model(model, "model")

    return run.info.run_id
```

---

## Model Registry — Full Lifecycle

```python
from mlflow import MlflowClient

client = MlflowClient()
model_name = "blk-ml-churn-xgboost"

# 1. Register
run_id = "abc123..."
mv = mlflow.register_model(f"runs:/{run_id}/model", model_name)
print(f"Registered: version {mv.version}")

# 2. Add required description
client.update_model_version(
    name=model_name,
    version=mv.version,
    description=(
        "GBM churn predictor. Input: customer features (prod_ml.features_gold.customer_features). "
        "Output: binary churn probability. Training data: 2024-01-01 to 2024-09-01. "
        f"AUC-ROC: 0.82. Run: {run_id}"
    ),
)

# 3. Promote to staging
client.set_registered_model_alias(name=model_name, alias="staging", version=mv.version)

# 4. After platform review: promote to champion, archive old
old_champion = client.get_model_version_by_alias(model_name, "champion")
client.set_registered_model_alias(name=model_name, alias="champion",  version=mv.version)
client.set_registered_model_alias(name=model_name, alias="archived",  version=old_champion.version)
```

---

## Loading a Model from the Registry

```python
import mlflow.pyfunc

# Load champion
model = mlflow.pyfunc.load_model(f"models:/blk-ml-churn-xgboost@champion")

# Predict
predictions = model.predict(X_new)
```

---

## LLM Experiment Run Template

```python
import mlflow
from pathlib import Path
from jinja2 import Template
import openai   # or Databricks SDK

def run_llm_experiment(questions: list[str], prompt_name: str) -> None:
    template = Template((Path("src/mypackage/prompts") / prompt_name).read_text())

    with mlflow.start_run(run_name=f"llm-{prompt_name}"):
        mlflow.set_tags({
            "team":          "ml",
            "project":       "support-qa",
            "environment":   "dev",
            "prompt_name":   prompt_name,
            "prompt_version": "1.0",
            "owner":         "user@blackstraw.ai",
        })

        total_prompt = total_completion = 0

        for q in questions:
            response = client.chat.completions.create(
                model="blk-data-llm-prod",
                messages=[{"role": "user", "content": template.render(question=q)}],
                max_tokens=512,               # always set
            )
            total_prompt     += response.usage.prompt_tokens
            total_completion += response.usage.completion_tokens

        # Log aggregate token usage
        mlflow.log_metrics({
            "llm/prompt_tokens":     total_prompt,
            "llm/completion_tokens": total_completion,
            "llm/total_tokens":      total_prompt + total_completion,
            "llm/questions_run":     len(questions),
        })
```

---

## LLM Evaluation with Judge Model

```python
import mlflow
import pandas as pd

eval_df = pd.DataFrame([
    {"inputs": "What is our refund policy?",   "ground_truth": "30-day full refund..."},
    {"inputs": "How do I cancel my account?",  "ground_truth": "Go to Settings..."},
])

with mlflow.start_run(run_name="eval-support-qa-v1"):
    results = mlflow.evaluate(
        data=eval_df,
        model="runs:/abc123.../model",
        model_type="question-answering",
        targets="ground_truth",
        evaluators="default",
        evaluator_config={
            "judge_model": "endpoints:/blk-data-llm-prod",
        },
    )
    mlflow.log_metrics(results.metrics)
    print(results.tables["eval_results_table"])
```
