# Airflow 3.x Database Schema Validation

## ✅ Validated Queries in Dashboard

### DAG Table Queries
All queries use correct Airflow 3.x schema:

1. **Total DAGs (All)**
   ```sql
   SELECT COUNT(*) FROM dag WHERE bundle_name IS NOT NULL;
   ```
   ✅ Correct - No `is_active` column in Airflow 3.x

2. **Total DAGs (Active)**
   ```sql
   SELECT COUNT(*) FROM dag WHERE is_paused = false AND bundle_name IS NOT NULL;
   ```
   ✅ Correct - Uses `is_paused` instead of `is_active`

3. **Paused DAGs**
   ```sql
   SELECT COUNT(*) FROM dag WHERE is_paused = true AND bundle_name IS NOT NULL;
   ```
   ✅ Correct

4. **DAG List Table**
   ```sql
   SELECT 
     dag_id, 
     is_paused, 
     bundle_name, 
     last_parsed_time, 
     fileloc, 
     last_expired
   FROM dag 
   WHERE bundle_name IS NOT NULL
   ORDER BY dag_id;
   ```
   ✅ Correct - All columns exist in Airflow 3.x

### DAG Run Table Queries

5. **Running DAGs**
   ```sql
   SELECT COUNT(DISTINCT dag_id) FROM dag_run WHERE state = 'running';
   ```
   ✅ Correct - Uses DISTINCT to count unique DAGs

6. **Queued DAGs**
   ```sql
   SELECT COUNT(DISTINCT dag_id) FROM dag_run WHERE state = 'queued';
   ```
   ✅ Correct

7. **Success DAGs (24h)**
   ```sql
   SELECT COUNT(DISTINCT dag_id) FROM dag_run 
   WHERE state = 'success' AND start_date > NOW() - INTERVAL '24 hours';
   ```
   ✅ Correct - Uses `start_date` instead of `execution_date`

8. **Failed DAGs (24h)**
   ```sql
   SELECT COUNT(DISTINCT dag_id) FROM dag_run 
   WHERE state = 'failed' AND start_date > NOW() - INTERVAL '24 hours';
   ```
   ✅ Correct

9. **Recent DAG Runs Table**
   ```sql
   SELECT 
     dag_id,
     run_id,
     state,
     logical_date,  -- ✅ Correct: Uses logical_date instead of execution_date
     start_date,
     end_date,
     EXTRACT(EPOCH FROM (COALESCE(end_date, NOW()) - start_date)) as "Duration (s)"
   FROM dag_run 
   WHERE start_date > NOW() - INTERVAL '24 hours'
   ORDER BY start_date DESC
   LIMIT 100;
   ```
   ✅ Correct - Uses `logical_date` and `start_date`

### Task Instance Table Queries

10. **Total Tasks (24h)**
    ```sql
    SELECT COUNT(*) FROM task_instance 
    WHERE start_date > NOW() - INTERVAL '24 hours';
    ```
    ✅ Correct - Uses `start_date` (no `execution_date` in task_instance)

11. **Running Tasks**
    ```sql
    SELECT COUNT(*) FROM task_instance WHERE state = 'running';
    ```
    ✅ Correct

12. **Queued Tasks**
    ```sql
    SELECT COUNT(*) FROM task_instance WHERE state = 'queued';
    ```
    ✅ Correct

13. **Success Tasks (24h)**
    ```sql
    SELECT COUNT(*) FROM task_instance 
    WHERE state = 'success' AND start_date > NOW() - INTERVAL '24 hours';
    ```
    ✅ Correct

14. **Failed Tasks (24h)**
    ```sql
    SELECT COUNT(*) FROM task_instance 
    WHERE state = 'failed' AND start_date > NOW() - INTERVAL '24 hours';
    ```
    ✅ Correct

## 📋 Schema Changes from Airflow 2.x to 3.x

### `dag` table
- ❌ Removed: `is_active` column
- ✅ Use instead: `bundle_name IS NOT NULL` to check if DAG exists
- ✅ Use: `is_paused` to check if DAG is active/paused

### `dag_run` table
- ❌ Removed: `execution_date` column
- ✅ Use instead: `logical_date` for logical execution date
- ✅ Use: `start_date` for filtering by time

### `task_instance` table
- ❌ Never had: `execution_date` or `logical_date`
- ✅ Use: `start_date` and `end_date` only

## ✅ All Queries Validated

All 14 SQL queries in the Airflow DAGs Dashboard are **100% compatible** with Airflow 3.x schema.

No changes needed! 🎉
