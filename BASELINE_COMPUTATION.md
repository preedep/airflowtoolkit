# Baseline Computation DAG Documentation

## 📊 Overview

**DAG ID**: `baseline_compute_daily`

**Purpose**: Automatically calculate performance baselines for all Airflow tasks daily and store them in the `airflow_extension` database for SLA monitoring and anomaly detection.

**Schedule**: Daily at 2:00 AM Bangkok time (`0 2 * * *`)

**Tags**: `baseline`, `sla`, `monitoring`

---

## 🎯 What It Does

The baseline computation DAG performs three main operations:

1. **Extract**: Query task execution history from Airflow metadata database
2. **Compute**: Calculate percentile statistics (p50, p90, p95, p99) and standard deviation
3. **Upsert**: Store/update baselines in `airflow_extension.task_baseline` table

### Workflow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    baseline_compute_daily                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │  extract(14)     │
                    │  Extract task    │
                    │  execution data  │
                    │  from metadata   │
                    └────────┬─────────┘
                             │
                             │ List[Dict] (task executions)
                             ▼
                    ┌──────────────────┐
                    │  compute(...)    │
                    │  Calculate       │
                    │  percentiles &   │
                    │  statistics      │
                    └────────┬─────────┘
                             │
                             │ List[Dict] (baselines)
                             ▼
                    ┌──────────────────┐
                    │  upsert(...)     │
                    │  Store baselines │
                    │  in database     │
                    └────────┬─────────┘
                             │
                             │ Dict (summary)
                             ▼
                    ┌──────────────────┐
                    │  report(...)     │
                    │  Print summary   │
                    └──────────────────┘
```

---

## ⚙️ Configuration

### Constants

| Parameter | Value | Description |
|-----------|-------|-------------|
| `WINDOW_DAYS` | 14 | Look back 14 days for historical data |
| `MIN_SAMPLES` | 20 | Minimum 20 successful runs required |
| `BASELINE_KEY` | "default" | Baseline context identifier |
| `BUFFER_PERCENT` | 0.15 | Recommended SLA = p95 × 1.15 (15% buffer) |

### Connections

| Connection ID | Database | Purpose |
|---------------|----------|---------|
| `airflow_metadata` | `airflow` | Read task execution history |
| `airflow_extension` | `airflow_extension` | Write baseline statistics |

---

## 📋 Task Details

### 1. Extract Task

**Function**: `extract(window_days: int) -> List[Dict[str, Any]]`

**Purpose**: Extract successful task execution records from Airflow metadata database.

**SQL Query**:
```sql
SELECT 
    dag_id, 
    task_id,
    EXTRACT(EPOCH FROM (end_date - start_date)) AS duration_seconds
FROM task_instance
WHERE state = 'success'
  AND start_date IS NOT NULL 
  AND end_date IS NOT NULL
  AND end_date >= start_date
  AND end_date >= (%(as_of)s::date - (%(window_days)s::int || ' days')::interval)
  AND end_date < (%(as_of)s::date + interval '1 day')
ORDER BY dag_id, task_id, end_date;
```

**Output Format**:
```python
[
    {"dag_id": "example_dag", "task_id": "task_1", "dur": 120.5},
    {"dag_id": "example_dag", "task_id": "task_2", "dur": 60.2},
    ...
]
```

**Filters**:
- Only `success` state tasks
- Valid start/end dates (end_date >= start_date)
- Within time window (14 days by default)
- Positive duration only

---

### 2. Compute Task

**Function**: `compute(rows, window_days, min_samples) -> List[Dict[str, Any]]`

**Purpose**: Calculate statistical baselines from task execution history.

**Algorithm**:

1. **Group by Task**: Bucket durations by `(dag_id, task_id)`
2. **Filter**: Skip tasks with < MIN_SAMPLES (20) executions
3. **Sort**: Sort durations for percentile calculation
4. **Calculate Statistics**:
   - **Mean (avg)**: `sum(durations) / count`
   - **Standard Deviation**: `sqrt(variance)`
   - **Percentiles**: p50, p90, p95, p99 using linear interpolation
   - **Recommended SLA**: `p95 × (1 + BUFFER_PERCENT)`

**Percentile Calculation**:
```python
def percentile(vals_sorted: List[float], p: float) -> float:
    """Linear interpolation between two closest values"""
    k = (len(vals_sorted) - 1) * (p / 100.0)
    f = int(k)  # Floor
    c = min(f + 1, len(vals_sorted) - 1)  # Ceiling
    if f == c:
        return float(vals_sorted[f])
    # Interpolate
    return float(vals_sorted[f] * (c - k) + vals_sorted[c] * (k - f))
```

**Output Format**:
```python
[
    {
        "dag_id": "example_dag",
        "task_id": "task_1",
        "baseline_key": "default",
        "window_days": 14,
        "as_of_date": "2025-02-18",
        "samples": 100,
        "avg_seconds": 120.5,
        "p50_seconds": 115.0,
        "p90_seconds": 180.0,
        "p95_seconds": 200.0,
        "p99_seconds": 250.0,
        "stddev_seconds": 45.2,
        "recommended_sla_seconds": 230.0  # p95 * 1.15
    },
    ...
]
```

---

### 3. Upsert Task

**Function**: `upsert(baselines: List[Dict[str, Any]]) -> Dict[str, int]`

**Purpose**: Insert or update baselines in `airflow_extension.task_baseline` table.

**SQL Query**:
```sql
INSERT INTO task_baseline (
  dag_id, task_id, baseline_key, window_days, as_of_date, samples,
  avg_seconds, p50_seconds, p90_seconds, p95_seconds, p99_seconds,
  stddev_seconds, recommended_sla_seconds, updated_at
) VALUES (
  %(dag_id)s, %(task_id)s, %(baseline_key)s, %(window_days)s, 
  %(as_of_date)s, %(samples)s, %(avg_seconds)s, %(p50_seconds)s, 
  %(p90_seconds)s, %(p95_seconds)s, %(p99_seconds)s, 
  %(stddev_seconds)s, %(recommended_sla_seconds)s, now()
)
ON CONFLICT (dag_id, task_id, baseline_key, window_days, as_of_date)
DO UPDATE SET
  samples = EXCLUDED.samples,
  avg_seconds = EXCLUDED.avg_seconds,
  p50_seconds = EXCLUDED.p50_seconds,
  p90_seconds = EXCLUDED.p90_seconds,
  p95_seconds = EXCLUDED.p95_seconds,
  p99_seconds = EXCLUDED.p99_seconds,
  stddev_seconds = EXCLUDED.stddev_seconds,
  recommended_sla_seconds = EXCLUDED.recommended_sla_seconds,
  updated_at = now();
```

**Conflict Resolution**: 
- Primary key: `(dag_id, task_id, baseline_key, window_days, as_of_date)`
- On conflict: Update all statistics with new values

**Output**:
```python
{
    "inserted": 0,  # Can't distinguish in ON CONFLICT
    "updated": 0,   # Can't distinguish in ON CONFLICT
    "total": 150    # Total baselines processed
}
```

---

### 4. Report Task

**Function**: `report(summary: Dict[str, int]) -> None`

**Purpose**: Print summary report to logs.

**Output Example**:
```
============================================================
📊 Baseline Computation Summary
============================================================
Total baselines processed: 150
Window: 14 days
Min samples: 20
Buffer: 15%
============================================================
```

---

## 🚀 Deployment

### Files Created

1. **`dags/baseline_compute_daily.py`**: DAG source code
2. **`k8s/airflow/baseline-dag-configmap.yaml`**: Kubernetes ConfigMap
3. **`k8s/airflow/airflow-connections-secret.yaml`**: Database connections
4. **`k8s/airflow/values.yaml`**: Updated with volume mounts and env vars

### Deployment Steps

```bash
# Deploy all components
./deploy.sh

# Or deploy manually:
kubectl apply -f k8s/airflow/airflow-connections-secret.yaml
kubectl apply -f k8s/airflow/baseline-dag-configmap.yaml

# Upgrade Airflow with new values
helm upgrade airflow apache-airflow/airflow \
  --namespace airflow \
  --values k8s/airflow/values.yaml \
  --version 1.18.0
```

### Verify Deployment

```bash
# Check DAG is loaded
kubectl exec -n airflow deployment/airflow-scheduler -- \
  airflow dags list | grep baseline_compute_daily

# Check connections
kubectl exec -n airflow deployment/airflow-scheduler -- \
  airflow connections list | grep -E "airflow_metadata|airflow_extension"

# Trigger manual run
kubectl exec -n airflow deployment/airflow-scheduler -- \
  airflow dags trigger baseline_compute_daily
```

---

## 📊 Usage

### View Baselines in Database

```sql
-- Connect to airflow_extension database
\c airflow_extension

-- View latest baselines
SELECT * FROM v_latest_task_baseline
ORDER BY dag_id, task_id;

-- View baselines for specific DAG
SELECT 
    task_id,
    samples,
    avg_seconds,
    p95_seconds,
    recommended_sla_seconds
FROM v_latest_task_baseline
WHERE dag_id = 'your_dag_id'
ORDER BY task_id;

-- View baseline history
SELECT 
    as_of_date,
    task_id,
    p95_seconds,
    recommended_sla_seconds
FROM task_baseline
WHERE dag_id = 'your_dag_id'
  AND task_id = 'your_task_id'
ORDER BY as_of_date DESC
LIMIT 30;
```

### Query from Grafana

```sql
-- Dashboard query: Latest baselines
SELECT 
    dag_id as "DAG ID",
    task_id as "Task ID",
    samples as "Samples",
    ROUND(avg_seconds::numeric, 2) as "Avg (s)",
    ROUND(p50_seconds::numeric, 2) as "p50 (s)",
    ROUND(p95_seconds::numeric, 2) as "p95 (s)",
    ROUND(recommended_sla_seconds::numeric, 2) as "Recommended SLA (s)",
    as_of_date as "As Of Date"
FROM v_latest_task_baseline
ORDER BY dag_id, task_id;
```

---

## 🔧 Customization

### Adjust Time Window

Edit DAG file and change `WINDOW_DAYS`:
```python
WINDOW_DAYS = 30  # Use 30 days instead of 14
```

### Adjust Minimum Samples

```python
MIN_SAMPLES = 10  # Require only 10 samples instead of 20
```

### Adjust SLA Buffer

```python
BUFFER_PERCENT = 0.20  # Use 20% buffer instead of 15%
```

### Add Baseline Keys

For different contexts (e.g., month-end, weekday):

```python
# In compute task, add logic to determine baseline_key
from datetime import datetime

def get_baseline_key(as_of_date: datetime) -> str:
    """Determine baseline key based on date"""
    if as_of_date.day >= 25:
        return "month_end"
    elif as_of_date.weekday() == 0:  # Monday
        return "weekday=Mon"
    else:
        return "default"

# Use in baseline dict
baseline_key = get_baseline_key(as_of)
```

---

## 🐛 Troubleshooting

### DAG Not Appearing

```bash
# Check if DAG file is mounted
kubectl exec -n airflow deployment/airflow-scheduler -- \
  ls -la /opt/airflow/dags/baseline_compute_daily.py

# Check DAG parsing errors
kubectl logs -n airflow deployment/airflow-scheduler | grep baseline_compute_daily
```

### Connection Errors

```bash
# Verify connections exist
kubectl exec -n airflow deployment/airflow-scheduler -- \
  airflow connections list

# Test connection
kubectl exec -n airflow deployment/airflow-scheduler -- \
  airflow connections test airflow_metadata

kubectl exec -n airflow deployment/airflow-scheduler -- \
  airflow connections test airflow_extension
```

### No Baselines Generated

**Check logs**:
```bash
kubectl logs -n airflow -l dag_id=baseline_compute_daily
```

**Common issues**:
- Insufficient samples (< 20 successful runs)
- No task executions in time window
- Database connection issues

**Verify data exists**:
```sql
-- Check task_instance data
SELECT dag_id, task_id, COUNT(*) 
FROM task_instance 
WHERE state = 'success' 
  AND end_date >= NOW() - INTERVAL '14 days'
GROUP BY dag_id, task_id
HAVING COUNT(*) >= 20;
```

---

## 📈 Performance Considerations

### Execution Time

- **Extract**: ~1-5 seconds (depends on task_instance table size)
- **Compute**: ~1-2 seconds (in-memory calculation)
- **Upsert**: ~1-3 seconds (batch insert)
- **Total**: ~5-10 seconds for typical workload

### Database Load

- **Read**: Single query on `task_instance` table
- **Write**: Batch upsert (one query for all baselines)
- **Impact**: Minimal (runs at 2 AM during low traffic)

### Optimization Tips

1. **Add index on task_instance**:
```sql
CREATE INDEX IF NOT EXISTS ix_task_instance_baseline_lookup
ON task_instance(state, end_date DESC)
WHERE state = 'success';
```

2. **Partition task_baseline table** (for large datasets):
```sql
-- Partition by as_of_date (monthly)
CREATE TABLE task_baseline_2025_02 PARTITION OF task_baseline
FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');
```

---

## 🎯 Next Steps

### 1. Create SLA Monitoring DAG

Create a companion DAG to monitor running tasks against baselines:

```python
@dag(
    dag_id="sla_monitor_realtime",
    schedule="*/5 * * * *",  # Every 5 minutes
    ...
)
def sla_monitor_realtime():
    # Query running tasks
    # Compare against baselines
    # Update sla_current_status
    # Trigger alerts on WARN/BREACH
    pass
```

### 2. Create Grafana Dashboard

Create dashboard showing:
- Latest baselines per task
- Baseline trends over time
- Tasks without baselines
- Recommended SLA values

### 3. Implement SLA Policies

Populate `sla_policy` table:
```sql
INSERT INTO sla_policy (dag_id, task_id, mode, buffer_percent, is_enabled)
SELECT 
    dag_id,
    task_id,
    'P95_PLUS_BUFFER' as mode,
    0.15 as buffer_percent,
    true as is_enabled
FROM v_latest_task_baseline;
```

---

## 📚 Related Documentation

- **[GRAFANA_DASHBOARDS.md](GRAFANA_DASHBOARDS.md)**: Grafana dashboard documentation
- **[init-airflow-extension.sql](k8s/database/init-airflow-extension.sql)**: Database schema
- **[DEPLOYMENT.md](DEPLOYMENT.md)**: Deployment guide

---

## 🔗 References

- [Airflow TaskFlow API](https://airflow.apache.org/docs/apache-airflow/stable/tutorial/taskflow.html)
- [PostgreSQL Percentile Functions](https://www.postgresql.org/docs/current/functions-aggregate.html)
- [Kubernetes ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
