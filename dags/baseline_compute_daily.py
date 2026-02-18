"""
Baseline Computation DAG
========================
Purpose: Calculate performance baselines for all DAG tasks daily
- Extracts task execution history from Airflow metadata database
- Computes percentile statistics (p50, p90, p95, p99)
- Stores baselines in airflow_extension database for SLA monitoring

Schedule: Daily at 2:00 AM Bangkok time
Window: 14 days of historical data
Min Samples: 20 successful task runs required
"""
from __future__ import annotations
from datetime import timedelta
from typing import Dict, Any, List
import pendulum
from airflow.decorators import dag, task
from airflow.providers.postgres.hooks.postgres import PostgresHook

# Connection IDs
META_CONN_ID = "airflow_metadata"  # Airflow metadata database (same instance)
EXT_CONN_ID = "airflow_extension"  # Airflow extension database (same instance)


@dag(
    dag_id="baseline_compute_daily",
    start_date=pendulum.datetime(2025, 1, 1, tz="Asia/Bangkok"),
    schedule="0 2 * * *",  # Daily at 2:00 AM
    catchup=False,
    max_active_runs=1,
    tags=["baseline", "sla", "monitoring"],
    doc_md=__doc__,
    default_args={
        "owner": "airflow",
        "retries": 2,
        "retry_delay": timedelta(minutes=5),
    },
)
def baseline_compute_daily():
    """
    Daily baseline computation workflow
    """
    # Configuration
    WINDOW_DAYS = 14  # Look back 14 days
    MIN_SAMPLES = 20  # Minimum 20 successful runs required
    BASELINE_KEY = "default"  # Baseline context key
    BUFFER_PERCENT = 0.15  # Recommended SLA = p95 * (1 + 15%)

    def percentile(vals_sorted: List[float], p: float) -> float:
        """
        Calculate percentile from sorted values

        Args:
            vals_sorted: Sorted list of values
            p: Percentile (0-100)

        Returns:
            Percentile value
        """
        if not vals_sorted:
            return 0.0
        k = (len(vals_sorted) - 1) * (p / 100.0)
        f = int(k)
        c = min(f + 1, len(vals_sorted) - 1)
        if f == c:
            return float(vals_sorted[f])
        return float(vals_sorted[f] * (c - k) + vals_sorted[c] * (k - f))

    @task
    def extract(window_days: int) -> List[Dict[str, Any]]:
        """
        Extract task execution history from Airflow metadata database

        Args:
            window_days: Number of days to look back

        Returns:
            List of task execution records with duration
        """
        from airflow.operators.python import get_current_context

        ctx = get_current_context()
        as_of = ctx["data_interval_end"].date()

        print(f"📊 Extracting task history for {window_days} days ending {as_of}")

        meta = PostgresHook(postgres_conn_id=META_CONN_ID)

        # Query successful task instances with duration
        sql = """
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
              ORDER BY dag_id, task_id, end_date
              ; \
              """

        rows = meta.get_records(
            sql,
            parameters={"as_of": str(as_of), "window_days": window_days}
        )

        # Convert to list of dicts
        result = [
            {
                "dag_id": r[0],
                "task_id": r[1],
                "dur": float(r[2])
            }
            for r in rows
            if r[2] is not None and r[2] > 0
        ]

        print(f"✅ Extracted {len(result)} task execution records")
        return result

    @task
    def compute(
            rows: List[Dict[str, Any]],
            window_days: int,
            min_samples: int
    ) -> List[Dict[str, Any]]:
        """
        Compute baseline statistics from task execution history

        Args:
            rows: Task execution records
            window_days: Window size in days
            min_samples: Minimum number of samples required

        Returns:
            List of baseline statistics per task
        """
        from airflow.operators.python import get_current_context

        ctx = get_current_context()
        as_of = ctx["data_interval_end"].date()

        print(f"🔢 Computing baselines from {len(rows)} records")
        print(f"   Min samples required: {min_samples}")

        # Group by (dag_id, task_id)
        buckets: Dict[tuple, List[float]] = {}
        for r in rows:
            key = (r["dag_id"], r["task_id"])
            buckets.setdefault(key, []).append(r["dur"])

        print(f"   Found {len(buckets)} unique tasks")

        # Compute statistics for each task
        out = []
        skipped = 0

        for (dag_id, task_id), vals in buckets.items():
            # Skip if insufficient samples
            if len(vals) < min_samples:
                skipped += 1
                continue

            # Sort values for percentile calculation
            vals_sorted = sorted(vals)
            n = len(vals_sorted)

            # Calculate statistics
            avg = sum(vals_sorted) / n
            var = sum((x - avg) ** 2 for x in vals_sorted) / (n - 1) if n > 1 else 0.0
            std = var ** 0.5

            p50 = percentile(vals_sorted, 50)
            p90 = percentile(vals_sorted, 90)
            p95 = percentile(vals_sorted, 95)
            p99 = percentile(vals_sorted, 99)

            # Recommended SLA = p95 + buffer
            recommended = p95 * (1.0 + BUFFER_PERCENT)

            out.append({
                "dag_id": dag_id,
                "task_id": task_id,
                "baseline_key": BASELINE_KEY,
                "window_days": window_days,
                "as_of_date": str(as_of),
                "samples": n,
                "avg_seconds": avg,
                "p50_seconds": p50,
                "p90_seconds": p90,
                "p95_seconds": p95,
                "p99_seconds": p99,
                "stddev_seconds": std,
                "recommended_sla_seconds": recommended,
            })

        print(f"✅ Computed {len(out)} baselines")
        print(f"⚠️  Skipped {skipped} tasks (insufficient samples)")

        return out

    @task
    def upsert(baselines: List[Dict[str, Any]]) -> Dict[str, int]:
        """
        Upsert baselines into airflow_extension database

        Args:
            baselines: List of baseline statistics

        Returns:
            Summary of upsert operation
        """
        if not baselines:
            print("⚠️  No baselines to upsert")
            return {"inserted": 0, "updated": 0, "total": 0}

        print(f"💾 Upserting {len(baselines)} baselines to database")

        ext = PostgresHook(postgres_conn_id=EXT_CONN_ID)

        # Upsert query with conflict resolution
        sql = """
              INSERT INTO task_baseline (
                  dag_id, task_id, baseline_key, window_days, as_of_date, samples,
                  avg_seconds, p50_seconds, p90_seconds, p95_seconds, p99_seconds,
                  stddev_seconds, recommended_sla_seconds, updated_at
              ) VALUES (
                           %(dag_id)s, %(task_id)s, %(baseline_key)s, %(window_days)s, %(as_of_date)s, %(samples)s,
                           %(avg_seconds)s, %(p50_seconds)s, %(p90_seconds)s, %(p95_seconds)s, %(p99_seconds)s,
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
                                 updated_at = now()
              ; \
              """

        # Execute batch insert/update
        ext.run(sql, parameters=baselines)

        print(f"✅ Successfully upserted {len(baselines)} baselines")

        # Print sample statistics
        if baselines:
            print("\n📊 Sample baselines:")
            for b in baselines[:5]:  # Show first 5
                print(f"   {b['dag_id']}.{b['task_id']}: "
                      f"p95={b['p95_seconds']:.1f}s, "
                      f"recommended_sla={b['recommended_sla_seconds']:.1f}s, "
                      f"samples={b['samples']}")
            if len(baselines) > 5:
                print(f"   ... and {len(baselines) - 5} more")

        return {
            "inserted": len(baselines),
            "updated": 0,  # Can't distinguish in ON CONFLICT
            "total": len(baselines)
        }

    @task
    def report(summary: Dict[str, int]) -> None:
        """
        Print summary report
        
        Args:
            summary: Upsert operation summary
        """
        print("\n" + "=" * 60)
        print("📊 Baseline Computation Summary")
        print("=" * 60)
        print(f"Total baselines processed: {summary['total']}")
        print(f"Window: {WINDOW_DAYS} days")
        print(f"Min samples: {MIN_SAMPLES}")
        print(f"Buffer: {BUFFER_PERCENT * 100:.0f}%")
        print("=" * 60)

    # Define task dependencies
    rows = extract(WINDOW_DAYS)
    baselines = compute(rows, WINDOW_DAYS, MIN_SAMPLES)
    summary = upsert(baselines)
    report(summary)


# Instantiate DAG
baseline_compute_daily()
