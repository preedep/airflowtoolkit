# Grafana Dashboards Documentation

[🇹🇭 ภาษาไทย](#ภาษาไทย) | [🇬🇧 English](#english)

---

## ภาษาไทย

### 📊 ภาพรวม Grafana Dashboards

ระบบมี **7 Dashboards** สำหรับ monitoring Airflow จากมุมมองต่างๆ โดยใช้ข้อมูลจาก 2 แหล่ง:
- **Prometheus Metrics** - Real-time metrics จาก StatsD Exporter
- **PostgreSQL Database** - ข้อมูลจาก Airflow metadata database (Airflow 3.x schema)

---

### 1️⃣ Airflow Metrics Dashboard

**วัตถุประสงค์**: ติดตาม real-time metrics จาก Prometheus

**Data Source**: Prometheus

**Panels หลัก**:

| Panel | Metric | คำอธิบาย |
|-------|--------|----------|
| Scheduler Heartbeat | `airflow_scheduler_heartbeat` | ตรวจสอบว่า scheduler ทำงานปกติ |
| Executor Slots (Open) | `airflow_executor_open_slots` | จำนวน slots ว่างสำหรับรัน tasks |
| Executor Slots (Used) | `airflow_executor_running_tasks` | จำนวน tasks ที่กำลังรัน |
| Task Queue | `airflow_executor_queued_tasks` | จำนวน tasks ที่รอในคิว |
| DAG Processing Time | `airflow_dagbag_size`, `airflow_dag_processing_total_parse_time` | เวลาที่ใช้ parse DAG files |
| Task Success Rate | `airflow_ti_successes` | อัตราความสำเร็จของ tasks แยกตาม DAG |
| Task Failure Rate | `airflow_ti_failures` | อัตราความล้มเหลวของ tasks แยกตาม DAG |

**ไม่มี SQL queries** - ใช้ PromQL เท่านั้น

---

### 2️⃣ Airflow DAGs Dashboard

**วัตถุประสงค์**: ภาพรวมสถานะ DAGs และ Tasks จาก database

**Data Source**: Airflow PostgreSQL

**Panels และ SQL Queries**:

#### 📈 Statistics Panels

```sql
-- Total DAGs (All)
SELECT COUNT(*) as "Total DAGs" 
FROM dag 
WHERE bundle_name IS NOT NULL;

-- Total DAGs (Active)
SELECT COUNT(*) as "Active DAGs" 
FROM dag 
WHERE is_paused = false AND bundle_name IS NOT NULL;

-- Running DAGs
SELECT COUNT(DISTINCT dag_id) as "Running DAGs" 
FROM dag_run 
WHERE state = 'running';

-- Queued DAGs
SELECT COUNT(DISTINCT dag_id) as "Queued DAGs" 
FROM dag_run 
WHERE state = 'queued';

-- Success DAGs (24h)
SELECT COUNT(DISTINCT dag_id) as "Success DAGs" 
FROM dag_run 
WHERE state = 'success' AND start_date > NOW() - INTERVAL '24 hours';

-- Failed DAGs (24h)
SELECT COUNT(DISTINCT dag_id) as "Failed DAGs" 
FROM dag_run 
WHERE state = 'failed' AND start_date > NOW() - INTERVAL '24 hours';

-- Paused DAGs
SELECT COUNT(*) as "Paused DAGs" 
FROM dag 
WHERE is_paused = true AND bundle_name IS NOT NULL;

-- Total Tasks (24h)
SELECT COUNT(*) as "Total Tasks" 
FROM task_instance 
WHERE start_date > NOW() - INTERVAL '24 hours';

-- Running Tasks
SELECT COUNT(*) as "Running Tasks" 
FROM task_instance 
WHERE state = 'running';

-- Queued Tasks
SELECT COUNT(*) as "Queued Tasks" 
FROM task_instance 
WHERE state = 'queued';

-- Success Tasks (24h)
SELECT COUNT(*) as "Success Tasks" 
FROM task_instance 
WHERE state = 'success' AND start_date > NOW() - INTERVAL '24 hours';

-- Failed Tasks (24h)
SELECT COUNT(*) as "Failed Tasks" 
FROM task_instance 
WHERE state = 'failed' AND start_date > NOW() - INTERVAL '24 hours';
```

#### 📋 DAG List Table

```sql
SELECT 
  dag_id as "DAG ID",
  is_paused as "Paused",
  bundle_name as "Bundle",
  last_parsed_time as "Last Parsed",
  fileloc as "File Location",
  last_expired as "Last Expired"
FROM dag 
WHERE bundle_name IS NOT NULL
ORDER BY dag_id;
```

#### 🕐 Recent DAG Runs (Last 24h)

```sql
SELECT 
  dag_id as "DAG ID",
  run_id as "Run ID",
  state as "State",
  logical_date as "Logical Date",
  start_date as "Start Date",
  end_date as "End Date",
  EXTRACT(EPOCH FROM (COALESCE(end_date, NOW()) - start_date)) as "Duration (s)"
FROM dag_run 
WHERE start_date > NOW() - INTERVAL '24 hours'
ORDER BY start_date DESC
LIMIT 100;
```

**Key Changes for Airflow 3.x**:
- ใช้ `bundle_name IS NOT NULL` แทน `is_active = true`
- ใช้ `is_paused` แทน `is_active`
- ใช้ `logical_date` แทน `execution_date`

---

### 3️⃣ Airflow DAGs Status Grid

**วัตถุประสงค์**: แสดงสถานะ DAGs แบบ grid layout (80 DAGs)

**Data Source**: Airflow PostgreSQL

**SQL Query** (แต่ละ panel):

```sql
SELECT 
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM dag_run 
      WHERE dag_id = 'dag_name' 
        AND state = 'running'
    ) THEN 'Running'
    WHEN EXISTS (
      SELECT 1 FROM dag_run 
      WHERE dag_id = 'dag_name' 
        AND state = 'failed' 
        AND start_date > NOW() - INTERVAL '24 hours'
    ) THEN 'Failed'
    WHEN EXISTS (
      SELECT 1 FROM dag_run 
      WHERE dag_id = 'dag_name' 
        AND state = 'success' 
        AND start_date > NOW() - INTERVAL '24 hours'
    ) THEN 'Success'
    WHEN EXISTS (
      SELECT 1 FROM dag 
      WHERE dag_id = 'dag_name' 
        AND is_paused = true
    ) THEN 'Paused'
    ELSE 'Unknown'
  END as status;
```

**หมายเหตุ**: Dashboard นี้ใช้ static grid (80 panels) ต้อง regenerate เมื่อมี DAG เพิ่ม/ลด

---

### 4️⃣ Airflow Task Performance Dashboard

**วัตถุประสงค์**: วิเคราะห์ performance ของ tasks, retry rate, และ queue time

**Data Source**: Airflow PostgreSQL

**Panels และ SQL Queries**:

#### ⏱️ Average Task Duration (24h)

```sql
SELECT AVG(EXTRACT(EPOCH FROM (end_date - start_date))) as "Avg Duration" 
FROM task_instance 
WHERE state = 'success' 
  AND start_date > NOW() - INTERVAL '24 hours' 
  AND end_date IS NOT NULL;
```

#### 🔄 Tasks with Retries (24h)

```sql
SELECT COUNT(*) as "Tasks with Retries" 
FROM task_instance 
WHERE try_number > 1 
  AND start_date > NOW() - INTERVAL '24 hours';
```

#### ⏳ Average Queue Time (24h)

```sql
SELECT AVG(EXTRACT(EPOCH FROM (start_date - queued_dttm))) as "Avg Queue Time" 
FROM task_instance 
WHERE state IN ('success', 'failed') 
  AND start_date > NOW() - INTERVAL '24 hours' 
  AND queued_dttm IS NOT NULL;
```

#### 📊 Average Task Duration by DAG (7 days)

```sql
SELECT 
  DATE_TRUNC('hour', start_date) as time,
  dag_id,
  AVG(EXTRACT(EPOCH FROM (end_date - start_date))) as value
FROM task_instance 
WHERE state = 'success' 
  AND start_date > NOW() - INTERVAL '7 days'
  AND end_date IS NOT NULL
GROUP BY DATE_TRUNC('hour', start_date), dag_id
ORDER BY time;
```

#### 🏆 Top 10 Longest Running Tasks (24h)

```sql
SELECT 
  dag_id || '.' || task_id as "Task",
  EXTRACT(EPOCH FROM (end_date - start_date)) as "Duration"
FROM task_instance 
WHERE state = 'success' 
  AND start_date > NOW() - INTERVAL '24 hours'
  AND end_date IS NOT NULL
ORDER BY "Duration" DESC
LIMIT 10;
```

#### 🔁 Top DAGs by Retry Count (7 days)

```sql
SELECT 
  dag_id as "DAG ID",
  COUNT(*) as "Retry Count"
FROM task_instance 
WHERE try_number > 1 
  AND start_date > NOW() - INTERVAL '7 days'
GROUP BY dag_id
ORDER BY "Retry Count" DESC
LIMIT 10;
```

#### 📈 Retry Rate Trend by DAG (7 days)

```sql
SELECT 
  DATE_TRUNC('hour', start_date) as time,
  dag_id,
  (COUNT(CASE WHEN try_number > 1 THEN 1 END)::float / NULLIF(COUNT(*)::float, 0) * 100) as value
FROM task_instance 
WHERE start_date > NOW() - INTERVAL '7 days'
GROUP BY DATE_TRUNC('hour', start_date), dag_id
HAVING COUNT(*) > 0
ORDER BY time;
```

#### 📋 Recent Tasks with Retries (24h)

```sql
SELECT 
  dag_id as "DAG ID",
  task_id as "Task ID",
  run_id as "Run ID",
  try_number as "Try Number",
  state as "State",
  start_date as "Start Date",
  end_date as "End Date",
  EXTRACT(EPOCH FROM (COALESCE(end_date, NOW()) - start_date)) as "Duration (s)"
FROM task_instance 
WHERE try_number > 1 
  AND start_date > NOW() - INTERVAL '24 hours'
ORDER BY start_date DESC
LIMIT 100;
```

**หมายเหตุ**: Dashboard นี้ไม่มี SLA panels เพราะตาราง `sla_miss` ถูกลบออกใน Airflow 3.x

---

### 5️⃣ Airflow Resource Utilization & Pool Dashboard

**วัตถุประสงค์**: ติดตาม pool usage, slot allocation, และ resource utilization

**Data Source**: Airflow PostgreSQL

**Panels และ SQL Queries**:

#### 🎯 Pool Statistics

```sql
-- Total Pools
SELECT COUNT(*) as "Total Pools" FROM slot_pool;

-- Total Slots
SELECT SUM(slots) as "Total Slots" FROM slot_pool;

-- Queued Tasks
SELECT COUNT(*) as "Queued Tasks" FROM task_instance WHERE state = 'queued';

-- Running Tasks
SELECT COUNT(*) as "Running Tasks" FROM task_instance WHERE state = 'running';
```

#### 📊 Pool Utilization (%)

```sql
SELECT 
  sp.pool as metric,
  CASE 
    WHEN sp.slots = 0 THEN 0
    ELSE (COUNT(ti.task_id)::float / sp.slots::float * 100)
  END as value
FROM slot_pool sp
LEFT JOIN task_instance ti ON ti.pool = sp.pool AND ti.state = 'running'
GROUP BY sp.pool, sp.slots
ORDER BY sp.pool;
```

#### 📋 Pool Details

```sql
SELECT 
  sp.pool as "Pool",
  sp.slots as "Total Slots",
  COUNT(ti.task_id) as "Occupied Slots",
  sp.slots - COUNT(ti.task_id) as "Available Slots"
FROM slot_pool sp
LEFT JOIN task_instance ti ON ti.pool = sp.pool AND ti.state = 'running'
GROUP BY sp.pool, sp.slots
ORDER BY sp.pool;
```

#### 📈 Task Execution by Pool (7 days)

```sql
SELECT 
  DATE_TRUNC('hour', start_date) as time,
  pool,
  COUNT(*) as value
FROM task_instance 
WHERE start_date > NOW() - INTERVAL '7 days'
  AND pool IS NOT NULL
GROUP BY DATE_TRUNC('hour', start_date), pool
ORDER BY time;
```

#### 🥧 Task Distribution by Pool (24h)

```sql
SELECT 
  COALESCE(pool, 'default_pool') as metric,
  COUNT(*) as value
FROM task_instance 
WHERE start_date > NOW() - INTERVAL '24 hours'
GROUP BY pool
ORDER BY value DESC;
```

#### 🏆 Top Pools by Task Count (7 days)

```sql
SELECT 
  COALESCE(pool, 'default_pool') as "Pool",
  COUNT(*) as "Task Count"
FROM task_instance 
WHERE start_date > NOW() - INTERVAL '7 days'
GROUP BY pool
ORDER BY "Task Count" DESC
LIMIT 10;
```

#### ⏳ Queued Tasks Details

```sql
SELECT 
  dag_id as "DAG ID",
  task_id as "Task ID",
  COALESCE(pool, 'default_pool') as "Pool",
  priority_weight as "Priority Weight",
  state as "State",
  queued_dttm as "Queued Time",
  EXTRACT(EPOCH FROM (NOW() - queued_dttm)) as "Wait Time (s)"
FROM task_instance 
WHERE state = 'queued'
ORDER BY priority_weight DESC, queued_dttm ASC
LIMIT 50;
```

---

### 6️⃣ Airflow Error & Debugging Dashboard

**วัตถุประสงค์**: ติดตาม errors, failures, และ import errors

**Data Source**: Airflow PostgreSQL

**Panels และ SQL Queries**:

#### ❌ Error Statistics

```sql
-- Failed Tasks (24h)
SELECT COUNT(*) as "Failed Tasks" 
FROM task_instance 
WHERE state = 'failed' 
  AND start_date > NOW() - INTERVAL '24 hours';

-- Failed DAG Runs (24h)
SELECT COUNT(*) as "Failed DAG Runs" 
FROM dag_run 
WHERE state = 'failed' 
  AND start_date > NOW() - INTERVAL '24 hours';

-- Import Errors
SELECT COUNT(*) as "Import Errors" FROM import_error;

-- Upstream Failed Tasks (24h)
SELECT COUNT(*) as "Upstream Failed" 
FROM task_instance 
WHERE state = 'upstream_failed' 
  AND start_date > NOW() - INTERVAL '24 hours';
```

#### 📊 Task Failure Trend (7 days)

```sql
SELECT 
  DATE_TRUNC('hour', start_date) as time,
  dag_id,
  COUNT(*) as value
FROM task_instance 
WHERE state = 'failed' 
  AND start_date > NOW() - INTERVAL '7 days'
GROUP BY DATE_TRUNC('hour', start_date), dag_id
ORDER BY time;
```

#### 🏆 Top Failed Tasks by DAG (7 days)

```sql
SELECT 
  dag_id as "DAG ID",
  COUNT(*) as "Failure Count"
FROM task_instance 
WHERE state = 'failed' 
  AND start_date > NOW() - INTERVAL '7 days'
GROUP BY dag_id
ORDER BY "Failure Count" DESC
LIMIT 10;
```

#### 📋 Recent Failed Tasks (24h)

```sql
SELECT 
  dag_id as "DAG ID",
  task_id as "Task ID",
  run_id as "Run ID",
  try_number as "Try Number",
  start_date as "Start Date",
  end_date as "End Date",
  EXTRACT(EPOCH FROM (COALESCE(end_date, NOW()) - start_date)) as "Duration (s)"
FROM task_instance 
WHERE state = 'failed' 
  AND start_date > NOW() - INTERVAL '24 hours'
ORDER BY start_date DESC
LIMIT 100;
```

#### 🐛 Import Errors

```sql
SELECT 
  timestamp as "Timestamp",
  filename as "Filename",
  stacktrace as "Error Message"
FROM import_error 
ORDER BY timestamp DESC
LIMIT 50;
```

#### 📊 DAG Failure Rate (7 days)

```sql
SELECT 
  dag_id as "DAG ID",
  COUNT(CASE WHEN state = 'failed' THEN 1 END) as "Failed",
  COUNT(CASE WHEN state = 'success' THEN 1 END) as "Success",
  ROUND(
    (COUNT(CASE WHEN state = 'failed' THEN 1 END)::float / 
     NULLIF(COUNT(*)::float, 0) * 100)::numeric, 2
  ) as "Failure Rate (%)"
FROM dag_run 
WHERE start_date > NOW() - INTERVAL '7 days'
GROUP BY dag_id
HAVING COUNT(*) > 0
ORDER BY "Failure Rate (%)" DESC
LIMIT 20;
```

---

### 7️⃣ Airflow DAG Dependencies & Lineage Dashboard

**วัตถุประสงค์**: ติดตาม DAG dependencies, asset relationships, และ task lineage

**Data Source**: Airflow PostgreSQL

**Panels และ SQL Queries**:

#### 📊 Overview Statistics

```sql
-- Total DAGs
SELECT COUNT(DISTINCT dag_id) as "Total DAGs" 
FROM dag 
WHERE bundle_name IS NOT NULL;

-- Total Task Instances (24h)
SELECT COUNT(*) as "Total Tasks" 
FROM task_instance 
WHERE start_date > NOW() - INTERVAL '24 hours';

-- DAGs with Asset Dependencies
SELECT COUNT(DISTINCT dag_id) as "DAGs with Asset Dependencies" 
FROM dag_schedule_asset_reference;

-- Total Assets
SELECT COUNT(DISTINCT id) as "Total Assets" FROM asset;
```

#### 🔗 DAG Complexity (by Task Count)

```sql
SELECT 
  dag_id as "DAG ID",
  COUNT(DISTINCT task_id) as "Task Count",
  is_paused as "Paused",
  schedule_interval as "Schedule",
  tags::text as "Tags"
FROM dag d
LEFT JOIN (
  SELECT DISTINCT dag_id, task_id 
  FROM task_instance 
  WHERE start_date > NOW() - INTERVAL '7 days'
) ti ON d.dag_id = ti.dag_id
WHERE d.bundle_name IS NOT NULL
GROUP BY d.dag_id, d.is_paused, d.schedule_interval, d.tags
ORDER BY "Task Count" DESC
LIMIT 20;
```

#### 📊 Task Operator Distribution (7 days)

```sql
SELECT 
  operator as "Operator Type",
  COUNT(*) as "Usage Count"
FROM task_instance 
WHERE start_date > NOW() - INTERVAL '7 days'
  AND operator IS NOT NULL
GROUP BY operator
ORDER BY "Usage Count" DESC
LIMIT 15;
```

#### 🗄️ Asset Registry

```sql
SELECT 
  a.id as "Asset ID",
  a.uri as "URI",
  a.name as "Name",
  a.group as "Group",
  a.created_at as "Created At",
  a.updated_at as "Updated At"
FROM asset a
ORDER BY a.updated_at DESC NULLS LAST
LIMIT 20;
```

#### 🔗 DAG Asset Dependencies

```sql
SELECT 
  dsar.dag_id as "DAG ID",
  a.uri as "Asset URI",
  a.name as "Asset Name",
  dsar.created_at as "Created At"
FROM dag_schedule_asset_reference dsar
JOIN asset a ON dsar.asset_id = a.id
ORDER BY dsar.dag_id, a.uri
LIMIT 50;
```

#### 📈 Asset Update Events (7 days)

```sql
SELECT 
  DATE_TRUNC('hour', ae.timestamp) as time,
  a.uri as metric,
  COUNT(*) as value
FROM asset_event ae
JOIN asset a ON ae.asset_id = a.id
WHERE ae.timestamp > NOW() - INTERVAL '7 days'
GROUP BY DATE_TRUNC('hour', ae.timestamp), a.uri
ORDER BY time;
```

#### 🥧 DAGs by Tags

```sql
SELECT 
  COALESCE(tags::text, 'No Tags') as metric,
  COUNT(*) as value
FROM dag 
WHERE bundle_name IS NOT NULL
GROUP BY tags::text
ORDER BY value DESC
LIMIT 10;
```

#### 📋 Task Execution Summary (7 days)

```sql
SELECT 
  dag_id as "DAG ID",
  task_id as "Task ID",
  operator as "Operator",
  COUNT(*) as "Execution Count",
  COUNT(CASE WHEN state = 'success' THEN 1 END) as "Success",
  COUNT(CASE WHEN state = 'failed' THEN 1 END) as "Failed",
  ROUND(AVG(EXTRACT(EPOCH FROM (end_date - start_date)))::numeric, 2) as "Avg Duration (s)"
FROM task_instance 
WHERE start_date > NOW() - INTERVAL '7 days'
  AND end_date IS NOT NULL
GROUP BY dag_id, task_id, operator
ORDER BY "Execution Count" DESC
LIMIT 50;
```

#### 📊 Asset Activity (7 days)

```sql
SELECT 
  a.uri as "Asset URI",
  a.name as "Asset Name",
  COUNT(ae.id) as "Event Count",
  MAX(ae.timestamp) as "Last Updated"
FROM asset a
LEFT JOIN asset_event ae ON a.id = ae.asset_id
WHERE ae.timestamp > NOW() - INTERVAL '7 days' OR ae.timestamp IS NULL
GROUP BY a.uri, a.name
ORDER BY "Event Count" DESC NULLS LAST
LIMIT 30;
```

**Key Changes for Airflow 3.x**:
- ใช้ `asset` แทน `dataset`
- ใช้ `asset_event` แทน `dataset_event`
- ใช้ `dag_schedule_asset_reference` แทน `dag_schedule_dataset_reference`

---

### 🎨 Grid Layout Options

#### ปัญหา
Grafana Table Panel แสดงเป็นตารางแนวตั้ง ไม่ใช่ grid แนวนอนแบบที่ต้องการ

#### ตัวเลือกที่มี

**1. ✅ Static Grid (ปัจจุบัน - ใช้งานได้)**
- สร้าง 80 panels แยกกัน (1 panel ต่อ 1 DAG)
- แสดงเป็น grid layout สวยงาม
- **ข้อเสีย**: ต้อง regenerate เมื่อมี DAG เพิ่ม/ลด

**2. ❌ Dynamic Table (ทดสอบแล้ว - ไม่เป็น grid)**
- ใช้ 1 panel query จาก database
- Dynamic 100% ไม่ต้อง regenerate
- **ข้อเสีย**: แสดงเป็นตารางแนวตั้ง ไม่ใช่ grid

**3. 🔄 Hybrid: Dynamic + Auto-regenerate (แนะนำ)**
- ใช้ static grid panels
- มี script auto-regenerate เมื่อ detect DAG เพิ่ม/ลด
- Run เป็น CronJob ใน Kubernetes (เช่น ทุก 5 นาที)
- **ข้อดี**: ได้ทั้ง grid layout และ dynamic

**4. 🎨 Bar Gauge Grid (ทางเลือก)**
- ใช้ Bar Gauge panel แทน Stat panel
- แสดงเป็นแถบสีแนวนอน
- Dynamic query ได้
- **ข้อเสีย**: ไม่เหมือน grid ในรูปที่ต้องการ 100%

**5. 🔌 Grafana Plugin (ต้องติดตั้งเพิ่ม)**
- ใช้ plugin เช่น "Discrete Panel" หรือ "Status Panel"
- รองรับ grid layout + dynamic query
- **ข้อเสีย**: ต้องติดตั้ง plugin เพิ่ม

#### 💡 คำแนะนำ

**สำหรับ Production**: ใช้ตัวเลือก #3 (Hybrid)
- Grid layout สวยงาม ✅
- Auto-update เมื่อมี DAG เพิ่ม/ลด ✅
- ไม่ต้อง manual regenerate ✅

**สำหรับ Testing**: ใช้ตัวเลือก #1 (Static Grid)
- ใช้งานได้ทันที
- Regenerate ด้วยมือเมื่อจำเป็น

---

### 🔑 สรุปความแตกต่าง Airflow 3.x Schema

การเปลี่ยนแปลงสำคัญที่ต้องระวังเมื่อเขียน SQL queries:

| Airflow 2.x | Airflow 3.x | หมายเหตุ |
|-------------|-------------|----------|
| `is_active` | `bundle_name IS NOT NULL` | ตรวจสอบว่า DAG มีอยู่จริง |
| `is_active = true` | `is_paused = false` | ตรวจสอบว่า DAG ไม่ pause |
| `execution_date` | `logical_date` | ใน `dag_run` table |
| `dataset` | `asset` | เปลี่ยนชื่อตาราง |
| `dataset_event` | `asset_event` | เปลี่ยนชื่อตาราง |
| `dag_schedule_dataset_reference` | `dag_schedule_asset_reference` | เปลี่ยนชื่อตาราง |
| `sla_miss` | ❌ **ถูกลบออก** | ไม่มีตารางนี้แล้ว |

---

## English

### 📊 Grafana Dashboards Overview

The system includes **7 Dashboards** for monitoring Airflow from different perspectives, using data from 2 sources:
- **Prometheus Metrics** - Real-time metrics from StatsD Exporter
- **PostgreSQL Database** - Data from Airflow metadata database (Airflow 3.x schema)

---

### 1️⃣ Airflow Metrics Dashboard

**Purpose**: Monitor real-time metrics from Prometheus

**Data Source**: Prometheus

**Main Panels**:

| Panel | Metric | Description |
|-------|--------|-------------|
| Scheduler Heartbeat | `airflow_scheduler_heartbeat` | Check if scheduler is running normally |
| Executor Slots (Open) | `airflow_executor_open_slots` | Number of available slots for running tasks |
| Executor Slots (Used) | `airflow_executor_running_tasks` | Number of currently running tasks |
| Task Queue | `airflow_executor_queued_tasks` | Number of tasks waiting in queue |
| DAG Processing Time | `airflow_dagbag_size`, `airflow_dag_processing_total_parse_time` | Time spent parsing DAG files |
| Task Success Rate | `airflow_ti_successes` | Task success rate by DAG |
| Task Failure Rate | `airflow_ti_failures` | Task failure rate by DAG |

**No SQL queries** - Uses PromQL only

---

### 2️⃣ Airflow DAGs Dashboard

**Purpose**: Overview of DAG and Task status from database

**Data Source**: Airflow PostgreSQL

**Panels and SQL Queries**:

#### 📈 Statistics Panels

```sql
-- Total DAGs (All)
SELECT COUNT(*) as "Total DAGs" 
FROM dag 
WHERE bundle_name IS NOT NULL;

-- Total DAGs (Active)
SELECT COUNT(*) as "Active DAGs" 
FROM dag 
WHERE is_paused = false AND bundle_name IS NOT NULL;

-- Running DAGs
SELECT COUNT(DISTINCT dag_id) as "Running DAGs" 
FROM dag_run 
WHERE state = 'running';

-- Queued DAGs
SELECT COUNT(DISTINCT dag_id) as "Queued DAGs" 
FROM dag_run 
WHERE state = 'queued';

-- Success DAGs (24h)
SELECT COUNT(DISTINCT dag_id) as "Success DAGs" 
FROM dag_run 
WHERE state = 'success' AND start_date > NOW() - INTERVAL '24 hours';

-- Failed DAGs (24h)
SELECT COUNT(DISTINCT dag_id) as "Failed DAGs" 
FROM dag_run 
WHERE state = 'failed' AND start_date > NOW() - INTERVAL '24 hours';

-- Paused DAGs
SELECT COUNT(*) as "Paused DAGs" 
FROM dag 
WHERE is_paused = true AND bundle_name IS NOT NULL;

-- Total Tasks (24h)
SELECT COUNT(*) as "Total Tasks" 
FROM task_instance 
WHERE start_date > NOW() - INTERVAL '24 hours';

-- Running Tasks
SELECT COUNT(*) as "Running Tasks" 
FROM task_instance 
WHERE state = 'running';

-- Queued Tasks
SELECT COUNT(*) as "Queued Tasks" 
FROM task_instance 
WHERE state = 'queued';

-- Success Tasks (24h)
SELECT COUNT(*) as "Success Tasks" 
FROM task_instance 
WHERE state = 'success' AND start_date > NOW() - INTERVAL '24 hours';

-- Failed Tasks (24h)
SELECT COUNT(*) as "Failed Tasks" 
FROM task_instance 
WHERE state = 'failed' AND start_date > NOW() - INTERVAL '24 hours';
```

#### 📋 DAG List Table

```sql
SELECT 
  dag_id as "DAG ID",
  is_paused as "Paused",
  bundle_name as "Bundle",
  last_parsed_time as "Last Parsed",
  fileloc as "File Location",
  last_expired as "Last Expired"
FROM dag 
WHERE bundle_name IS NOT NULL
ORDER BY dag_id;
```

#### 🕐 Recent DAG Runs (Last 24h)

```sql
SELECT 
  dag_id as "DAG ID",
  run_id as "Run ID",
  state as "State",
  logical_date as "Logical Date",
  start_date as "Start Date",
  end_date as "End Date",
  EXTRACT(EPOCH FROM (COALESCE(end_date, NOW()) - start_date)) as "Duration (s)"
FROM dag_run 
WHERE start_date > NOW() - INTERVAL '24 hours'
ORDER BY start_date DESC
LIMIT 100;
```

**Key Changes for Airflow 3.x**:
- Use `bundle_name IS NOT NULL` instead of `is_active = true`
- Use `is_paused` instead of `is_active`
- Use `logical_date` instead of `execution_date`

---

### 3️⃣ Airflow DAGs Status Grid

**Purpose**: Display DAG status in grid layout (80 DAGs)

**Data Source**: Airflow PostgreSQL

**SQL Query** (per panel):

```sql
SELECT 
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM dag_run 
      WHERE dag_id = 'dag_name' 
        AND state = 'running'
    ) THEN 'Running'
    WHEN EXISTS (
      SELECT 1 FROM dag_run 
      WHERE dag_id = 'dag_name' 
        AND state = 'failed' 
        AND start_date > NOW() - INTERVAL '24 hours'
    ) THEN 'Failed'
    WHEN EXISTS (
      SELECT 1 FROM dag_run 
      WHERE dag_id = 'dag_name' 
        AND state = 'success' 
        AND start_date > NOW() - INTERVAL '24 hours'
    ) THEN 'Success'
    WHEN EXISTS (
      SELECT 1 FROM dag 
      WHERE dag_id = 'dag_name' 
        AND is_paused = true
    ) THEN 'Paused'
    ELSE 'Unknown'
  END as status;
```

**Note**: This dashboard uses static grid (80 panels) and needs regeneration when DAGs are added/removed

---

### 4️⃣ Airflow Task Performance Dashboard

**Purpose**: Analyze task performance, retry rate, and queue time

**Data Source**: Airflow PostgreSQL

**Panels and SQL Queries**:

#### ⏱️ Average Task Duration (24h)

```sql
SELECT AVG(EXTRACT(EPOCH FROM (end_date - start_date))) as "Avg Duration" 
FROM task_instance 
WHERE state = 'success' 
  AND start_date > NOW() - INTERVAL '24 hours' 
  AND end_date IS NOT NULL;
```

#### 🔄 Tasks with Retries (24h)

```sql
SELECT COUNT(*) as "Tasks with Retries" 
FROM task_instance 
WHERE try_number > 1 
  AND start_date > NOW() - INTERVAL '24 hours';
```

#### ⏳ Average Queue Time (24h)

```sql
SELECT AVG(EXTRACT(EPOCH FROM (start_date - queued_dttm))) as "Avg Queue Time" 
FROM task_instance 
WHERE state IN ('success', 'failed') 
  AND start_date > NOW() - INTERVAL '24 hours' 
  AND queued_dttm IS NOT NULL;
```

#### 📊 Average Task Duration by DAG (7 days)

```sql
SELECT 
  DATE_TRUNC('hour', start_date) as time,
  dag_id,
  AVG(EXTRACT(EPOCH FROM (end_date - start_date))) as value
FROM task_instance 
WHERE state = 'success' 
  AND start_date > NOW() - INTERVAL '7 days'
  AND end_date IS NOT NULL
GROUP BY DATE_TRUNC('hour', start_date), dag_id
ORDER BY time;
```

#### 🏆 Top 10 Longest Running Tasks (24h)

```sql
SELECT 
  dag_id || '.' || task_id as "Task",
  EXTRACT(EPOCH FROM (end_date - start_date)) as "Duration"
FROM task_instance 
WHERE state = 'success' 
  AND start_date > NOW() - INTERVAL '24 hours'
  AND end_date IS NOT NULL
ORDER BY "Duration" DESC
LIMIT 10;
```

#### 🔁 Top DAGs by Retry Count (7 days)

```sql
SELECT 
  dag_id as "DAG ID",
  COUNT(*) as "Retry Count"
FROM task_instance 
WHERE try_number > 1 
  AND start_date > NOW() - INTERVAL '7 days'
GROUP BY dag_id
ORDER BY "Retry Count" DESC
LIMIT 10;
```

#### 📈 Retry Rate Trend by DAG (7 days)

```sql
SELECT 
  DATE_TRUNC('hour', start_date) as time,
  dag_id,
  (COUNT(CASE WHEN try_number > 1 THEN 1 END)::float / NULLIF(COUNT(*)::float, 0) * 100) as value
FROM task_instance 
WHERE start_date > NOW() - INTERVAL '7 days'
GROUP BY DATE_TRUNC('hour', start_date), dag_id
HAVING COUNT(*) > 0
ORDER BY time;
```

#### 📋 Recent Tasks with Retries (24h)

```sql
SELECT 
  dag_id as "DAG ID",
  task_id as "Task ID",
  run_id as "Run ID",
  try_number as "Try Number",
  state as "State",
  start_date as "Start Date",
  end_date as "End Date",
  EXTRACT(EPOCH FROM (COALESCE(end_date, NOW()) - start_date)) as "Duration (s)"
FROM task_instance 
WHERE try_number > 1 
  AND start_date > NOW() - INTERVAL '24 hours'
ORDER BY start_date DESC
LIMIT 100;
```

**Note**: This dashboard doesn't include SLA panels because the `sla_miss` table was removed in Airflow 3.x

---

### 5️⃣ Airflow Resource Utilization & Pool Dashboard

**Purpose**: Monitor pool usage, slot allocation, and resource utilization

**Data Source**: Airflow PostgreSQL

**Panels and SQL Queries**:

#### 🎯 Pool Statistics

```sql
-- Total Pools
SELECT COUNT(*) as "Total Pools" FROM slot_pool;

-- Total Slots
SELECT SUM(slots) as "Total Slots" FROM slot_pool;

-- Queued Tasks
SELECT COUNT(*) as "Queued Tasks" FROM task_instance WHERE state = 'queued';

-- Running Tasks
SELECT COUNT(*) as "Running Tasks" FROM task_instance WHERE state = 'running';
```

#### 📊 Pool Utilization (%)

```sql
SELECT 
  sp.pool as metric,
  CASE 
    WHEN sp.slots = 0 THEN 0
    ELSE (COUNT(ti.task_id)::float / sp.slots::float * 100)
  END as value
FROM slot_pool sp
LEFT JOIN task_instance ti ON ti.pool = sp.pool AND ti.state = 'running'
GROUP BY sp.pool, sp.slots
ORDER BY sp.pool;
```

#### 📋 Pool Details

```sql
SELECT 
  sp.pool as "Pool",
  sp.slots as "Total Slots",
  COUNT(ti.task_id) as "Occupied Slots",
  sp.slots - COUNT(ti.task_id) as "Available Slots"
FROM slot_pool sp
LEFT JOIN task_instance ti ON ti.pool = sp.pool AND ti.state = 'running'
GROUP BY sp.pool, sp.slots
ORDER BY sp.pool;
```

#### 📈 Task Execution by Pool (7 days)

```sql
SELECT 
  DATE_TRUNC('hour', start_date) as time,
  pool,
  COUNT(*) as value
FROM task_instance 
WHERE start_date > NOW() - INTERVAL '7 days'
  AND pool IS NOT NULL
GROUP BY DATE_TRUNC('hour', start_date), pool
ORDER BY time;
```

#### 🥧 Task Distribution by Pool (24h)

```sql
SELECT 
  COALESCE(pool, 'default_pool') as metric,
  COUNT(*) as value
FROM task_instance 
WHERE start_date > NOW() - INTERVAL '24 hours'
GROUP BY pool
ORDER BY value DESC;
```

#### 🏆 Top Pools by Task Count (7 days)

```sql
SELECT 
  COALESCE(pool, 'default_pool') as "Pool",
  COUNT(*) as "Task Count"
FROM task_instance 
WHERE start_date > NOW() - INTERVAL '7 days'
GROUP BY pool
ORDER BY "Task Count" DESC
LIMIT 10;
```

#### ⏳ Queued Tasks Details

```sql
SELECT 
  dag_id as "DAG ID",
  task_id as "Task ID",
  COALESCE(pool, 'default_pool') as "Pool",
  priority_weight as "Priority Weight",
  state as "State",
  queued_dttm as "Queued Time",
  EXTRACT(EPOCH FROM (NOW() - queued_dttm)) as "Wait Time (s)"
FROM task_instance 
WHERE state = 'queued'
ORDER BY priority_weight DESC, queued_dttm ASC
LIMIT 50;
```

---

### 6️⃣ Airflow Error & Debugging Dashboard

**Purpose**: Monitor errors, failures, and import errors

**Data Source**: Airflow PostgreSQL

**Panels and SQL Queries**:

#### ❌ Error Statistics

```sql
-- Failed Tasks (24h)
SELECT COUNT(*) as "Failed Tasks" 
FROM task_instance 
WHERE state = 'failed' 
  AND start_date > NOW() - INTERVAL '24 hours';

-- Failed DAG Runs (24h)
SELECT COUNT(*) as "Failed DAG Runs" 
FROM dag_run 
WHERE state = 'failed' 
  AND start_date > NOW() - INTERVAL '24 hours';

-- Import Errors
SELECT COUNT(*) as "Import Errors" FROM import_error;

-- Upstream Failed Tasks (24h)
SELECT COUNT(*) as "Upstream Failed" 
FROM task_instance 
WHERE state = 'upstream_failed' 
  AND start_date > NOW() - INTERVAL '24 hours';
```

#### 📊 Task Failure Trend (7 days)

```sql
SELECT 
  DATE_TRUNC('hour', start_date) as time,
  dag_id,
  COUNT(*) as value
FROM task_instance 
WHERE state = 'failed' 
  AND start_date > NOW() - INTERVAL '7 days'
GROUP BY DATE_TRUNC('hour', start_date), dag_id
ORDER BY time;
```

#### 🏆 Top Failed Tasks by DAG (7 days)

```sql
SELECT 
  dag_id as "DAG ID",
  COUNT(*) as "Failure Count"
FROM task_instance 
WHERE state = 'failed' 
  AND start_date > NOW() - INTERVAL '7 days'
GROUP BY dag_id
ORDER BY "Failure Count" DESC
LIMIT 10;
```

#### 📋 Recent Failed Tasks (24h)

```sql
SELECT 
  dag_id as "DAG ID",
  task_id as "Task ID",
  run_id as "Run ID",
  try_number as "Try Number",
  start_date as "Start Date",
  end_date as "End Date",
  EXTRACT(EPOCH FROM (COALESCE(end_date, NOW()) - start_date)) as "Duration (s)"
FROM task_instance 
WHERE state = 'failed' 
  AND start_date > NOW() - INTERVAL '24 hours'
ORDER BY start_date DESC
LIMIT 100;
```

#### 🐛 Import Errors

```sql
SELECT 
  timestamp as "Timestamp",
  filename as "Filename",
  stacktrace as "Error Message"
FROM import_error 
ORDER BY timestamp DESC
LIMIT 50;
```

#### 📊 DAG Failure Rate (7 days)

```sql
SELECT 
  dag_id as "DAG ID",
  COUNT(CASE WHEN state = 'failed' THEN 1 END) as "Failed",
  COUNT(CASE WHEN state = 'success' THEN 1 END) as "Success",
  ROUND(
    (COUNT(CASE WHEN state = 'failed' THEN 1 END)::float / 
     NULLIF(COUNT(*)::float, 0) * 100)::numeric, 2
  ) as "Failure Rate (%)"
FROM dag_run 
WHERE start_date > NOW() - INTERVAL '7 days'
GROUP BY dag_id
HAVING COUNT(*) > 0
ORDER BY "Failure Rate (%)" DESC
LIMIT 20;
```

---

### 7️⃣ Airflow DAG Dependencies & Lineage Dashboard

**Purpose**: Monitor DAG dependencies, asset relationships, and task lineage

**Data Source**: Airflow PostgreSQL

**Panels and SQL Queries**:

#### 📊 Overview Statistics

```sql
-- Total DAGs
SELECT COUNT(DISTINCT dag_id) as "Total DAGs" 
FROM dag 
WHERE bundle_name IS NOT NULL;

-- Total Task Instances (24h)
SELECT COUNT(*) as "Total Tasks" 
FROM task_instance 
WHERE start_date > NOW() - INTERVAL '24 hours';

-- DAGs with Asset Dependencies
SELECT COUNT(DISTINCT dag_id) as "DAGs with Asset Dependencies" 
FROM dag_schedule_asset_reference;

-- Total Assets
SELECT COUNT(DISTINCT id) as "Total Assets" FROM asset;
```

#### 🔗 DAG Complexity (by Task Count)

```sql
SELECT 
  dag_id as "DAG ID",
  COUNT(DISTINCT task_id) as "Task Count",
  is_paused as "Paused",
  schedule_interval as "Schedule",
  tags::text as "Tags"
FROM dag d
LEFT JOIN (
  SELECT DISTINCT dag_id, task_id 
  FROM task_instance 
  WHERE start_date > NOW() - INTERVAL '7 days'
) ti ON d.dag_id = ti.dag_id
WHERE d.bundle_name IS NOT NULL
GROUP BY d.dag_id, d.is_paused, d.schedule_interval, d.tags
ORDER BY "Task Count" DESC
LIMIT 20;
```

#### 📊 Task Operator Distribution (7 days)

```sql
SELECT 
  operator as "Operator Type",
  COUNT(*) as "Usage Count"
FROM task_instance 
WHERE start_date > NOW() - INTERVAL '7 days'
  AND operator IS NOT NULL
GROUP BY operator
ORDER BY "Usage Count" DESC
LIMIT 15;
```

#### 🗄️ Asset Registry

```sql
SELECT 
  a.id as "Asset ID",
  a.uri as "URI",
  a.name as "Name",
  a.group as "Group",
  a.created_at as "Created At",
  a.updated_at as "Updated At"
FROM asset a
ORDER BY a.updated_at DESC NULLS LAST
LIMIT 20;
```

#### 🔗 DAG Asset Dependencies

```sql
SELECT 
  dsar.dag_id as "DAG ID",
  a.uri as "Asset URI",
  a.name as "Asset Name",
  dsar.created_at as "Created At"
FROM dag_schedule_asset_reference dsar
JOIN asset a ON dsar.asset_id = a.id
ORDER BY dsar.dag_id, a.uri
LIMIT 50;
```

#### 📈 Asset Update Events (7 days)

```sql
SELECT 
  DATE_TRUNC('hour', ae.timestamp) as time,
  a.uri as metric,
  COUNT(*) as value
FROM asset_event ae
JOIN asset a ON ae.asset_id = a.id
WHERE ae.timestamp > NOW() - INTERVAL '7 days'
GROUP BY DATE_TRUNC('hour', ae.timestamp), a.uri
ORDER BY time;
```

#### 🥧 DAGs by Tags

```sql
SELECT 
  COALESCE(tags::text, 'No Tags') as metric,
  COUNT(*) as value
FROM dag 
WHERE bundle_name IS NOT NULL
GROUP BY tags::text
ORDER BY value DESC
LIMIT 10;
```

#### 📋 Task Execution Summary (7 days)

```sql
SELECT 
  dag_id as "DAG ID",
  task_id as "Task ID",
  operator as "Operator",
  COUNT(*) as "Execution Count",
  COUNT(CASE WHEN state = 'success' THEN 1 END) as "Success",
  COUNT(CASE WHEN state = 'failed' THEN 1 END) as "Failed",
  ROUND(AVG(EXTRACT(EPOCH FROM (end_date - start_date)))::numeric, 2) as "Avg Duration (s)"
FROM task_instance 
WHERE start_date > NOW() - INTERVAL '7 days'
  AND end_date IS NOT NULL
GROUP BY dag_id, task_id, operator
ORDER BY "Execution Count" DESC
LIMIT 50;
```

#### 📊 Asset Activity (7 days)

```sql
SELECT 
  a.uri as "Asset URI",
  a.name as "Asset Name",
  COUNT(ae.id) as "Event Count",
  MAX(ae.timestamp) as "Last Updated"
FROM asset a
LEFT JOIN asset_event ae ON a.id = ae.asset_id
WHERE ae.timestamp > NOW() - INTERVAL '7 days' OR ae.timestamp IS NULL
GROUP BY a.uri, a.name
ORDER BY "Event Count" DESC NULLS LAST
LIMIT 30;
```

**Key Changes for Airflow 3.x**:
- Use `asset` instead of `dataset`
- Use `asset_event` instead of `dataset_event`
- Use `dag_schedule_asset_reference` instead of `dag_schedule_dataset_reference`

---

### 🎨 Grid Layout Options

#### Problem
Grafana Table Panel displays as vertical table, not horizontal grid as desired

#### Available Options

**1. ✅ Static Grid (Current - Working)**
- Create 80 separate panels (1 panel per DAG)
- Displays as beautiful grid layout
- **Downside**: Must regenerate when DAGs are added/removed

**2. ❌ Dynamic Table (Tested - Not Grid)**
- Use 1 panel querying from database
- 100% dynamic, no regeneration needed
- **Downside**: Displays as vertical table, not grid

**3. 🔄 Hybrid: Dynamic + Auto-regenerate (Recommended)**
- Use static grid panels
- Have script auto-regenerate when detecting DAG changes
- Run as CronJob in Kubernetes (e.g., every 5 minutes)
- **Advantage**: Get both grid layout and dynamic behavior

**4. 🎨 Bar Gauge Grid (Alternative)**
- Use Bar Gauge panel instead of Stat panel
- Displays as horizontal color bars
- Can query dynamically
- **Downside**: Not 100% like desired grid

**5. 🔌 Grafana Plugin (Requires Installation)**
- Use plugins like "Discrete Panel" or "Status Panel"
- Supports grid layout + dynamic query
- **Downside**: Requires additional plugin installation

#### 💡 Recommendations

**For Production**: Use Option #3 (Hybrid)
- Beautiful grid layout ✅
- Auto-update when DAGs change ✅
- No manual regeneration needed ✅

**For Testing**: Use Option #1 (Static Grid)
- Works immediately
- Regenerate manually when necessary

---

### 🔑 Airflow 3.x Schema Changes Summary

Important changes to watch for when writing SQL queries:

| Airflow 2.x | Airflow 3.x | Notes |
|-------------|-------------|-------|
| `is_active` | `bundle_name IS NOT NULL` | Check if DAG exists |
| `is_active = true` | `is_paused = false` | Check if DAG is not paused |
| `execution_date` | `logical_date` | In `dag_run` table |
| `dataset` | `asset` | Table renamed |
| `dataset_event` | `asset_event` | Table renamed |
| `dag_schedule_dataset_reference` | `dag_schedule_asset_reference` | Table renamed |
| `sla_miss` | ❌ **Removed** | Table no longer exists |

---

## 📚 Additional Resources

- **[README.md](README.md)** - Main documentation
- **[DEPLOYMENT.md](DEPLOYMENT.md)** - Detailed deployment guide
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common issues and solutions
- **[AIRFLOW-3X-SCHEMA-VALIDATION.md](AIRFLOW-3X-SCHEMA-VALIDATION.md)** - Schema validation details
