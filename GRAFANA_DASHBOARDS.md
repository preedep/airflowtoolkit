# Grafana Dashboards Documentation

[🇹🇭 ภาษาไทย](#ภาษาไทย) | [🇬🇧 English](#english)

---

## ภาษาไทย

### 📊 ภาพรวม Grafana Dashboards

ระบบมี **9 Dashboards** สำหรับ monitoring Airflow จากมุมมองต่างๆ โดยใช้ข้อมูลจาก 2 แหล่ง:
- **Prometheus Metrics** - Real-time metrics จาก StatsD Exporter สำหรับติดตามประสิทธิภาพแบบ real-time
- **PostgreSQL Database** - ข้อมูลจาก Airflow metadata database (Airflow 3.x schema) สำหรับวิเคราะห์เชิงลึกและ historical data

---

### 1️⃣ Airflow Metrics Dashboard

**วัตถุประสงค์**: ติดตาม real-time metrics จาก Prometheus เพื่อตรวจสอบสุขภาพของระบบ Airflow แบบ real-time

**Data Source**: Prometheus

**เหตุผลในการใช้ Prometheus**: 
- ให้ข้อมูล real-time ที่อัปเดตทุก 15 วินาที
- ไม่กระทบต่อ performance ของ Airflow database
- เหมาะสำหรับการ alert และ monitoring แบบ continuous

**Panels หลัก**:

| Panel | Metric | คำอธิบาย | เหตุผลที่สำคัญ |
|-------|--------|----------|----------------|
| Scheduler Heartbeat | `airflow_scheduler_heartbeat` | ตรวจสอบว่า scheduler ทำงานปกติ | **Critical metric** - หาก scheduler หยุดทำงาน DAGs ทั้งหมดจะไม่ถูก schedule ระบบจะหยุดชะงัก |
| Executor Slots (Open) | `airflow_executor_open_slots` | จำนวน slots ว่างสำหรับรัน tasks | ใช้วางแผน capacity - ถ้า slots เหลือน้อยต้องเพิ่ม workers หรือปรับ parallelism |
| Executor Slots (Used) | `airflow_executor_running_tasks` | จำนวน tasks ที่กำลังรัน | ติดตาม utilization rate - ช่วยประเมินว่าระบบถูกใช้งานเต็มประสิทธิภาพหรือไม่ |
| Task Queue | `airflow_executor_queued_tasks` | จำนวน tasks ที่รอในคิว | **Performance indicator** - ถ้า queue สูงแสดงว่า bottleneck อาจต้องเพิ่ม resources |
| DAG Processing Time | `airflow_dagbag_size`, `airflow_dag_processing_total_parse_time` | เวลาที่ใช้ parse DAG files | ติดตาม DAG complexity - ถ้าใช้เวลานานอาจต้อง optimize DAG code |
| Task Success Rate | `airflow_ti_successes` | อัตราความสำเร็จของ tasks แยกตาม DAG | **Quality metric** - วัด reliability ของแต่ละ DAG |
| Task Failure Rate | `airflow_ti_failures` | อัตราความล้มเหลวของ tasks แยกตาม DAG | **Alert trigger** - ใช้ตั้ง alert เมื่อ failure rate สูงผิดปกติ |

**ไม่มี SQL queries** - ใช้ PromQL เท่านั้น

**Best Practices**:
- ตั้ง alert สำหรับ Scheduler Heartbeat หยุด > 1 นาที
- ตั้ง alert เมื่อ Task Queue > 100 tasks
- Monitor Task Failure Rate และสร้าง alert เมื่อเกิน threshold

---

### 2️⃣ Airflow DAGs Dashboard

**วัตถุประสงค์**: ภาพรวมสถานะ DAGs และ Tasks จาก database เพื่อวิเคราะห์ operational status และ historical trends

**Data Source**: Airflow PostgreSQL

**เหตุผลในการใช้ Database**:
- ให้ข้อมูลที่แม่นยำและ consistent จาก source of truth
- สามารถ query ข้อมูล historical ย้อนหลังได้
- รองรับการวิเคราะห์เชิงลึกด้วย SQL joins และ aggregations

**Panels และ SQL Queries**:

#### 📈 Statistics Panels

**1. Total DAGs (All)**
```sql
SELECT COUNT(*) as "Total DAGs" 
FROM dag 
WHERE bundle_name IS NOT NULL;
```

**คำอธิบาย**:
- **Column `bundle_name`**: ใน Airflow 3.x ใช้ `bundle_name IS NOT NULL` เพื่อตรวจสอบว่า DAG ถูก deploy และมีอยู่จริงในระบบ
- **เหตุผล**: แทนที่ `is_active` ใน Airflow 2.x ซึ่งถูกเปลี่ยนแปลงใน schema ใหม่
- **ความสำคัญ**: ใช้ติดตามจำนวน DAGs ทั้งหมดที่ active ในระบบ ช่วยในการวางแผน capacity และ license management

**2. Total DAGs (Active)**
```sql
SELECT COUNT(*) as "Active DAGs" 
FROM dag 
WHERE is_paused = false AND bundle_name IS NOT NULL;
```

**คำอธิบาย**:
- **Column `is_paused`**: Boolean flag ที่บอกว่า DAG ถูก pause หรือไม่
- **เหตุผล**: DAGs ที่ไม่ pause คือ DAGs ที่กำลังทำงานจริง (actively scheduling)
- **ความสำคัญ**: แยกแยะระหว่าง DAGs ที่ deploy แล้วกับ DAGs ที่กำลังทำงานจริง ช่วยในการ monitor operational workload

**3. Running DAGs**
```sql
SELECT COUNT(DISTINCT dag_id) as "Running DAGs" 
FROM dag_run 
WHERE state = 'running';
```

**คำอธิบาย**:
- **Table `dag_run`**: เก็บ execution instances ของแต่ละ DAG run
- **Column `state`**: สถานะปัจจุบันของ DAG run (running, success, failed, etc.)
- **`DISTINCT dag_id`**: นับจำนวน DAGs ที่ unique ไม่ใช่จำนวน runs (เพราะ 1 DAG อาจมีหลาย runs พร้อมกัน)
- **ความสำคัญ**: **Real-time operational metric** - บอกว่ามี DAGs กี่ตัวที่กำลังทำงานอยู่ในขณะนี้ ใช้ติดตาม concurrent execution

**4. Queued DAGs**
```sql
SELECT COUNT(DISTINCT dag_id) as "Queued DAGs" 
FROM dag_run 
WHERE state = 'queued';
```

**คำอธิบาย**:
- **State 'queued'**: DAG runs ที่รอการ execute
- **เหตุผล**: เกิดเมื่อ DAG ถูก trigger แต่ยังไม่มี resources พร้อม หรือรอ dependencies
- **ความสำคัญ**: **Bottleneck indicator** - ถ้ามี queued DAGs เยอะแสดงว่าระบบมี capacity issues หรือ dependency problems

**5. Success DAGs (24h)**
```sql
SELECT COUNT(DISTINCT dag_id) as "Success DAGs" 
FROM dag_run 
WHERE state = 'success' 
  AND start_date >= $__timeFrom() 
  AND start_date <= $__timeTo();
```

**คำอธิบาย**:
- **Column `start_date`**: เวลาที่ DAG run เริ่มทำงาน
- **`$__timeFrom()` และ `$__timeTo()`**: Grafana time range variables - ผู้ใช้เลือก time range ได้เอง
- **เหตุผล**: Flexible time window ที่ผู้ใช้กำหนดเองได้ (Last 1h, 6h, 24h, 7d, Custom)
- **ความสำคัญ**: **Success indicator** - วัด operational health ในช่วงเวลาที่เลือก ใช้ในการ reporting

**6. Failed DAGs (24h)**
```sql
SELECT COUNT(DISTINCT dag_id) as "Failed DAGs" 
FROM dag_run 
WHERE state = 'failed' 
  AND start_date >= $__timeFrom() 
  AND start_date <= $__timeTo();
```

**คำอธิบาย**:
- **State 'failed'**: DAG runs ที่ล้มเหลว
- **เหตุผล**: ใช้ time window 24h เพื่อ focus ที่ปัญหาล่าสุดที่ต้องแก้ไขด่วน
- **ความสำคัญ**: **Critical alert metric** - ต้อง investigate ทันทีเพื่อแก้ไขปัญหาก่อนกระทบ business

**7. Paused DAGs**
```sql
SELECT COUNT(*) as "Paused DAGs" 
FROM dag 
WHERE is_paused = true AND bundle_name IS NOT NULL;
```

**คำอธิบาย**:
- **เหตุผล**: DAGs ที่ pause อาจเป็น DAGs ที่กำลัง maintenance หรือ temporarily disabled
- **ความสำคัญ**: ช่วยติดตามว่ามี DAGs อะไรบ้างที่ไม่ได้ทำงาน ป้องกันการลืม unpause

**8. Total Tasks (24h)**
```sql
SELECT COUNT(*) as "Total Tasks" 
FROM task_instance 
WHERE start_date >= $__timeFrom() 
  AND start_date <= $__timeTo();
```

**คำอธิบาย**:
- **Table `task_instance`**: เก็บ execution instances ของแต่ละ task ใน DAG
- **เหตุผล**: นับทุก task executions รวมถึง retries
- **ความสำคัญ**: **Workload metric** - วัดปริมาณงานที่ระบบประมวลผลใน 24 ชั่วโมง ใช้ในการ capacity planning

**9-12. Running/Queued/Success/Failed Tasks**
```sql
-- Running Tasks
SELECT COUNT(*) as "Running Tasks" 
FROM task_instance 
WHERE state = 'running';

-- Queued Tasks
SELECT COUNT(*) as "Queued Tasks" 
FROM task_instance 
WHERE state = 'queued';

-- Success Tasks
SELECT COUNT(*) as "Success Tasks" 
FROM task_instance 
WHERE state = 'success' 
  AND start_date >= $__timeFrom() 
  AND start_date <= $__timeTo();

-- Failed Tasks
SELECT COUNT(*) as "Failed Tasks" 
FROM task_instance 
WHERE state = 'failed' 
  AND start_date >= $__timeFrom() 
  AND start_date <= $__timeTo();
```

**คำอธิบาย**:
- **Task-level granularity**: ให้รายละเอียดมากกว่า DAG-level เพราะ 1 DAG มีหลาย tasks
- **เหตุผล**: ช่วย pinpoint ปัญหาได้แม่นยำกว่า - บางครั้ง DAG success แต่บาง tasks อาจ retry หลายครั้ง
- **ความสำคัญ**: **Operational metrics** - ใช้ติดตาม task-level performance และ identify bottlenecks

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

**คำอธิบายแต่ละ Column**:

1. **`dag_id`**: Unique identifier ของ DAG
   - **เหตุผล**: Primary key สำหรับ reference และ filtering
   - **ความสำคัญ**: ใช้ในการ drill-down และ troubleshooting

2. **`is_paused`**: สถานะ pause/unpause
   - **เหตุผล**: บอกว่า DAG กำลังทำงานหรือถูก pause
   - **ความสำคัญ**: Quick visibility ของ operational status

3. **`bundle_name`**: Bundle/package ที่ DAG อยู่
   - **เหตุผล**: Airflow 3.x ใช้ bundle system สำหรับ DAG deployment
   - **ความสำคัญ**: ช่วยในการ organize และ version control DAGs

4. **`last_parsed_time`**: เวลาที่ DAG ถูก parse ครั้งล่าสุด
   - **เหตุผล**: บอกว่า scheduler อ่าน DAG file เมื่อไหร่
   - **ความสำคัญ**: **Troubleshooting metric** - ถ้า parse time เก่ามากอาจมีปัญหา DAG file ไม่ถูก refresh

5. **`fileloc`**: ตำแหน่งไฟล์ของ DAG
   - **เหตุผล**: ช่วยในการ locate source code
   - **ความสำคัญ**: ใช้เมื่อต้อง debug หรือแก้ไข DAG code

6. **`last_expired`**: เวลาที่ DAG expired
   - **เหตุผล**: ใช้ใน DAG versioning และ cleanup
   - **ความสำคัญ**: ช่วยติดตาม DAG lifecycle

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
WHERE start_date >= $__timeFrom()
  AND start_date <= $__timeTo()
ORDER BY start_date DESC
LIMIT 100;
```

**คำอธิบายแต่ละ Column**:

1. **`run_id`**: Unique identifier ของแต่ละ run
   - **เหตุผล**: ใช้ในการ reference specific execution
   - **ความสำคัญ**: Critical สำหรับ troubleshooting และ log correlation

2. **`state`**: สถานะของ run (running, success, failed, etc.)
   - **เหตุผล**: บอกผลลัพธ์ของ execution
   - **ความสำคัญ**: **Primary indicator** ของ run health

3. **`logical_date`**: วันที่ logical ของ data (เดิมชื่อ execution_date)
   - **เหตุผล**: Airflow 3.x เปลี่ยนชื่อจาก `execution_date` เพื่อความชัดเจน - นี่คือวันที่ของ data ที่ process ไม่ใช่วันที่ run จริง
   - **ความสำคัญ**: **Business context** - บอกว่า run นี้ process data ของวันไหน สำคัญสำหรับ data pipeline tracking

4. **`start_date`**: เวลาที่เริ่ม run จริง
   - **เหตุผล**: Actual execution time
   - **ความสำคัญ**: ใช้คำนวณ duration และ schedule adherence

5. **`end_date`**: เวลาที่จบ run
   - **เหตุผล**: บอกว่า run เสร็จเมื่อไหร่
   - **ความสำคัญ**: ใช้คำนวณ duration และ SLA compliance

6. **`Duration (s)`**: ระยะเวลาที่ใช้ (วินาที)
   - **Formula**: `EXTRACT(EPOCH FROM (COALESCE(end_date, NOW()) - start_date))`
   - **`COALESCE(end_date, NOW())`**: ถ้า run ยังไม่จบ ใช้เวลาปัจจุบัน
   - **`EXTRACT(EPOCH FROM ...)`**: แปลง interval เป็นวินาที
   - **ความสำคัญ**: **Performance metric** - ใช้ identify slow runs และ optimize performance

**Key Changes for Airflow 3.x**:
- ใช้ `bundle_name IS NOT NULL` แทน `is_active = true` - เพราะ schema เปลี่ยน
- ใช้ `is_paused` แทน `is_active` - ชื่อชัดเจนกว่า
- ใช้ `logical_date` แทน `execution_date` - ชื่อสื่อความหมายมากกว่า

**Best Practices**:
- Monitor Failed DAGs ทุกวัน และสร้าง runbook สำหรับ common failures
- ตั้ง alert เมื่อ Queued DAGs > threshold เพื่อ detect capacity issues
- Review Paused DAGs เป็นประจำเพื่อ unpause DAGs ที่ลืม
- Track Duration trends เพื่อ identify performance degradation

---

### 3️⃣ Airflow DAGs Status Grid

**วัตถุประสงค์**: แสดงสถานะ DAGs แบบ grid layout (80 DAGs) เพื่อให้เห็นภาพรวมสถานะของ DAGs ทั้งหมดในหน้าเดียว

**Data Source**: Airflow PostgreSQL

**เหตุผลในการออกแบบ Grid Layout**:
- **Visual clarity**: เห็นสถานะ DAGs ทั้งหมดในหน้าเดียวโดยไม่ต้อง scroll
- **Quick identification**: ใช้สีแยกสถานะ (เขียว=Success, แดง=Failed, เหลือง=Running, เทา=Paused)
- **Operational dashboard**: เหมาะสำหรับแสดงบน monitor ในห้อง operations

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

**คำอธิบาย Logic**:

1. **Priority-based CASE statement**: ใช้ลำดับความสำคัญในการตรวจสอบสถานะ
   - **Running first**: ถ้ากำลัง run อยู่ = สถานะสำคัญที่สุด
   - **Failed second**: ถ้า fail ใน 24h = ต้อง attention ทันที
   - **Success third**: ถ้า success ใน 24h = ทำงานปกติ
   - **Paused fourth**: ถ้า pause = ไม่ได้ทำงาน
   - **Unknown last**: ถ้าไม่ตรงเงื่อนไขใดๆ = อาจมีปัญหา

2. **`EXISTS` subquery**: ใช้แทน JOIN เพื่อ performance
   - **เหตุผล**: EXISTS หยุดทันทีที่เจอ row แรก ไม่ต้องนับทั้งหมด
   - **ความสำคัญ**: Query เร็วกว่า COUNT(*) มาก เมื่อมี DAG runs เยอะ

3. **Time window 24h สำหรับ Failed/Success**:
   - **เหตุผล**: Focus ที่สถานะล่าสุด ไม่สนใจ historical failures
   - **ความสำคัญ**: ถ้า DAG fail เมื่อ 2 วันก่อนแต่ success วันนี้ = ถือว่า OK

4. **Check `is_paused` จาก `dag` table**:
   - **เหตุผล**: Paused status เก็บใน DAG definition ไม่ใช่ run history
   - **ความสำคัญ**: แยกระหว่าง "ไม่ได้ run เพราะ pause" กับ "ไม่ได้ run เพราะมีปัญหา"

**หมายเหตุ**: Dashboard นี้ใช้ static grid (80 panels) ต้อง regenerate เมื่อมี DAG เพิ่ม/ลด

**Trade-offs**:
- **ข้อดี**: Visual clarity สูง, เหมาะสำหรับ operations monitoring
- **ข้อเสีย**: ต้อง regenerate เมื่อ DAG เปลี่ยน (ดู Grid Layout Options ด้านล่าง)

---

### 4️⃣ Airflow Task Performance Dashboard

**วัตถุประสงค์**: วิเคราะห์ performance ของ tasks, retry rate, และ queue time เพื่อ optimize ประสิทธิภาพและ identify bottlenecks

**Data Source**: Airflow PostgreSQL

**เหตุผลในการวิเคราะห์ Task Performance**:
- **Capacity planning**: ใช้ duration และ queue time ในการวางแผน resources
- **Performance optimization**: Identify slow tasks ที่ต้อง optimize
- **Reliability improvement**: ติดตาม retry rate เพื่อแก้ไขปัญหา instability

**Panels และ SQL Queries**:

#### ⏱️ Average Task Duration (24h)

```sql
SELECT AVG(EXTRACT(EPOCH FROM (end_date - start_date))) as "Avg Duration" 
FROM task_instance 
WHERE state = 'success' 
  AND start_date >= $__timeFrom() 
  AND start_date <= $__timeTo()
  AND end_date IS NOT NULL;
```

**คำอธิบายแต่ละส่วน**:

1. **`EXTRACT(EPOCH FROM (end_date - start_date))`**:
   - **EPOCH**: แปลง PostgreSQL interval เป็นวินาที (seconds)
   - **เหตุผล**: ง่ายต่อการคำนวณและเปรียบเทียบ
   - **ความสำคัญ**: Standard unit สำหรับ duration metrics

2. **`WHERE state = 'success'`**:
   - **เหตุผล**: นับเฉพาะ tasks ที่ทำงานสำเร็จ ไม่รวม failed tasks (ที่อาจ timeout หรือ crash)
   - **ความสำคัญ**: ได้ baseline performance ที่แท้จริง ไม่ถูก skew จาก failures

3. **`AND end_date IS NOT NULL`**:
   - **เหตุผล**: กรอง tasks ที่ยังไม่จบ (running tasks มี end_date = NULL)
   - **ความสำคัญ**: ป้องกัน NULL values ที่ทำให้ calculation ผิดพลาด

4. **Time window 24h**:
   - **เหตุผล**: Recent performance indicator ไม่รวม historical data ที่อาจ outdated
   - **ความสำคัญ**: ใช้ติดตาม current performance และ detect regressions

**Business Value**: ใช้เป็น baseline สำหรับ SLA และ performance monitoring

#### 🔄 Tasks with Retries (24h)

```sql
SELECT COUNT(*) as "Tasks with Retries" 
FROM task_instance 
WHERE try_number > 1 
  AND start_date >= $__timeFrom() 
  AND start_date <= $__timeTo();
```

**คำอธิบาย**:

1. **`try_number > 1`**:
   - **try_number**: จำนวนครั้งที่ task ถูก execute (เริ่มจาก 1)
   - **> 1**: หมายความว่า task fail อย่างน้อย 1 ครั้งแล้ว retry
   - **เหตุผล**: Indicator ของ instability หรือ transient failures
   - **ความสำคัญ**: **Reliability metric** - retry rate สูง = มีปัญหาที่ต้องแก้ไข

**Business Value**: 
- High retry rate = เสีย resources และเวลา
- ต้อง investigate root cause (network issues, external API failures, etc.)
- อาจต้องปรับ retry strategy หรือแก้ไข task logic

#### ⏳ Average Queue Time (24h)

```sql
SELECT AVG(EXTRACT(EPOCH FROM (start_date - queued_dttm))) as "Avg Queue Time" 
FROM task_instance 
WHERE state IN ('success', 'failed') 
  AND start_date >= $__timeFrom() 
  AND start_date <= $__timeTo()
  AND queued_dttm IS NOT NULL;
```

**คำอธิบายแต่ละส่วน**:

1. **`start_date - queued_dttm`**:
   - **queued_dttm**: เวลาที่ task ถูกใส่เข้า queue
   - **start_date**: เวลาที่ task เริ่ม execute จริง
   - **Difference**: ระยะเวลาที่รออยู่ใน queue
   - **ความสำคัญ**: **Bottleneck indicator** - queue time สูง = ไม่มี resources พอ

2. **`WHERE state IN ('success', 'failed')`**:
   - **เหตุผล**: นับเฉพาะ tasks ที่จบแล้ว (มี start_date แน่นอน)
   - **ไม่รวม 'running'**: เพราะยังไม่รู้ว่า queue time จริงๆ เท่าไหร่
   - **ความสำคัญ**: ได้ accurate measurement

3. **`AND queued_dttm IS NOT NULL`**:
   - **เหตุผล**: บาง tasks อาจไม่ผ่าน queue (direct execution)
   - **ความสำคัญ**: ป้องกัน NULL values

**Business Value**:
- Queue time สูง = ต้องเพิ่ม workers หรือปรับ pool configuration
- ใช้ในการ capacity planning และ cost optimization
- ช่วย identify peak hours ที่ต้อง scale up

#### 📊 Average Task Duration by DAG (7 days)

```sql
SELECT 
  DATE_TRUNC('hour', start_date) as time,
  dag_id,
  AVG(EXTRACT(EPOCH FROM (end_date - start_date))) as value
FROM task_instance 
WHERE state = 'success' 
  AND start_date >= $__timeFrom()
  AND start_date <= $__timeTo()
  AND end_date IS NOT NULL
GROUP BY DATE_TRUNC('hour', start_date), dag_id
ORDER BY time;
```

**คำอธิบายแต่ละส่วน**:

1. **`DATE_TRUNC('hour', start_date)`**:
   - **DATE_TRUNC**: ตัด timestamp ให้เหลือแค่ hour (ทิ้ง minutes, seconds)
   - **เหตุผล**: Group data เป็น hourly buckets สำหรับ time series
   - **ความสำคัญ**: Balance ระหว่าง granularity และ readability

2. **`GROUP BY ... dag_id`**:
   - **เหตุผล**: แยก metrics ตาม DAG เพื่อเปรียบเทียบ
   - **ความสำคัญ**: Identify ว่า DAG ไหนช้า DAG ไหนเร็ว

3. **Time window 7 days**:
   - **เหตุผล**: ดู trend ระยะสั้น ไม่ยาวเกินไปจนเห็น pattern ไม่ชัด
   - **ความสำคัญ**: เหมาะสำหรับ detect performance regressions

**Business Value**:
- **Trend analysis**: เห็น performance degradation over time
- **Comparison**: เปรียบเทียบ DAGs เพื่อ identify outliers
- **Alerting**: ตั้ง alert เมื่อ duration เพิ่มขึ้นผิดปกติ

#### 🏆 Top 10 Longest Running Tasks (24h)

```sql
SELECT 
  dag_id || '.' || task_id as "Task",
  EXTRACT(EPOCH FROM (end_date - start_date)) as "Duration"
FROM task_instance 
WHERE state = 'success' 
  AND start_date >= $__timeFrom()
  AND start_date <= $__timeTo()
  AND end_date IS NOT NULL
ORDER BY "Duration" DESC
LIMIT 10;
```

**คำอธิบาย**:

1. **`dag_id || '.' || task_id`**:
   - **String concatenation**: รวม DAG ID และ Task ID
   - **เหตุผล**: Unique identifier ที่อ่านง่าย (เช่น "etl_pipeline.extract_data")
   - **ความสำคัญ**: ช่วยในการ identify และ navigate ไปยัง task

2. **`ORDER BY "Duration" DESC LIMIT 10`**:
   - **เหตุผล**: Focus ที่ top 10 slowest tasks
   - **ความสำคัญ**: **Optimization target** - tasks เหล่านี้มี impact สูงสุดต่อ overall performance

**Business Value**:
- **Optimization priority**: รู้ว่าควร optimize task ไหนก่อน
- **Resource allocation**: Tasks ที่ใช้เวลานานอาจต้อง dedicated resources
- **SLA planning**: ใช้ในการกำหนด realistic SLAs

#### 🔁 Top DAGs by Retry Count (7 days)

```sql
SELECT 
  dag_id as "DAG ID",
  COUNT(*) as "Retry Count"
FROM task_instance 
WHERE try_number > 1 
  AND start_date >= $__timeFrom()
  AND start_date <= $__timeTo()
GROUP BY dag_id
ORDER BY "Retry Count" DESC
LIMIT 10;
```

**คำอธิบาย**:

1. **`COUNT(*)`**: นับจำนวน task instances ที่ retry
   - **เหตุผล**: วัดปริมาณ retries ไม่ใช่แค่มีหรือไม่มี
   - **ความสำคัญ**: DAG ที่ retry เยอะ = มีปัญหาร้ายแรง

2. **`GROUP BY dag_id`**: รวม retries ตาม DAG
   - **เหตุผล**: Identify problematic DAGs
   - **ความสำคัญ**: Focus investigation efforts

**Business Value**:
- **Reliability improvement**: รู้ว่า DAG ไหนมีปัญหา
- **Cost reduction**: Retries เสีย compute resources
- **Root cause analysis**: ใช้เป็น starting point สำหรับ investigation

#### 📈 Retry Rate Trend by DAG (7 days)

```sql
SELECT 
  DATE_TRUNC('hour', start_date) as time,
  dag_id,
  (COUNT(CASE WHEN try_number > 1 THEN 1 END)::float / NULLIF(COUNT(*)::float, 0) * 100) as value
FROM task_instance 
WHERE start_date >= $__timeFrom()
  AND start_date <= $__timeTo()
GROUP BY DATE_TRUNC('hour', start_date), dag_id
HAVING COUNT(*) > 0
ORDER BY time;
```

**คำอธิบายแต่ละส่วน**:

1. **`COUNT(CASE WHEN try_number > 1 THEN 1 END)`**:
   - **Conditional count**: นับเฉพาะ tasks ที่ retry
   - **เหตุผล**: ได้จำนวน retries

2. **`NULLIF(COUNT(*)::float, 0)`**:
   - **NULLIF**: แปลง 0 เป็น NULL เพื่อป้องกัน division by zero
   - **::float**: Cast เป็น float สำหรับ decimal division
   - **ความสำคัญ**: ป้องกัน error และได้ percentage ที่แม่นยำ

3. **`* 100`**: แปลงเป็น percentage
   - **เหตุผล**: Percentage อ่านง่ายกว่า decimal (10% vs 0.1)

4. **`HAVING COUNT(*) > 0`**:
   - **เหตุผล**: กรอง time buckets ที่ไม่มี tasks
   - **ความสำคัญ**: ลด noise ใน chart

**Business Value**:
- **Trend detection**: เห็นว่า retry rate เพิ่มหรือลด
- **Incident correlation**: เชื่อมโยงกับ incidents หรือ deployments
- **Proactive alerting**: ตั้ง alert เมื่อ retry rate spike

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
  AND start_date >= $__timeFrom()
  AND start_date <= $__timeTo()
ORDER BY start_date DESC
LIMIT 100;
```

**คำอธิบายแต่ละ Column**:

1. **`run_id`**: Unique identifier ของ DAG run
   - **เหตุผล**: ใช้ในการ drill-down และ log correlation
   - **ความสำคัญ**: Critical สำหรับ troubleshooting

2. **`try_number`**: จำนวนครั้งที่ try
   - **เหตุผล**: บอกว่า retry กี่ครั้ง (2 = retry 1 ครั้ง, 3 = retry 2 ครั้ง)
   - **ความสำคัญ**: Severity indicator - try_number สูง = ปัญหาร้ายแรง

3. **`COALESCE(end_date, NOW())`**:
   - **เหตุผล**: ถ้า task ยังไม่จบ ใช้เวลาปัจจุบันคำนวณ duration
   - **ความสำคัญ**: ได้ duration แม้ task ยัง running

**Business Value**:
- **Immediate investigation**: เห็น recent failures ที่ต้องแก้ไขทันที
- **Pattern recognition**: เห็น pattern ของ retries (เช่น retry ช่วงเวลาเดียวกัน)
- **Detailed troubleshooting**: มีข้อมูลครบสำหรับ debug

**หมายเหตุ**: Dashboard นี้ไม่มี SLA panels เพราะตาราง `sla_miss` ถูกลบออกใน Airflow 3.x

**Best Practices**:
- ตั้ง alert เมื่อ Average Queue Time > 5 นาที
- Review Top 10 Longest Tasks ทุกสัปดาห์เพื่อ optimize
- Investigate DAGs ที่มี Retry Rate > 10%
- Monitor Retry Rate Trend เพื่อ detect regressions หลัง deployment


---

### 5️⃣ Airflow Resource Utilization & Pool Dashboard

**วัตถุประสงค์**: ติดตาม pool usage, slot allocation, และ resource utilization เพื่อ optimize resource allocation และป้องกัน bottlenecks

**Data Source**: Airflow PostgreSQL

**เหตุผลในการ Monitor Resources**:
- **Capacity planning**: วางแผน resources ให้เพียงพอกับ workload
- **Cost optimization**: ใช้ resources อย่างมีประสิทธิภาพ ไม่ over-provision
- **Bottleneck prevention**: Identify และแก้ไข resource constraints ก่อนกระทบ production

**Concept: Airflow Pools**:
- **Pool**: กลุ่ม slots สำหรับควบคุม concurrency ของ tasks
- **Slot**: หน่วยของ parallelism (1 task = 1 slot โดยปกติ)
- **Use case**: จำกัดจำนวน tasks ที่เข้าถึง shared resources (เช่น database, API) พร้อมกัน

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

**คำอธิบาย**:

1. **Total Pools**: จำนวน pools ทั้งหมดในระบบ
   - **เหตุผล**: ภาพรวมของ resource segmentation
   - **ความสำคัญ**: ใช้ในการ organize และ manage resources

2. **Total Slots**: จำนวน slots ทั้งหมด (capacity รวม)
   - **Formula**: `SUM(slots)` - รวม slots จากทุก pools
   - **เหตุผล**: บอก maximum concurrency ของระบบ
   - **ความสำคัญ**: **Capacity metric** - ใช้ในการ capacity planning

3. **Queued Tasks**: tasks ที่รอ slots ว่าง
   - **เหตุผล**: Indicator ของ resource saturation
   - **ความสำคัญ**: Queue สูง = ต้องเพิ่ม slots หรือ optimize tasks

4. **Running Tasks**: tasks ที่กำลังใช้ slots
   - **เหตุผล**: Current utilization
   - **ความสำคัญ**: เปรียบเทียบกับ Total Slots เพื่อดู utilization rate

**Business Value**: ภาพรวม resource availability และ utilization

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

**คำอธิบายแต่ละส่วน**:

1. **`LEFT JOIN task_instance`**:
   - **LEFT JOIN**: รวม pools ที่ไม่มี running tasks ด้วย (จะได้ 0%)
   - **เหตุผล**: ต้องการเห็นทุก pools แม้ไม่มี tasks
   - **ความสำคัญ**: Complete picture ของทุก pools

2. **`ti.state = 'running'`**:
   - **เหตุผล**: นับเฉพาะ tasks ที่กำลังใช้ slots
   - **ไม่รวม queued**: เพราะยังไม่ได้ใช้ slots จริง

3. **`COUNT(ti.task_id)::float / sp.slots::float * 100`**:
   - **Occupied slots / Total slots * 100**: คำนวณ utilization percentage
   - **::float**: Cast เป็น float เพื่อได้ decimal
   - **ความสำคัญ**: Percentage อ่านง่ายและเปรียบเทียบได้

4. **`CASE WHEN sp.slots = 0`**:
   - **เหตุผล**: ป้องกัน division by zero
   - **ความสำคัญ**: Handle edge case ของ pools ที่ slots = 0

**Business Value**:
- **Utilization monitoring**: รู้ว่า pool ไหนใช้งานเต็ม pool ไหนว่าง
- **Rebalancing**: ปรับ slots ระหว่าง pools ให้เหมาะสม
- **Alerting**: ตั้ง alert เมื่อ utilization > 90%

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

**คำอธิบายแต่ละ Column**:

1. **Total Slots**: Configured capacity ของ pool
   - **เหตุผล**: Maximum concurrency ที่อนุญาต
   - **ความสำคัญ**: Configuration reference

2. **Occupied Slots**: จำนวน slots ที่ใช้งานอยู่
   - **Formula**: `COUNT(ti.task_id)` where state = 'running'
   - **เหตุผล**: Current usage
   - **ความสำคัญ**: Real-time utilization

3. **Available Slots**: จำนวน slots ว่าง
   - **Formula**: `Total Slots - Occupied Slots`
   - **เหตุผล**: Remaining capacity
   - **ความสำคัญ**: **Critical metric** - บอกว่ารับ tasks เพิ่มได้อีกกี่ tasks

**Business Value**: Detailed view สำหรับ capacity management และ troubleshooting

#### 📈 Task Execution by Pool (7 days)

```sql
SELECT 
  DATE_TRUNC('hour', start_date) as time,
  pool,
  COUNT(*) as value
FROM task_instance 
WHERE start_date >= $__timeFrom()
  AND start_date <= $__timeTo()
  AND pool IS NOT NULL
GROUP BY DATE_TRUNC('hour', start_date), pool
ORDER BY time;
```

**คำอธิบาย**:

1. **`AND pool IS NOT NULL`**:
   - **เหตุผล**: กรอง tasks ที่ไม่ได้ระบุ pool (ใช้ default_pool)
   - **ความสำคัญ**: Focus ที่ pools ที่ configure ไว้

2. **Time series by pool**:
   - **เหตุผล**: เห็น usage pattern ของแต่ละ pool
   - **ความสำคัญ**: Identify peak hours และ usage trends

**Business Value**:
- **Pattern recognition**: เห็นว่า pool ไหนใช้งานหนักช่วงไหน
- **Capacity planning**: วางแผนเพิ่ม slots ในช่วง peak
- **Cost optimization**: ลด slots ในช่วงที่ไม่ใช้งาน (ถ้าใช้ auto-scaling)

#### 🥧 Task Distribution by Pool (24h)

```sql
SELECT 
  COALESCE(pool, 'default_pool') as metric,
  COUNT(*) as value
FROM task_instance 
WHERE start_date >= $__timeFrom()
  AND start_date <= $__timeTo()
GROUP BY pool
ORDER BY value DESC;
```

**คำอธิบาย**:

1. **`COALESCE(pool, 'default_pool')`**:
   - **COALESCE**: แทนที่ NULL ด้วย 'default_pool'
   - **เหตุผล**: Tasks ที่ไม่ระบุ pool จะใช้ default_pool
   - **ความสำคัญ**: Accurate representation ของ pool usage

2. **`ORDER BY value DESC`**:
   - **เหตุผล**: เรียงจากมากไปน้อย เห็น busiest pools ก่อน
   - **ความสำคัญ**: Quick identification ของ high-usage pools

**Business Value**: เห็น distribution ของ workload ระหว่าง pools

#### 🏆 Top Pools by Task Count (7 days)

```sql
SELECT 
  COALESCE(pool, 'default_pool') as "Pool",
  COUNT(*) as "Task Count"
FROM task_instance 
WHERE start_date >= $__timeFrom()
  AND start_date <= $__timeTo()
GROUP BY pool
ORDER BY "Task Count" DESC
LIMIT 10;
```

**Business Value**: Identify pools ที่ใช้งานมากที่สุด เพื่อ prioritize optimization

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

**คำอธิบายแต่ละ Column**:

1. **`priority_weight`**: ค่า priority ของ task (สูงกว่า = สำคัญกว่า)
   - **เหตุผล**: Airflow ใช้ priority_weight ในการตัดสินใจว่าจะ execute task ไหนก่อน
   - **ความสำคัญ**: เข้าใจ queue ordering logic

2. **`queued_dttm`**: เวลาที่เข้า queue
   - **เหตุผล**: บอกว่ารออยู่นานแค่ไหน
   - **ความสำคัญ**: Identify tasks ที่รอนานผิดปกติ

3. **`Wait Time (s)`**: ระยะเวลาที่รออยู่ (วินาที)
   - **Formula**: `NOW() - queued_dttm`
   - **เหตุผล**: Real-time wait time
   - **ความสำคัญ**: **SLA indicator** - wait time นาน = อาจพลาด SLA

4. **`ORDER BY priority_weight DESC, queued_dttm ASC`**:
   - **เหตุผล**: เรียงตาม priority สูงสุดก่อน แล้วตาม queue time เก่าสุดก่อน
   - **ความสำคัญ**: Matches Airflow's actual execution order

**Business Value**:
- **Troubleshooting**: เห็นว่า tasks อะไรติดอยู่ใน queue
- **Priority management**: ตรวจสอบว่า priority weights ถูกต้อง
- **Capacity planning**: Wait time สูง = ต้องเพิ่ม capacity

**Best Practices**:
- ตั้ง alert เมื่อ Pool Utilization > 90% ต่อเนื่อง 10 นาที
- Review Pool Distribution ทุกสัปดาห์เพื่อ rebalance slots
- Monitor Queued Tasks และ investigate ถ้า wait time > 5 นาที
- ใช้ priority_weight อย่างมีกลยุทธ์ - ไม่ควรทุก tasks มี priority สูง

---

### 6️⃣ Airflow Error & Debugging Dashboard

**วัตถุประสงค์**: ติดตาม errors, failures, และ import errors เพื่อ maintain system reliability และ quickly identify issues

**Data Source**: Airflow PostgreSQL

**เหตุผลในการ Monitor Errors**:
- **Proactive issue detection**: จับปัญหาก่อนกระทบ business
- **MTTR reduction**: ลดเวลาในการแก้ไขปัญหา (Mean Time To Resolution)
- **Root cause analysis**: มีข้อมูลเพียงพอสำหรับ investigate

**Panels และ SQL Queries**:

#### ❌ Error Statistics

```sql
-- Failed Tasks (ใช้ Grafana time range)
SELECT COUNT(*) as "Failed Tasks" 
FROM task_instance 
WHERE state = 'failed' 
  AND start_date >= $__timeFrom()
  AND start_date <= $__timeTo();

-- Failed DAG Runs (ใช้ Grafana time range)
SELECT COUNT(*) as "Failed DAG Runs" 
FROM dag_run 
WHERE state = 'failed' 
  AND start_date >= $__timeFrom()
  AND start_date <= $__timeTo();

-- Import Errors (ไม่มี time filter - แสดงทั้งหมด)
SELECT COUNT(*) as "Import Errors" FROM import_error;

-- Upstream Failed Tasks (ใช้ Grafana time range)
SELECT COUNT(*) as "Upstream Failed" 
FROM task_instance 
WHERE state = 'upstream_failed' 
  AND start_date >= $__timeFrom()
  AND start_date <= $__timeTo();
```

**การใช้ Grafana Time Range Variables**:
- **`$__timeFrom()`**: เวลาเริ่มต้นที่ผู้ใช้เลือกจาก Grafana UI
- **`$__timeTo()`**: เวลาสิ้นสุดที่ผู้ใช้เลือกจาก Grafana UI
- **ข้อดี**: Flexible - ผู้ใช้สามารถเลือก time range ได้เอง (Last 24h, Last 7 days, Custom range)
- **Default time range**: Dashboard ตั้งค่าเริ่มต้นเป็น "Last 24 hours"

**คำอธิบายแต่ละ Metric**:

1. **Failed Tasks**: จำนวน tasks ที่ fail
   - **เหตุผล**: Task-level failures (code errors, timeouts, etc.)
   - **ความสำคัญ**: **Primary error metric** - บอกจำนวนปัญหาที่เกิดขึ้น

2. **Failed DAG Runs**: จำนวน DAG runs ที่ fail
   - **เหตุผล**: DAG-level failures (ทั้ง DAG fail)
   - **ความสำคัญ**: **Business impact metric** - 1 DAG fail = business process fail

3. **Import Errors**: จำนวน DAG files ที่ import ไม่ได้
   - **Table `import_error`**: เก็บ errors จากการ parse/import DAG files
   - **เหตุผล**: Syntax errors, missing dependencies, etc.
   - **ความสำคัญ**: **Critical errors** - DAGs ที่ import error จะไม่ทำงานเลย

4. **Upstream Failed Tasks**: tasks ที่ fail เพราะ upstream task fail
   - **State 'upstream_failed'**: Task ถูก skip เพราะ dependency fail
   - **เหตุผล**: Cascade failures จาก upstream
   - **ความสำคัญ**: บอก impact radius ของ failures

**Business Value**: ภาพรวม error landscape สำหรับ prioritize investigation

#### 📊 Task Failure Trend (7 days)

```sql
SELECT 
  DATE_TRUNC('hour', start_date) as time,
  dag_id,
  COUNT(*) as value
FROM task_instance 
WHERE state = 'failed' 
  AND start_date >= $__timeFrom()
  AND start_date <= $__timeTo()
GROUP BY DATE_TRUNC('hour', start_date), dag_id
ORDER BY time;
```

**คำอธิบาย**:
- **Time series of failures**: เห็น failure patterns over time
- **By DAG**: แยกตาม DAG เพื่อเห็นว่า DAG ไหนมีปัญหา
- **ความสำคัญ**: **Trend analysis** - detect increasing failure rates

**Business Value**:
- **Incident detection**: Spike ใน failures = incident
- **Correlation**: เชื่อมโยงกับ deployments หรือ external events
- **Proactive alerting**: ตั้ง alert เมื่อ failure rate เพิ่มขึ้นผิดปกติ

#### 🏆 Top Failed Tasks by DAG (7 days)

```sql
SELECT 
  dag_id as "DAG ID",
  COUNT(*) as "Failure Count"
FROM task_instance 
WHERE state = 'failed' 
  AND start_date >= $__timeFrom()
  AND start_date <= $__timeTo()
GROUP BY dag_id
ORDER BY "Failure Count" DESC
LIMIT 10;
```

**Business Value**: **Investigation priority** - focus ที่ DAGs ที่ fail บ่อยที่สุด

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
  AND start_date >= $__timeFrom()
  AND start_date <= $__timeTo()
ORDER BY start_date DESC
LIMIT 100;
```

**คำอธิบาย**:
- **Recent failures**: Focus ที่ failures ล่าสุด
- **Detailed information**: มีข้อมูลครบสำหรับ investigation
- **ความสำคัญ**: **Actionable data** - ใช้ในการ troubleshoot ทันที

**Business Value**: Immediate visibility สำหรับ on-call engineers

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

**คำอธิบายแต่ละ Column**:

1. **`filename`**: ชื่อไฟล์ DAG ที่มีปัญหา
   - **เหตุผล**: Identify problematic DAG file
   - **ความสำคัญ**: Direct pointer ไปยัง source ของปัญหา

2. **`stacktrace`**: Error message และ stack trace (ไม่มี underscore)
   - **เหตุผล**: Detailed error information
   - **ความสำคัญ**: **Root cause information** - ใช้ในการแก้ไขปัญหา

3. **`timestamp`**: เวลาที่เกิด error
   - **เหตุผล**: บอกว่าเกิดเมื่อไหร่
   - **ความสำคัญ**: Correlate กับ deployments

**Business Value**: **Critical errors** - ต้องแก้ไขทันทีเพราะ DAGs ไม่ทำงาน

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
WHERE start_date >= $__timeFrom()
  AND start_date <= $__timeTo()
GROUP BY dag_id
HAVING COUNT(*) > 0
ORDER BY "Failure Rate (%)" DESC
LIMIT 20;
```

**คำอธิบายแต่ละส่วน**:

1. **Conditional counts**:
   - **`COUNT(CASE WHEN state = 'failed' THEN 1 END)`**: นับ failures
   - **`COUNT(CASE WHEN state = 'success' THEN 1 END)`**: นับ successes
   - **เหตุผล**: ได้ทั้ง absolute numbers และ rate

2. **Failure Rate calculation**:
   - **Formula**: `Failed / Total * 100`
   - **`NULLIF(COUNT(*), 0)`**: ป้องกัน division by zero
   - **`ROUND(..., 2)`**: ปัดเป็น 2 ทศนิยม
   - **ความสำคัญ**: **Reliability metric** - percentage อ่านง่ายกว่า absolute numbers

3. **`HAVING COUNT(*) > 0`**:
   - **เหตุผล**: กรอง DAGs ที่ไม่มี runs
   - **ความสำคัญ**: Focus ที่ active DAGs

**Business Value**:
- **Reliability ranking**: รู้ว่า DAG ไหน reliable DAG ไหนมีปัญหา
- **SLA compliance**: Failure rate สูง = พลาด SLA
- **Investment priority**: DAGs ที่ failure rate สูงควร invest ใน improvement

**Best Practices**:
- ตั้ง alert เมื่อ Failed Tasks > threshold (เช่น 10 tasks/hour)
- Review Import Errors ทุกวัน - ต้องแก้ไขให้เป็น 0
- Investigate DAGs ที่ Failure Rate > 5%
- สร้าง runbook สำหรับ common failure patterns
- Monitor Upstream Failed Tasks เพื่อเข้าใจ dependency impact


---

### 7️⃣ Airflow DAG Dependencies & Lineage Dashboard

**วัตถุประสงค์**: ติดตาม DAG dependencies, asset relationships, และ task lineage เพื่อเข้าใจ data flow และ dependencies ระหว่าง DAGs

**Data Source**: Airflow PostgreSQL

**เหตุผลในการ Monitor Dependencies**:
- **Impact analysis**: เข้าใจว่าการเปลี่ยนแปลง DAG หนึ่งจะกระทบอะไรบ้าง
- **Data lineage**: ติดตาม data flow จาก source ถึง destination
- **Troubleshooting**: เข้าใจ dependencies เมื่อเกิดปัญหา

**Concept: Airflow Assets (เดิมชื่อ Datasets)**:
- **Asset**: Resource ที่ DAGs produce หรือ consume (เช่น tables, files)
- **Asset-based scheduling**: DAG ถูก trigger เมื่อ assets ที่ depend on ถูก update
- **Lineage**: ติดตาม data flow ผ่าน assets

**Panels และ SQL Queries**:

#### 📊 Overview Statistics

```sql
-- Total DAGs
SELECT COUNT(DISTINCT dag_id) as "Total DAGs" 
FROM dag 
WHERE bundle_name IS NOT NULL;

-- Total Task Instances
SELECT COUNT(*) as "Total Tasks" 
FROM task_instance 
WHERE start_date >= $__timeFrom()
  AND start_date <= $__timeTo();

-- DAGs with Asset Dependencies
SELECT COUNT(DISTINCT dag_id) as "DAGs with Asset Dependencies" 
FROM dag_schedule_asset_reference;

-- Total Assets
SELECT COUNT(DISTINCT id) as "Total Assets" FROM asset;
```

**คำอธิบาย**:

1. **DAGs with Asset Dependencies**:
   - **Table `dag_schedule_asset_reference`**: เก็บ relationships ระหว่าง DAGs และ assets ที่ trigger DAGs
   - **เหตุผล**: บอกจำนวน DAGs ที่ใช้ asset-based scheduling
   - **ความสำคัญ**: Measure adoption ของ data-driven scheduling

2. **Total Assets**:
   - **Table `asset`**: เก็บ asset definitions (เดิมชื่อ `dataset` ใน Airflow 2.x)
   - **เหตุผล**: บอกจำนวน data resources ที่ tracked
   - **ความสำคัญ**: Measure data lineage coverage

**Business Value**: ภาพรวมของ data ecosystem และ dependency complexity

#### 🔗 DAG Complexity (by Task Count)

```sql
SELECT 
  d.dag_id as "DAG ID",
  COUNT(DISTINCT ti.task_id) as "Task Count",
  d.is_paused as "Paused",
  d.timetable_summary as "Schedule"
FROM dag d
LEFT JOIN (
  SELECT DISTINCT dag_id, task_id 
  FROM task_instance 
  WHERE start_date >= $__timeFrom()
    AND start_date <= $__timeTo()
) ti ON d.dag_id = ti.dag_id
WHERE d.bundle_name IS NOT NULL
GROUP BY d.dag_id, d.is_paused, d.timetable_summary
ORDER BY "Task Count" DESC
LIMIT 20;
```

**คำอธิบายแต่ละส่วน**:

1. **`COUNT(DISTINCT task_id)`**: นับจำนวน unique tasks ใน DAG
   - **เหตุผล**: Measure DAG complexity
   - **ความสำคัญ**: **Complexity metric** - DAGs ที่มี tasks เยอะมักซับซ้อนและยาก maintain

2. **`LEFT JOIN task_instance`**: Join กับ recent task executions
   - **เหตุผล**: นับเฉพาะ tasks ที่ execute จริง (ไม่รวม tasks ที่ไม่เคย run)
   - **Time window 7 days**: Focus ที่ active tasks
   - **ความสำคัญ**: Accurate complexity measurement

3. **`timetable_summary`**: Schedule pattern ของ DAG (Airflow 3.x)
   - **เหตุผล**: เข้าใจ execution frequency - แทนที่ `schedule_interval` ใน Airflow 2.x
   - **ความสำคัญ**: Context สำหรับ complexity - DAG ที่ run บ่อยต้อง optimize มากกว่า

4. **`tags::text`**: Tags ของ DAG
   - **Cast to text**: แปลง array เป็น text สำหรับแสดงผล
   - **เหตุผล**: Categorization และ filtering
   - **ความสำคัญ**: Organization และ management

**Business Value**: 
- **Maintenance priority**: DAGs ที่ซับซ้อนต้อง invest ใน documentation และ testing
- **Refactoring candidates**: DAGs ที่มี tasks มากเกินไปอาจต้อง refactor
- **Resource planning**: Complex DAGs ใช้ resources มากกว่า

#### 📊 Task Operator Distribution (7 days)

```sql
SELECT 
  operator as "Operator Type",
  COUNT(*) as "Usage Count"
FROM task_instance 
WHERE start_date >= $__timeFrom()
  AND start_date <= $__timeTo()
  AND operator IS NOT NULL
GROUP BY operator
ORDER BY "Usage Count" DESC
LIMIT 15;
```

**คำอธิบาย**:

1. **Column `operator`**: ชื่อ operator class ที่ task ใช้
   - **เหตุผล**: บอกว่าใช้ operators อะไรบ้าง (PythonOperator, BashOperator, etc.)
   - **ความสำคัญ**: **Technology stack visibility** - เห็นว่าใช้ technologies อะไร

2. **Usage count**: จำนวนครั้งที่ operator ถูกใช้
   - **เหตุผล**: Measure operator popularity
   - **ความสำคัญ**: Identify most-used operators สำหรับ optimization และ training

**Business Value**:
- **Standardization**: เห็น operator patterns เพื่อ standardize
- **Training focus**: Train team บน operators ที่ใช้บ่อย
- **Dependency management**: รู้ว่าต้อง maintain operators ไหนบ้าง

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

**คำอธิบายแต่ละ Column**:

1. **`uri`**: Unique identifier ของ asset (เช่น "s3://bucket/data.csv", "postgres://db/table")
   - **เหตุผล**: Globally unique identifier
   - **ความสำคัญ**: **Primary identifier** สำหรับ asset tracking

2. **`name`**: Human-readable name
   - **เหตุผล**: ชื่อที่อ่านง่ายกว่า URI
   - **ความสำคัญ**: User-friendly reference

3. **`group`**: Logical grouping ของ assets
   - **เหตุผล**: Organize assets ตาม domain หรือ team
   - **ความสำคัญ**: Organization และ access control

4. **`updated_at`**: เวลาที่ asset ถูก update ล่าสุด
   - **เหตุผล**: Track freshness ของ asset
   - **ความสำคัญ**: **Data freshness indicator** - บอกว่า data ใหม่แค่ไหน

**Business Value**: Asset catalog สำหรับ data discovery และ governance

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

**คำอธิบาย**:

1. **Table `dag_schedule_asset_reference`**: Mapping ระหว่าง DAGs และ assets ที่ trigger DAGs
   - **เหตุผล**: Airflow 3.x ใช้ asset-based scheduling - DAG ถูก trigger เมื่อ asset ถูก update
   - **ความสำคัญ**: **Dependency mapping** - เข้าใจว่า DAG ไหน depend on asset ไหน

2. **JOIN asset**: เอา asset details มาแสดง
   - **เหตุผล**: ต้องการ URI และ name ของ asset
   - **ความสำคัญ**: Complete information สำหรับ analysis

**Business Value**:
- **Impact analysis**: รู้ว่าถ้า asset เปลี่ยน จะกระทบ DAGs ไหนบ้าง
- **Dependency visualization**: เห็น data flow ระหว่าง DAGs
- **Troubleshooting**: Debug scheduling issues ที่เกี่ยวกับ asset dependencies

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

**คำอธิบาย**:

1. **Table `asset_event`**: เก็บ events เมื่อ assets ถูก update
   - **เหตุผล**: Track asset changes ที่ trigger DAGs
   - **ความสำคัญ**: **Activity tracking** - เห็นว่า assets ถูก update บ่อยแค่ไหน

2. **Time series by asset**:
   - **เหตุผล**: เห็น update patterns ของแต่ละ asset
   - **ความสำคัญ**: Identify active vs inactive assets

**Business Value**:
- **Data freshness monitoring**: รู้ว่า data ถูก update สม่ำเสมอหรือไม่
- **Anomaly detection**: Detect ถ้า asset หยุด update หรือ update บ่อยผิดปกติ
- **Capacity planning**: เข้าใจ data volume และ frequency

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

**คำอธิบาย**:

1. **`tags::text`**: แปลง array ของ tags เป็น text
   - **เหตุผล**: PostgreSQL array ต้อง cast เป็น text สำหรับ GROUP BY
   - **ความสำคัญ**: Enable grouping และ counting

2. **`COALESCE(..., 'No Tags')`**: แทนที่ NULL ด้วย 'No Tags'
   - **เหตุผล**: DAGs ที่ไม่มี tags จะมี tags = NULL
   - **ความสำคัญ**: Include untagged DAGs ใน analysis

**Business Value**:
- **Organization visibility**: เห็นว่า DAGs ถูก organize อย่างไร
- **Governance**: Identify DAGs ที่ยังไม่มี tags
- **Access control**: Tags ใช้ในการ filter และ permission management

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

**คำอธิบายแต่ละ Column**:

1. **Execution Count**: จำนวนครั้งที่ task execute
   - **เหตุผล**: Measure task activity
   - **ความสำคัญ**: High execution count = important task

2. **Success/Failed counts**: แยกนับ success และ failed
   - **เหตุผล**: เห็น reliability ของแต่ละ task
   - **ความสำคัญ**: **Task-level reliability metric**

3. **Avg Duration**: เวลาเฉลี่ยที่ task ใช้
   - **`ROUND(..., 2)`**: ปัดเป็น 2 ทศนิยม
   - **เหตุผล**: Performance metric ของแต่ละ task
   - **ความสำคัญ**: Identify slow tasks สำหรับ optimization

**Business Value**:
- **Task-level insights**: เห็น performance และ reliability ของแต่ละ task
- **Optimization targets**: Tasks ที่ execute บ่อยและช้าควร optimize ก่อน
- **Reliability focus**: Tasks ที่ fail บ่อยต้อง investigate

#### 📊 Asset Activity (7 days)

```sql
SELECT 
  a.uri as "Asset URI",
  a.name as "Asset Name",
  COUNT(ae.id) as "Event Count",
  MAX(ae.timestamp) as "Last Updated"
FROM asset a
LEFT JOIN asset_event ae ON a.id = ae.asset_id
WHERE (ae.timestamp >= $__timeFrom() AND ae.timestamp <= $__timeTo()) OR ae.timestamp IS NULL
GROUP BY a.uri, a.name
ORDER BY "Event Count" DESC NULLS LAST
LIMIT 30;
```

**คำอธิบาย**:

1. **`LEFT JOIN asset_event`**: รวม assets ที่ไม่มี events ด้วย
   - **เหตุผล**: เห็นทุก assets รวมถึง inactive assets
   - **ความสำคัญ**: Complete visibility

2. **Event Count**: จำนวน update events
   - **เหตุผล**: Measure asset activity
   - **ความสำคัญ**: **Activity indicator** - assets ที่ไม่มี events อาจมีปัญหา

3. **Last Updated**: เวลาที่ update ล่าสุด
   - **`MAX(ae.timestamp)`**: เอา timestamp ล่าสุด
   - **เหตุผล**: Data freshness indicator
   - **ความสำคัญ**: Identify stale assets

**Business Value**:
- **Data quality monitoring**: Assets ที่ไม่ update อาจมีปัญหา
- **Cleanup candidates**: Inactive assets อาจลบได้
- **Dependency validation**: ตรวจสอบว่า assets ที่ DAGs depend on ยัง active

**Key Changes for Airflow 3.x**:
- ใช้ `asset` แทน `dataset` - Airflow 3.x เปลี่ยนชื่อเพื่อความชัดเจน
- ใช้ `asset_event` แทน `dataset_event`
- ใช้ `dag_schedule_asset_reference` แทน `dag_schedule_dataset_reference`

**Best Practices**:
- Tag DAGs ทุกตัวเพื่อ organization
- Monitor Asset Update Events เพื่อ detect data pipeline issues
- Review DAG Complexity เป็นประจำและ refactor DAGs ที่ซับซ้อนเกินไป
- Use asset-based scheduling สำหรับ data-driven workflows
- Document asset dependencies สำหรับ impact analysis

---

### 8️⃣ Airflow DAG Tasks Explorer

**วัตถุประสงค์**: Dashboard แบบ interactive สำหรับ drill-down และ explore tasks ภายใน DAG ที่เลือก เพื่อวิเคราะห์ task-level performance และ troubleshooting

**Data Source**: Airflow PostgreSQL

**เหตุผลในการใช้ Dashboard นี้**:
- **Drill-down analysis**: Focus ที่ tasks ของ DAG เดียวโดยเฉพาะ
- **Task-level troubleshooting**: Debug ปัญหาของ tasks แต่ละตัวอย่างละเอียด
- **Performance analysis**: วิเคราะห์ performance ของแต่ละ task ใน DAG
- **Interactive filtering**: ใช้ variable `$dag_id` เลือก DAG ที่ต้องการดู

**Key Feature: Dynamic DAG Selection**:
- Dashboard มี **variable `$dag_id`** ที่ query จาก database
- ผู้ใช้เลือก DAG จาก dropdown ได้เอง
- ทุก panels จะ filter ข้อมูลตาม DAG ที่เลือกอัตโนมัติ

**Panels และ SQL Queries**:

#### 📋 Tasks for DAG: $dag_id (Main Table)

```sql
SELECT 
  ti.task_id as "Task ID",
  ti.run_id as "Run ID",
  ti.state as "State",
  ti.start_date as "Start Date",
  ti.end_date as "End Date",
  EXTRACT(EPOCH FROM (COALESCE(ti.end_date, NOW()) - ti.start_date)) as "Duration (s)",
  ti.try_number as "Try Number",
  ti.max_tries as "Max Tries",
  ti.operator as "Operator",
  ti.pool as "Pool",
  ti.priority_weight as "Priority"
FROM task_instance ti
WHERE ti.dag_id = '$dag_id'
  AND ti.start_date >= $__timeFrom()
  AND ti.start_date <= $__timeTo()
ORDER BY ti.start_date DESC
LIMIT 100;
```

**คำอธิบายแต่ละ Column**:

1. **`task_id`**: Unique identifier ของ task ภายใน DAG
   - **เหตุผล**: Primary identifier สำหรับแต่ละ task
   - **ความสำคัญ**: ใช้ในการ reference และ drill-down
   - **Feature**: มี link ไปยัง Airflow UI สำหรับ task นั้นๆ

2. **`run_id`**: Unique identifier ของ DAG run
   - **เหตุผล**: บอกว่า task นี้อยู่ใน run ไหน
   - **ความสำคัญ**: ใช้ในการ correlate tasks ใน run เดียวกัน

3. **`state`**: สถานะของ task (success, failed, running, queued, up_for_retry)
   - **เหตุผล**: บอกผลลัพธ์ของ task execution
   - **ความสำคัญ**: **Primary indicator** ของ task health
   - **Visualization**: แสดงเป็น color-background (เขียว=success, แดง=failed, น้ำเงิน=running, เหลือง=queued, ส้ม=up_for_retry)

4. **`start_date`**: เวลาที่ task เริ่มทำงาน
   - **เหตุผล**: Actual execution start time
   - **ความสำคัญ**: ใช้คำนวณ duration และ timeline analysis

5. **`end_date`**: เวลาที่ task จบการทำงาน
   - **เหตุผล**: Actual execution end time
   - **ความสำคัญ**: ใช้คำนวณ duration

6. **`Duration (s)`**: ระยะเวลาที่ task ใช้ (วินาที)
   - **Formula**: `EXTRACT(EPOCH FROM (COALESCE(end_date, NOW()) - start_date))`
   - **`COALESCE(end_date, NOW())`**: ถ้า task ยังไม่จบ ใช้เวลาปัจจุบัน
   - **ความสำคัญ**: **Performance metric** - identify slow tasks
   - **Visualization**: แสดงเป็น gradient gauge (เขียว < 60s, เหลือง 60-300s, แดง > 300s)

7. **`try_number`**: จำนวนครั้งที่ task ถูก execute
   - **เหตุผล**: บอกว่า task retry กี่ครั้ง (1 = ครั้งแรก, 2 = retry 1 ครั้ง)
   - **ความสำคัญ**: **Reliability indicator** - try_number สูง = มีปัญหา

8. **`max_tries`**: จำนวนครั้งสูงสุดที่ task สามารถ retry ได้
   - **เหตุผล**: Configuration reference
   - **ความสำคัญ**: เปรียบเทียบกับ try_number เพื่อดูว่าใกล้ถึง limit หรือยัง

9. **`operator`**: ชื่อ operator class ที่ task ใช้
   - **เหตุผล**: บอกว่า task ใช้ technology อะไร (PythonOperator, BashOperator, etc.)
   - **ความสำคัญ**: **Technical context** - ช่วยในการ troubleshooting

10. **`pool`**: Pool ที่ task ใช้
    - **เหตุผล**: บอกว่า task ใช้ resource pool ไหน
    - **ความสำคัญ**: **Resource allocation context** - เข้าใจ resource constraints

11. **`priority_weight`**: ค่า priority ของ task
    - **เหตุผล**: บอกว่า task นี้มี priority เท่าไหร่ในการ schedule
    - **ความสำคัญ**: **Scheduling context** - เข้าใจ execution order

**Table Features**:
- **Sorting**: Default เรียงตาม Start Date (ล่าสุดก่อน)
- **Color coding**: State column แสดงสีตามสถานะ
- **Gradient gauge**: Duration column แสดง gradient ตาม threshold
- **Deep links**: Task ID มี link ไปยัง Airflow UI

#### 📊 Statistics Panels

**1. Total Tasks**
```sql
SELECT COUNT(*) as "Total Tasks" 
FROM task_instance 
WHERE dag_id = '$dag_id' 
  AND start_date >= $__timeFrom() 
  AND start_date <= $__timeTo();
```

**คำอธิบาย**:
- **เหตุผล**: นับจำนวน task executions ทั้งหมดของ DAG ที่เลือก
- **ความสำคัญ**: **Workload metric** - บอกว่า DAG นี้มี task executions เท่าไหร่

**2. Success Tasks**
```sql
SELECT COUNT(*) as "Success Tasks" 
FROM task_instance 
WHERE dag_id = '$dag_id' 
  AND state = 'success' 
  AND start_date >= $__timeFrom() 
  AND start_date <= $__timeTo();
```

**คำอธิบาย**:
- **เหตุผล**: นับ tasks ที่ทำงานสำเร็จ
- **ความสำคัญ**: **Success indicator** - วัด reliability ของ DAG
- **Visualization**: แสดงเป็น stat panel สีเขียว

**3. Failed Tasks**
```sql
SELECT COUNT(*) as "Failed Tasks" 
FROM task_instance 
WHERE dag_id = '$dag_id' 
  AND state = 'failed' 
  AND start_date >= $__timeFrom() 
  AND start_date <= $__timeTo();
```

**คำอธิบาย**:
- **เหตุผล**: นับ tasks ที่ล้มเหลว
- **ความสำคัญ**: **Failure indicator** - ต้อง investigate ถ้ามีค่าสูง
- **Visualization**: แสดงเป็น stat panel สีแดง

**4. Avg Task Duration**
```sql
SELECT ROUND(AVG(EXTRACT(EPOCH FROM (end_date - start_date)))::numeric, 2) as "Avg Duration" 
FROM task_instance 
WHERE dag_id = '$dag_id' 
  AND state = 'success' 
  AND start_date >= $__timeFrom() 
  AND start_date <= $__timeTo() 
  AND end_date IS NOT NULL;
```

**คำอธิบาย**:
- **เหตุผล**: คำนวณเวลาเฉลี่ยที่ tasks ใช้ในการทำงาน
- **`ROUND(..., 2)`**: ปัดเป็น 2 ทศนิยม
- **`WHERE state = 'success'`**: นับเฉพาะ success tasks เพื่อได้ baseline ที่แท้จริง
- **ความสำคัญ**: **Performance baseline** - ใช้เป็น reference สำหรับ SLA
- **Visualization**: แสดงเป็น stat panel สีน้ำเงิน พร้อม unit "s" (seconds)

#### 🎯 Variables Configuration

**1. Variable: `$dag_id`**
- **Type**: Query variable
- **Query**: `SELECT dag_id FROM dag WHERE bundle_name IS NOT NULL ORDER BY dag_id`
- **เหตุผล**: Query DAG IDs จาก database แบบ dynamic
- **Refresh**: On dashboard load
- **ความสำคัญ**: **Core feature** - ทำให้ dashboard เป็น interactive

**2. Variable: `$airflow_url`**
- **Type**: Textbox variable
- **Default**: `http://localhost:30080`
- **เหตุผล**: ใช้สำหรับสร้าง deep links ไปยัง Airflow UI
- **ความสำคัญ**: **UX enhancement** - click-through navigation

#### 🔄 Workflow

**การใช้งาน Dashboard**:
1. เปิด dashboard "Airflow DAG Tasks Explorer"
2. เลือก DAG จาก dropdown `$dag_id` ด้านบน
3. เลือก time range ที่ต้องการ (Last 24h, 7d, etc.)
4. ดู statistics panels เพื่อเห็นภาพรวม
5. ดู main table เพื่อเห็น task-level details
6. Click ที่ Task ID เพื่อ drill-down ไปยัง Airflow UI

**Use Cases**:

1. **Troubleshooting Failed Tasks**:
   - เลือก DAG ที่มีปัญหา
   - ดู Failed Tasks count
   - Filter table โดย State = 'failed'
   - ดู Try Number เพื่อเห็น retry pattern
   - Click Task ID เพื่อดู logs ใน Airflow UI

2. **Performance Analysis**:
   - เลือก DAG ที่ต้องการวิเคราะห์
   - ดู Avg Task Duration
   - Sort table ตาม Duration (s) จากมากไปน้อย
   - Identify slow tasks ที่ต้อง optimize

3. **Retry Pattern Investigation**:
   - ดู tasks ที่มี Try Number > 1
   - วิเคราะห์ว่า tasks ไหน retry บ่อย
   - Check Operator และ Pool เพื่อหา pattern

4. **Resource Utilization**:
   - ดู Pool column เพื่อเห็น resource allocation
   - ดู Priority Weight เพื่อเข้าใจ scheduling order
   - วิเคราะห์ว่า tasks ใช้ pools อย่างมีประสิทธิภาพหรือไม่

**Business Value**:
- **Focused analysis**: ดู tasks ของ DAG เดียวโดยเฉพาะ ไม่ต้องกรองข้อมูลจาก dashboards อื่น
- **Quick troubleshooting**: เห็น task failures และ retries ทันที
- **Performance insights**: เข้าใจ task-level performance ของแต่ละ DAG
- **Interactive exploration**: เลือก DAG ได้ตามต้องการ ไม่ต้องสร้าง dashboard ใหม่

**Key Differences จาก Dashboard อื่น**:

| Feature | DAG Tasks Explorer | DAGs Dashboard | Task Performance |
|---------|-------------------|----------------|------------------|
| **Scope** | Tasks ของ 1 DAG | ทุก DAGs | ทุก Tasks |
| **Filtering** | Interactive DAG selection | ไม่มี variable | ไม่มี variable |
| **Focus** | Task-level details | DAG-level overview | Aggregate performance |
| **Use Case** | Drill-down analysis | Operational overview | Performance trends |
| **Granularity** | Individual task instances | DAG runs | Aggregated metrics |

**Best Practices**:
- ใช้ dashboard นี้เมื่อต้องการ **deep dive** ใน DAG เดียว
- ใช้ร่วมกับ "Airflow DAGs Dashboard" สำหรับ identify problematic DAGs ก่อน
- ตั้ง time range ให้เหมาะสม - ใช้ 24h สำหรับ recent issues, 7d สำหรับ trend analysis
- Sort table ตาม columns ต่างๆ เพื่อหา patterns (เช่น sort ตาม Duration เพื่อหา slow tasks)
- ใช้ deep links ไปยัง Airflow UI สำหรับดู logs และ detailed information
- Monitor Try Number เพื่อ identify tasks ที่มี reliability issues

**Limitations**:
- แสดงได้ครั้งละ 1 DAG (ไม่สามารถเปรียบเทียบหลาย DAGs พร้อมกัน)
- Limit 100 task instances ต่อ query (ถ้าต้องการดูมากกว่านี้ต้องปรับ time range)
- ต้องเลือก DAG manually (ไม่ auto-detect problematic DAGs)

**Tips**:
- ใช้ร่วมกับ "Airflow Error & Debugging Dashboard" เพื่อ identify DAGs ที่มีปัญหาก่อน
- Bookmark dashboard พร้อม DAG ID สำหรับ DAGs ที่ monitor บ่อยๆ
- ใช้ Grafana's "Share" feature เพื่อแชร์ view ของ specific DAG กับทีม

---

### 9️⃣ Airflow Job Flow Visualization

**วัตถุประสงค์**: Dashboard สำหรับ visualize job flow, dependency chains, และ detect performance anomalies แบบ Control-M style เพื่อ monitor DAG dependencies และ identify bottlenecks

**Data Source**: Airflow PostgreSQL

**เหตุผลในการใช้ Dashboard นี้**:
- **Job Flow Monitoring**: เห็น flow ของ DAGs ที่ต่อกันผ่าน asset dependencies (เหมือน Control-M Viewpoint)
- **Performance Anomaly Detection**: ตรวจจับ DAGs ที่ทำงานช้ากว่าปกติด้วย statistical analysis
- **Critical Path Analysis**: Identify DAGs ที่มี downstream impact สูง
- **Dependency Chain Visibility**: เห็น producer → asset → consumer relationships

**Key Features**:
- **Anomaly Detection**: ใช้ statistical baseline (mean + 2σ) ตรวจจับ performance degradation
- **Impact Analysis**: แสดง downstream impact ของแต่ละ DAG
- **Dependency Mapping**: แสดง DAG dependencies ผ่าน assets
- **Trend Analysis**: Time series ของ DAG duration เพื่อ detect regressions

**Panels และ SQL Queries**:

#### 📊 Statistics Panels

**1. Total DAGs**
```sql
SELECT COUNT(DISTINCT dag_id) as "Total DAGs" 
FROM dag 
WHERE bundle_name IS NOT NULL;
```

**2. Running DAGs**
```sql
SELECT COUNT(DISTINCT dag_id) as "Running DAGs" 
FROM dag_run 
WHERE state = 'running';
```

**3. DAGs with Dependencies**
```sql
SELECT COUNT(DISTINCT dag_id) as "DAGs with Dependencies" 
FROM dag_schedule_asset_reference;
```

**4. Total Assets**
```sql
SELECT COUNT(DISTINCT id) as "Total Assets" 
FROM asset;
```

#### 📋 Job Flow Status (with Performance Anomaly Detection)

**Main Table Query:**
```sql
WITH dag_stats AS (
  SELECT 
    dag_id,
    AVG(EXTRACT(EPOCH FROM (end_date - start_date))) as avg_duration,
    STDDEV(EXTRACT(EPOCH FROM (end_date - start_date))) as stddev_duration
  FROM dag_run
  WHERE state = 'success'
    AND start_date > NOW() - INTERVAL '7 days'
    AND end_date IS NOT NULL
  GROUP BY dag_id
),
recent_runs AS (
  SELECT 
    dr.dag_id,
    dr.run_id,
    dr.state,
    dr.start_date,
    dr.end_date,
    EXTRACT(EPOCH FROM (COALESCE(dr.end_date, NOW()) - dr.start_date)) as duration
  FROM dag_run dr
  WHERE dr.start_date >= $__timeFrom()
    AND dr.start_date <= $__timeTo()
)
SELECT 
  r.dag_id as "DAG ID",
  r.run_id as "Run ID",
  r.state as "Status",
  r.start_date as "Start Date",
  r.end_date as "End Date",
  ROUND(r.duration::numeric, 2) as "Duration (s)",
  ROUND(COALESCE(s.avg_duration, 0)::numeric, 2) as "Avg Duration (s)",
  CASE 
    WHEN s.avg_duration IS NULL THEN 'Normal'
    WHEN r.duration > (s.avg_duration + 2 * COALESCE(s.stddev_duration, 0)) THEN 'Critical'
    WHEN r.duration > (s.avg_duration + COALESCE(s.stddev_duration, 0)) THEN 'Slow'
    ELSE 'Normal'
  END as "Performance",
  ROUND(((r.duration - COALESCE(s.avg_duration, r.duration)) / NULLIF(s.avg_duration, 0) * 100)::numeric, 1) as "% vs Baseline"
FROM recent_runs r
LEFT JOIN dag_stats s ON r.dag_id = s.dag_id
ORDER BY r.start_date DESC
LIMIT 100;
```

**คำอธิบายแต่ละส่วน**:

1. **CTE: `dag_stats`** - คำนวณ baseline performance
   - **`AVG(duration)`**: เวลาเฉลี่ยของ DAG runs ใน 7 วันที่ผ่านมา
   - **`STDDEV(duration)`**: Standard deviation สำหรับ anomaly detection
   - **เหตุผล**: ใช้เป็น baseline สำหรับเปรียบเทียบ current performance
   - **ความสำคัญ**: **Statistical baseline** - ไม่ใช่ hardcoded threshold

2. **CTE: `recent_runs`** - ดึง recent DAG runs
   - **Time window**: ใช้ Grafana time range variables
   - **`COALESCE(end_date, NOW())`**: Handle running DAGs
   - **เหตุผล**: Focus ที่ recent executions
   - **ความสำคัญ**: Real-time monitoring data

3. **Performance Classification**:
   ```sql
   CASE 
     WHEN duration > (avg + 2σ) THEN 'Critical'  -- > 95th percentile
     WHEN duration > (avg + σ) THEN 'Slow'       -- > 68th percentile
     ELSE 'Normal'
   END
   ```
   - **Critical**: Duration เกิน mean + 2 standard deviations (statistical anomaly)
   - **Slow**: Duration เกิน mean + 1 standard deviation (warning)
   - **Normal**: Duration อยู่ใน expected range
   - **เหตุผล**: ใช้ statistical approach แทน fixed thresholds
   - **ความสำคัญ**: **Adaptive thresholds** - ปรับตาม historical data

4. **% vs Baseline**:
   - **Formula**: `(current - baseline) / baseline * 100`
   - **เหตุผล**: แสดง percentage deviation จาก baseline
   - **ความสำคัญ**: **Intuitive metric** - ง่ายต่อการเข้าใจว่าช้าขึ้นกี่เปอร์เซ็นต์

**Visualization Features**:
- **Status column**: Color-coded (เขียว=success, แดง=failed, น้ำเงิน=running, เหลือง=queued)
- **Performance column**: Color-coded (เขียว=Normal, เหลือง=Slow, แดง=Critical)
- **Duration column**: Gradient gauge (เขียว < 300s, เหลือง 300-600s, แดง > 600s)
- **Deep links**: DAG ID links ไปยัง Airflow UI

#### 🔗 DAG Dependency Chain (Producer → Asset → Consumer)

```sql
WITH asset_producers AS (
  SELECT DISTINCT
    ti.dag_id,
    a.id as asset_id,
    a.uri as asset_uri,
    a.name as asset_name
  FROM task_instance ti
  JOIN asset_event ae ON ae.source_task_id = ti.task_id 
    AND ae.source_dag_id = ti.dag_id
  JOIN asset a ON ae.asset_id = a.id
  WHERE ti.start_date >= $__timeFrom()
    AND ti.start_date <= $__timeTo()
),
asset_consumers AS (
  SELECT DISTINCT
    dsar.dag_id,
    dsar.asset_id,
    a.uri as asset_uri,
    a.name as asset_name
  FROM dag_schedule_asset_reference dsar
  JOIN asset a ON dsar.asset_id = a.id
)
SELECT 
  p.dag_id as "Producer DAG",
  p.asset_uri as "Asset URI",
  COALESCE(p.asset_name, 'Unnamed') as "Asset Name",
  c.dag_id as "Consumer DAG",
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM dag_run 
      WHERE dag_id = c.dag_id 
        AND state = 'running'
    ) THEN 'Running'
    WHEN EXISTS (
      SELECT 1 FROM dag_run 
      WHERE dag_id = c.dag_id 
        AND state = 'queued'
    ) THEN 'Queued'
    ELSE 'Idle'
  END as "Consumer Status"
FROM asset_producers p
JOIN asset_consumers c ON p.asset_id = c.asset_id
ORDER BY p.dag_id, c.dag_id
LIMIT 100;
```

**คำอธิบาย**:

1. **CTE: `asset_producers`** - หา DAGs ที่ produce assets
   - **Join `asset_event`**: เชื่อมกับ events ที่ tasks สร้าง assets
   - **`source_task_id` และ `source_dag_id`**: Identify producer
   - **เหตุผล**: ติดตาม DAGs ที่สร้าง data/assets
   - **ความสำคัญ**: **Upstream identification** - รู้ว่า data มาจากไหน

2. **CTE: `asset_consumers`** - หา DAGs ที่ consume assets
   - **Table `dag_schedule_asset_reference`**: DAGs ที่ depend on assets
   - **เหตุผล**: ติดตาม DAGs ที่รอ assets เพื่อ trigger
   - **ความสำคัญ**: **Downstream identification** - รู้ว่า data ไปที่ไหน

3. **Consumer Status**:
   - **Running**: Consumer DAG กำลังทำงาน
   - **Queued**: Consumer DAG รอ execution
   - **Idle**: Consumer DAG ไม่ได้ทำงาน
   - **เหตุผล**: Real-time status ของ downstream DAGs
   - **ความสำคัญ**: **Flow visibility** - เห็น data flow แบบ real-time

**Business Value**:
- **Dependency Mapping**: เห็น producer → asset → consumer chain
- **Impact Analysis**: รู้ว่าถ้า producer fail จะกระทบ consumer ไหนบ้าง
- **Troubleshooting**: Debug dependency issues ได้ง่าย
- **Data Lineage**: ติดตาม data flow ผ่าน assets

#### 🎯 Critical Path Analysis (DAGs with High Downstream Impact)

```sql
WITH asset_producers AS (
  SELECT DISTINCT
    ti.dag_id,
    ae.asset_id
  FROM task_instance ti
  JOIN asset_event ae ON ae.source_task_id = ti.task_id 
    AND ae.source_dag_id = ti.dag_id
  WHERE ti.start_date >= $__timeFrom()
    AND ti.start_date <= $__timeTo()
),
downstream_counts AS (
  SELECT 
    p.dag_id,
    COUNT(DISTINCT dsar.dag_id) as downstream_count
  FROM asset_producers p
  JOIN dag_schedule_asset_reference dsar ON p.asset_id = dsar.asset_id
  GROUP BY p.dag_id
),
dag_performance AS (
  SELECT 
    dag_id,
    AVG(EXTRACT(EPOCH FROM (end_date - start_date))) as avg_duration
  FROM dag_run
  WHERE state = 'success'
    AND start_date > NOW() - INTERVAL '7 days'
    AND end_date IS NOT NULL
  GROUP BY dag_id
)
SELECT 
  dc.dag_id as "DAG ID",
  dc.downstream_count as "Downstream Count",
  ROUND(COALESCE(dp.avg_duration, 0)::numeric, 2) as "Avg Duration (s)",
  ROUND((dc.downstream_count * COALESCE(dp.avg_duration, 0))::numeric, 2) as "Total Impact (s)",
  CASE 
    WHEN dc.downstream_count >= 5 THEN 'High'
    WHEN dc.downstream_count >= 2 THEN 'Medium'
    ELSE 'Low'
  END as "Impact Level"
FROM downstream_counts dc
LEFT JOIN dag_performance dp ON dc.dag_id = dp.dag_id
ORDER BY dc.downstream_count DESC, dp.avg_duration DESC
LIMIT 20;
```

**คำอธิบาย**:

1. **Downstream Count**: จำนวน DAGs ที่ depend on DAG นี้
   - **เหตุผล**: วัด impact radius
   - **ความสำคัญ**: **Critical path indicator** - DAG ที่มี downstream เยอะ = critical

2. **Total Impact (s)**: `downstream_count × avg_duration`
   - **Formula**: จำนวน downstream × เวลาเฉลี่ยของ DAG
   - **เหตุผล**: Estimate total time impact ถ้า DAG นี้ล่าช้า
   - **ความสำคัญ**: **Business impact metric** - วัดผลกระทบต่อ overall pipeline

3. **Impact Level Classification**:
   - **High**: ≥ 5 downstream DAGs
   - **Medium**: 2-4 downstream DAGs
   - **Low**: < 2 downstream DAGs
   - **เหตุผล**: Prioritize monitoring และ optimization efforts
   - **ความสำคัญ**: **Risk assessment** - DAGs ที่ impact สูงต้อง monitor ใกล้ชิด

**Business Value**:
- **Optimization Priority**: รู้ว่าควร optimize DAG ไหนก่อน (high impact DAGs)
- **Risk Management**: Identify critical DAGs ที่ต้อง monitor ใกล้ชิด
- **Capacity Planning**: เข้าใจ dependencies เพื่อวางแผน resources
- **SLA Planning**: DAGs ที่มี high impact ต้องมี strict SLAs

#### 📈 DAG Duration Trend (Detect Performance Degradation)

```sql
SELECT 
  DATE_TRUNC('hour', start_date) as time,
  dag_id as metric,
  AVG(EXTRACT(EPOCH FROM (end_date - start_date))) as value
FROM dag_run
WHERE state = 'success'
  AND start_date >= $__timeFrom()
  AND start_date <= $__timeTo()
  AND end_date IS NOT NULL
GROUP BY DATE_TRUNC('hour', start_date), dag_id
ORDER BY time;
```

**คำอธิบาย**:
- **Time series visualization**: แสดง duration trends over time
- **Hourly aggregation**: Balance ระหว่าง granularity และ readability
- **Per-DAG metrics**: แยกแสดงแต่ละ DAG เป็น separate line
- **ความสำคัญ**: **Trend detection** - เห็น performance degradation over time

**Use Cases**:
- **Regression Detection**: เห็นว่า duration เพิ่มขึ้นหลัง deployment
- **Pattern Recognition**: เห็น peak hours ที่ DAGs ทำงานช้า
- **Capacity Planning**: เข้าใจ performance trends เพื่อวางแผน scaling

#### 🔄 Workflow: การใช้งาน Dashboard

**1. Monitor Job Flow Status**:
- เปิด dashboard "Airflow Job Flow Visualization"
- ดู statistics panels เพื่อเห็นภาพรวม
- ดู main table เพื่อเห็น DAG runs พร้อม performance classification
- **Focus**: DAGs ที่มี Performance = "Critical" หรือ "Slow"

**2. Investigate Performance Anomalies**:
- Filter table โดย Performance = "Critical"
- ดู "% vs Baseline" เพื่อเห็น deviation
- Click DAG ID เพื่อ drill-down ไปยัง Airflow UI
- Check logs และ identify root cause

**3. Analyze Dependency Impact**:
- ดู "DAG Dependency Chain" table
- Identify producer DAGs ที่ล่าช้า
- Check Consumer Status เพื่อเห็น downstream impact
- **Action**: ถ้า producer slow → consumers จะ delayed

**4. Identify Critical Path**:
- ดู "Critical Path Analysis" table
- Sort by "Downstream Count" หรือ "Total Impact"
- **Focus**: DAGs ที่มี Impact Level = "High"
- **Action**: Prioritize optimization และ monitoring

**5. Detect Performance Trends**:
- ดู "DAG Duration Trend" chart
- Identify DAGs ที่ duration เพิ่มขึ้นเรื่อยๆ
- Correlate กับ deployments หรือ data volume changes
- **Action**: Investigate และ optimize ก่อนกระทบ SLA

#### 🚨 Alert Use Cases (สำหรับ Grafana Alerting)

**Alert 1: Performance Anomaly Detected**
```yaml
Condition: Performance = "Critical"
Threshold: > 0 DAGs
Duration: 5 minutes
Action: Send email/Teams notification
Message: |
  🚨 Performance Anomaly Detected
  DAG: {{ dag_id }}
  Current Duration: {{ duration }}s
  Baseline: {{ avg_duration }}s
  Deviation: +{{ percentage }}%
```

**Alert 2: High Impact DAG Delayed**
```yaml
Condition: (Impact Level = "High") AND (Performance != "Normal")
Threshold: > 0 DAGs
Duration: 10 minutes
Action: Send email/Teams notification
Message: |
  ⚠️ Critical Path DAG Delayed
  DAG: {{ dag_id }}
  Downstream Impact: {{ downstream_count }} DAGs
  Estimated Total Delay: {{ total_impact }}s
```

**Alert 3: Dependency Chain Broken**
```yaml
Condition: Producer DAG failed AND has downstream consumers
Threshold: > 0 failures
Duration: 1 minute
Action: Send email/Teams notification
Message: |
  🔴 Dependency Chain Broken
  Producer DAG: {{ producer_dag }}
  Failed Asset: {{ asset_uri }}
  Affected Consumers: {{ consumer_dags }}
```

#### 💡 Best Practices

**Monitoring**:
- ตรวจสอบ dashboard ทุกวันเพื่อ identify performance anomalies
- Focus ที่ DAGs ที่มี "Critical" performance classification
- Monitor Critical Path DAGs ใกล้ชิดเพราะมี high downstream impact
- ตั้ง alerts สำหรับ performance anomalies และ dependency failures

**Optimization**:
- Prioritize optimization ของ DAGs ที่มี:
  - High downstream count (critical path)
  - Frequent "Critical" or "Slow" classifications
  - Increasing duration trends
- Use "% vs Baseline" เพื่อ quantify improvement หลัง optimization

**Troubleshooting**:
- เมื่อเห็น performance anomaly:
  1. Check "DAG Dependency Chain" เพื่อเห็น upstream/downstream
  2. Check "Critical Path Analysis" เพื่อประเมิน business impact
  3. Use deep links ไปยัง Airflow UI เพื่อดู logs
  4. Investigate root cause (data volume, resource contention, code changes)

**Capacity Planning**:
- ใช้ "Total Impact" metric เพื่อ prioritize resource allocation
- Monitor duration trends เพื่อ predict future capacity needs
- Identify peak hours จาก time series chart

#### 🎯 Key Differences จาก Dashboard อื่น

| Feature | Job Flow Visualization | DAGs Dashboard | Dependencies Dashboard |
|---------|------------------------|----------------|------------------------|
| **Focus** | Performance anomalies + dependencies | Operational status | Static dependencies |
| **Anomaly Detection** | ✅ Statistical baseline | ❌ | ❌ |
| **Critical Path** | ✅ Impact analysis | ❌ | ❌ |
| **Real-time Flow** | ✅ Producer→Consumer status | ❌ | Partial |
| **Use Case** | Performance monitoring + impact analysis | Daily operations | Dependency mapping |
| **Alert Ready** | ✅ Anomaly-based alerts | Manual monitoring | Manual monitoring |

#### 🔔 Integration with Control-M Style Monitoring

Dashboard นี้ออกแบบมาเพื่อทำงานคล้าย **Control-M Viewpoint**:

**Similar Features**:
- ✅ Job flow visualization
- ✅ Dependency chain tracking
- ✅ Performance anomaly detection
- ✅ Critical path identification
- ✅ Real-time status monitoring

**Enhanced Features** (เหนือกว่า Control-M):
- 📊 Statistical anomaly detection (adaptive thresholds)
- 🎯 Quantified impact analysis (Total Impact metric)
- 📈 Historical trend analysis
- 🔗 Deep links to detailed views
- 💰 Open source (no licensing costs)

**Best Practices**:
- ใช้ dashboard นี้เป็น **primary monitoring dashboard** สำหรับ operations team
- ตั้ง alerts สำหรับ performance anomalies และ dependency failures
- Review Critical Path Analysis ทุกสัปดาห์เพื่อ prioritize optimization
- Use dependency chain information สำหรับ impact analysis เมื่อมีปัญหา
- Monitor duration trends เพื่อ proactive capacity planning

---

### 🎨 Grid Layout Options

#### ปัญหา
Grafana Table Panel แสดงเป็นตารางแนวตั้ง ไม่ใช่ grid แนวนอนแบบที่ต้องการ

#### ตัวเลือกที่มี

**1. ✅ Static Grid (ปัจจุบัน - ใช้งานได้)**
- สร้าง 80 panels แยกกัน (1 panel ต่อ 1 DAG)
- แสดงเป็น grid layout สวยงาม
- **ข้อดี**: Visual clarity สูง, เหมาะสำหรับ operations monitoring
- **ข้อเสีย**: ต้อง regenerate เมื่อมี DAG เพิ่ม/ลด

**2. ❌ Dynamic Table (ทดสอบแล้ว - ไม่เป็น grid)**
- ใช้ 1 panel query จาก database
- Dynamic 100% ไม่ต้อง regenerate
- **ข้อดี**: Auto-update เมื่อมี DAG เปลี่ยน
- **ข้อเสีย**: แสดงเป็นตารางแนวตั้ง ไม่ใช่ grid

**3. 🔄 Hybrid: Dynamic + Auto-regenerate (แนะนำ)**
- ใช้ static grid panels
- มี script auto-regenerate เมื่อ detect DAG เพิ่ม/ลด
- Run เป็น CronJob ใน Kubernetes (เช่น ทุก 5 นาที)
- **ข้อดี**: ได้ทั้ง grid layout และ dynamic behavior
- **ข้อเสีย**: ต้อง maintain regeneration script

**4. 🎨 Bar Gauge Grid (ทางเลือก)**
- ใช้ Bar Gauge panel แทน Stat panel
- แสดงเป็นแถบสีแนวนอน
- Dynamic query ได้
- **ข้อดี**: Dynamic และ visual
- **ข้อเสีย**: ไม่เหมือน grid ในรูปที่ต้องการ 100%

**5. 🔌 Grafana Plugin (ต้องติดตั้งเพิ่ม)**
- ใช้ plugin เช่น "Discrete Panel" หรือ "Status Panel"
- รองรับ grid layout + dynamic query
- **ข้อดี**: Purpose-built สำหรับ use case นี้
- **ข้อเสีย**: ต้องติดตั้ง plugin เพิ่ม, อาจมี compatibility issues

#### 💡 คำแนะนำ

**สำหรับ Production**: ใช้ตัวเลือก #3 (Hybrid)
- Grid layout สวยงาม ✅
- Auto-update เมื่อมี DAG เพิ่ม/ลด ✅
- ไม่ต้อง manual regenerate ✅
- Scalable และ maintainable

**สำหรับ Testing/Development**: ใช้ตัวเลือก #1 (Static Grid)
- ใช้งานได้ทันที
- Regenerate ด้วยมือเมื่อจำเป็น
- เหมาะสำหรับ environment ที่ DAGs ไม่เปลี่ยนบ่อย

---

### 🔟 Airflow SLA & Baseline Monitoring Dashboard

**วัตถุประสงค์**: ติดตาม SLA compliance และเปรียบเทียบ actual performance กับ baseline statistics เพื่อ detect performance degradation และ SLA violations

**Data Sources**: 
- **Airflow Extension PostgreSQL** - `task_baseline` table (baseline statistics)
- **Airflow PostgreSQL** - `task_instance` table (actual execution data)

**เหตุผลในการใช้ Baseline Monitoring**:
- **Proactive Detection**: ตรวจจับ performance issues ก่อนที่จะกลายเป็นปัญหาใหญ่
- **Data-Driven SLA**: ใช้ statistical baseline (P95) แทนการตั้ง SLA แบบ arbitrary
- **Trend Analysis**: เปรียบเทียบ actual vs baseline เพื่อเห็น performance trends
- **Capacity Planning**: ใช้ baseline data วางแผน resource allocation

**Architecture**:
```
baseline_compute_daily DAG (รันทุก 5 นาที)
    ↓
Extract task history (14 days)
    ↓
Compute percentiles (P50, P90, P95, P99)
    ↓
Store in task_baseline table
    ↓
Dashboard queries JOIN task_instance + task_baseline
```

---

#### 📊 Panels และ SQL Queries

**1. SLA Compliance Rate**
```sql
SELECT 
  ROUND(
    ((COUNT(*) FILTER (WHERE actual_duration <= p95_seconds) * 100.0) / NULLIF(COUNT(*), 0))::numeric,
    2
  ) as sla_compliance_rate
FROM (
  SELECT 
    ti.dag_id,
    ti.task_id,
    ti.duration as actual_duration,
    tb.p95_seconds
  FROM task_instance ti
  JOIN task_baseline tb 
    ON ti.dag_id = tb.dag_id 
    AND ti.task_id = tb.task_id
    AND tb.baseline_key = 'default'
  WHERE ti.start_date BETWEEN $__timeFrom() AND $__timeTo()
    AND ti.state = 'success'
    AND ti.duration IS NOT NULL
) t;
```

**คำอธิบาย**:
- **`COUNT(*) FILTER (WHERE actual_duration <= p95_seconds)`**: นับ tasks ที่รันเสร็จภายใน P95 baseline (ถือว่า meet SLA)
- **`p95_seconds`**: Baseline P95 จาก `task_baseline` table (คำนวณจาก 14 วันย้อนหลัง)
- **`baseline_key = 'default'`**: Filter baseline context (รองรับหลาย baseline contexts)
- **`$__timeFrom()` และ `$__timeTo()`**: Grafana time range variables (dynamic time selection)
- **ความสำคัญ**: **Primary SLA metric** - วัดว่ากี่ % ของ tasks ที่ meet SLA target

**Business Value**:
- SLA compliance > 95% = ระบบทำงานตาม expectation
- SLA compliance < 90% = มี performance issues ต้องแก้ไขด่วน
- Trend analysis: ถ้า compliance ลดลงเรื่อยๆ แสดงว่ามี degradation

---

**2. Total Tasks**
```sql
SELECT COUNT(*) as total_tasks
FROM task_instance
WHERE start_date BETWEEN $__timeFrom() AND $__timeTo()
  AND state IN ('success', 'failed', 'running');
```

**คำอธิบาย**:
- นับจำนวน tasks ทั้งหมดที่รันใน time range ที่เลือก
- รวมทั้ง success, failed, และ running states
- ใช้เป็น denominator สำหรับคำนวณ percentages

---

**3. SLA Violations**
```sql
SELECT COUNT(*) as sla_violations
FROM (
  SELECT 
    ti.dag_id,
    ti.task_id,
    ti.duration as actual_duration,
    tb.p95_seconds
  FROM task_instance ti
  JOIN task_baseline tb 
    ON ti.dag_id = tb.dag_id 
    AND ti.task_id = tb.task_id
    AND tb.baseline_key = 'default'
  WHERE ti.start_date BETWEEN $__timeFrom() AND $__timeTo()
    AND ti.state = 'success'
    AND ti.duration IS NOT NULL
    AND ti.duration > tb.p95_seconds
) t;
```

**คำอธิบาย**:
- **`ti.duration > tb.p95_seconds`**: Tasks ที่รันช้ากว่า P95 baseline (SLA violation)
- **ความสำคัญ**: **Alert trigger metric** - ใช้ตั้ง alert เมื่อ violations เกิน threshold

**Business Value**:
- Violations = 0: Perfect performance
- Violations < 5% of total: Acceptable (อยู่ใน P95 definition)
- Violations > 10%: Performance degradation ต้องสอบสวน

---

**4. At Risk Tasks (>80% baseline)**
```sql
SELECT COUNT(*) as at_risk_tasks
FROM (
  SELECT 
    ti.dag_id,
    ti.task_id,
    ti.duration as actual_duration,
    tb.p95_seconds
  FROM task_instance ti
  JOIN task_baseline tb 
    ON ti.dag_id = tb.dag_id 
    AND ti.task_id = tb.task_id
    AND tb.baseline_key = 'default'
  WHERE ti.state = 'running'
    AND ti.start_date IS NOT NULL
    AND (EXTRACT(EPOCH FROM (NOW() - ti.start_date))) > (tb.p95_seconds * 0.8)
    AND (EXTRACT(EPOCH FROM (NOW() - ti.start_date))) <= tb.p95_seconds
) t;
```

**คำอธิบาย**:
- **`EXTRACT(EPOCH FROM (NOW() - ti.start_date))`**: Running time ของ task ที่กำลังรันอยู่
- **`> (tb.p95_seconds * 0.8)`**: Tasks ที่รันไปแล้ว > 80% ของ baseline
- **`<= tb.p95_seconds`**: แต่ยังไม่เกิน P95 (ยังไม่ violate แต่ใกล้แล้ว)
- **ความสำคัญ**: **Early warning metric** - tasks ที่กำลังจะ violate SLA

**Business Value**:
- Proactive monitoring: แจ้งเตือนก่อน SLA violation เกิดขึ้น
- ให้เวลา operations team แก้ไขปัญหาทันเวลา

---

**5. SLA Compliance Trend**
```sql
SELECT 
  DATE_TRUNC('hour', ti.start_date) as time,
  ROUND(
    ((COUNT(*) FILTER (WHERE ti.duration <= tb.p95_seconds) * 100.0) / NULLIF(COUNT(*), 0))::numeric,
    2
  ) as "SLA Compliance %"
FROM task_instance ti
JOIN task_baseline tb 
  ON ti.dag_id = tb.dag_id 
  AND ti.task_id = tb.task_id
  AND tb.baseline_key = 'default'
WHERE ti.start_date BETWEEN $__timeFrom() AND $__timeTo()
  AND ti.state = 'success'
  AND ti.duration IS NOT NULL
GROUP BY DATE_TRUNC('hour', ti.start_date)
ORDER BY time;
```

**คำอธิบาย**:
- **`DATE_TRUNC('hour', ti.start_date)`**: Group by hour สำหรับ time series
- **`ROUND(...::numeric, 2)`**: Cast เป็น numeric ก่อน round (PostgreSQL requirement)
- **ความสำคัญ**: **Trend analysis** - เห็น SLA compliance เปลี่ยนแปลงตามเวลา

**Business Value**:
- Identify peak hours ที่มี SLA violations สูง
- Detect performance degradation trends
- Validate optimization efforts (ดู compliance เพิ่มขึ้นหลัง optimize)

---

**6. Task Duration Distribution**
```sql
SELECT 
  CASE 
    WHEN ti.duration <= tb.p50_seconds THEN 'Fast (≤P50)'
    WHEN ti.duration <= tb.p95_seconds THEN 'Normal (P50-P95)'
    ELSE 'Slow (>P95)'
  END as "Performance Category",
  COUNT(*) as "Task Count"
FROM task_instance ti
JOIN task_baseline tb 
  ON ti.dag_id = tb.dag_id 
  AND ti.task_id = tb.task_id
  AND tb.baseline_key = 'default'
WHERE ti.start_date BETWEEN $__timeFrom() AND $__timeTo()
  AND ti.state = 'success'
  AND ti.duration IS NOT NULL
GROUP BY "Performance Category"
ORDER BY "Task Count" DESC;
```

**คำอธิบาย**:
- **`CASE WHEN`**: Categorize tasks เป็น 3 กลุ่ม (Fast, Normal, Slow)
- **`p50_seconds`**: Median baseline (50th percentile)
- **`p95_seconds`**: SLA threshold (95th percentile)
- **ความสำคัญ**: **Distribution analysis** - เห็นภาพรวม performance distribution

**Business Value**:
- Healthy distribution: ส่วนใหญ่อยู่ใน Fast/Normal, มี Slow น้อย
- Unhealthy distribution: มี Slow tasks เยอะ = performance issues

---

**7. Current Running Tasks (SLA Monitor)**
```sql
SELECT 
  ti.dag_id as "DAG ID",
  ti.task_id as "Task ID",
  ti.state as "State",
  ROUND(EXTRACT(EPOCH FROM (NOW() - ti.start_date))::numeric, 2) as "Running Time (s)",
  ROUND(tb.p95_seconds::numeric, 2) as "Baseline P95 (s)",
  ROUND(
    (EXTRACT(EPOCH FROM (NOW() - ti.start_date)) / NULLIF(tb.p95_seconds, 0))::numeric,
    2
  ) as "SLA Ratio"
FROM task_instance ti
JOIN task_baseline tb 
  ON ti.dag_id = tb.dag_id 
  AND ti.task_id = tb.task_id
  AND tb.baseline_key = 'default'
WHERE ti.state = 'running'
  AND ti.start_date IS NOT NULL
ORDER BY "SLA Ratio" DESC
LIMIT 20;
```

**คำอธิบาย**:
- **`EXTRACT(EPOCH FROM (NOW() - ti.start_date))`**: Running time ในหน่วยวินาที
- **`SLA Ratio`**: Running time / P95 baseline (> 1.0 = violating SLA)
- **`ORDER BY "SLA Ratio" DESC`**: แสดง tasks ที่ใกล้ violate หรือ violate แล้วก่อน
- **ความสำคัญ**: **Real-time monitoring** - ดู tasks ที่กำลังรันและอาจ violate SLA

**Business Value**:
- Real-time visibility: เห็น tasks ที่กำลังมีปัญหา
- Proactive intervention: แก้ไขปัญหาก่อน task fail หรือ impact downstream

---

**8. Recent SLA Violations**
```sql
SELECT 
  ti.dag_id as "DAG ID",
  ti.task_id as "Task ID",
  ti.start_date as "Start Time",
  ROUND(ti.duration::numeric, 2) as "Actual Duration (s)",
  ROUND(tb.p95_seconds::numeric, 2) as "Baseline P95 (s)",
  ROUND(
    (((ti.duration - tb.p95_seconds) / NULLIF(tb.p95_seconds, 0)) * 100)::numeric,
    2
  ) as "Violation %",
  ti.end_date as "End Time"
FROM task_instance ti
JOIN task_baseline tb 
  ON ti.dag_id = tb.dag_id 
  AND ti.task_id = tb.task_id
  AND tb.baseline_key = 'default'
WHERE ti.start_date BETWEEN $__timeFrom() AND $__timeTo()
  AND ti.state = 'success'
  AND ti.duration IS NOT NULL
  AND ti.duration > tb.p95_seconds
ORDER BY ti.start_date DESC
LIMIT 20;
```

**คำอธิบาย**:
- **`Violation %`**: เกินกว่า baseline กี่ % (เช่น 150% = ช้ากว่า baseline 1.5 เท่า)
- **`ORDER BY ti.start_date DESC`**: แสดง violations ล่าสุดก่อน
- **ความสำคัญ**: **Incident tracking** - ดู violations ที่เกิดขึ้นล่าสุดเพื่อสอบสวน

**Business Value**:
- Root cause analysis: ดู pattern ของ violations (DAG/task ไหนมีปัญหาบ่อย)
- Impact assessment: ดู severity ของ violations (violation % สูง = impact มาก)

---

**9. Top 10 Slowest Tasks (vs Baseline)**
```sql
SELECT 
  ti.dag_id as "DAG ID",
  ti.task_id as "Task ID",
  COUNT(*) as "Occurrences",
  ROUND(AVG(ti.duration)::numeric, 2) as "Avg Actual (s)",
  ROUND(AVG(tb.p95_seconds)::numeric, 2) as "Baseline P95 (s)",
  ROUND(
    (AVG(ti.duration) / NULLIF(AVG(tb.p95_seconds), 0))::numeric,
    2
  ) as "Slowdown Factor"
FROM task_instance ti
JOIN task_baseline tb 
  ON ti.dag_id = tb.dag_id 
  AND ti.task_id = tb.task_id
  AND tb.baseline_key = 'default'
WHERE ti.start_date BETWEEN $__timeFrom() AND $__timeTo()
  AND ti.state = 'success'
  AND ti.duration IS NOT NULL
  AND ti.duration > tb.p95_seconds
GROUP BY ti.dag_id, ti.task_id
ORDER BY "Slowdown Factor" DESC
LIMIT 10;
```

**คำอธิบาย**:
- **`Slowdown Factor`**: Avg actual / Avg baseline (2.0 = ช้ากว่า baseline 2 เท่า)
- **`Occurrences`**: จำนวนครั้งที่ task นี้ violate SLA
- **ความสำคัญ**: **Optimization prioritization** - tasks ไหนควร optimize ก่อน

**Business Value**:
- Prioritize optimization: Focus ที่ tasks ที่มี slowdown factor สูงและ occurrences เยอะ
- ROI calculation: Tasks ที่ช้ามากและรันบ่อย = high impact optimization

---

**10. Baseline vs Actual Duration Trend**
```sql
SELECT 
  DATE_TRUNC('hour', ti.start_date) as time,
  AVG(ti.duration) as "Actual Duration",
  AVG(tb.p50_seconds) as "Baseline P50",
  AVG(tb.p95_seconds) as "Baseline P95 (SLA)"
FROM task_instance ti
JOIN task_baseline tb 
  ON ti.dag_id = tb.dag_id 
  AND ti.task_id = tb.task_id
  AND tb.baseline_key = 'default'
WHERE ti.start_date BETWEEN $__timeFrom() AND $__timeTo()
  AND ti.state = 'success'
  AND ti.duration IS NOT NULL
GROUP BY DATE_TRUNC('hour', ti.start_date)
ORDER BY time;
```

**คำอธิบาย**:
- **3 lines**: Actual duration, P50 baseline, P95 baseline (SLA threshold)
- **Visual comparison**: เห็นว่า actual duration อยู่ระหว่าง P50-P95 หรือเกิน P95
- **ความสำคัญ**: **Trend visualization** - เห็น performance trends เทียบกับ baseline

**Business Value**:
- Early warning: เห็น actual duration เริ่มเข้าใกล้ P95 = ต้องเตรียมแก้ไข
- Validation: หลัง optimize เห็น actual duration ลดลงใกล้ P50

---

**11. SLA Violation Heatmap (by Hour of Day)**
```sql
SELECT 
  EXTRACT(HOUR FROM ti.start_date) as "Hour",
  COUNT(*) FILTER (WHERE ti.duration > tb.p95_seconds) as "Violations"
FROM task_instance ti
JOIN task_baseline tb 
  ON ti.dag_id = tb.dag_id 
  AND ti.task_id = tb.task_id
  AND tb.baseline_key = 'default'
WHERE ti.start_date BETWEEN $__timeFrom() AND $__timeTo()
  AND ti.state = 'success'
  AND ti.duration IS NOT NULL
GROUP BY EXTRACT(HOUR FROM ti.start_date)
ORDER BY "Hour";
```

**คำอธิบาย**:
- **`EXTRACT(HOUR FROM ti.start_date)`**: แยกชั่วโมงจาก timestamp (0-23)
- **`COUNT(*) FILTER (WHERE ...)`**: นับ violations ในแต่ละชั่วโมง
- **ความสำคัญ**: **Pattern analysis** - เห็น peak hours ที่มี violations สูง

**Business Value**:
- Capacity planning: เพิ่ม resources ใน peak hours
- Scheduling optimization: Reschedule heavy tasks ออกจาก peak hours

---

#### 🎯 Baseline Computation DAG

**DAG**: `baseline_compute_daily`
**Schedule**: ทุก 5 นาที (POC mode) - Production ควรเป็น daily
**Configuration**:
```python
WINDOW_DAYS = 14      # Look back 14 days
MIN_SAMPLES = 2       # Minimum 2 successful runs (POC) - Production ควรเป็น 20
BASELINE_KEY = "default"
BUFFER_PERCENT = 0.15  # Recommended SLA = P95 * 1.15
```

**Tasks**:
1. **extract**: Query task_instance history (14 days, success only)
2. **compute**: Calculate percentiles (P50, P90, P95, P99) per task
3. **upsert**: Store/update baselines in task_baseline table
4. **report**: Print summary

**Baseline Table Schema**:
```sql
CREATE TABLE task_baseline (
  dag_id VARCHAR,
  task_id VARCHAR,
  baseline_key VARCHAR,
  window_days INTEGER,
  as_of_date DATE,
  samples INTEGER,
  avg_seconds FLOAT,
  p50_seconds FLOAT,
  p90_seconds FLOAT,
  p95_seconds FLOAT,
  p99_seconds FLOAT,
  stddev_seconds FLOAT,
  recommended_sla_seconds FLOAT,
  updated_at TIMESTAMP,
  PRIMARY KEY (dag_id, task_id, baseline_key, window_days, as_of_date)
);
```

---

#### 📈 Best Practices

**Monitoring**:
- ตั้ง alert สำหรับ SLA Compliance < 90%
- ตั้ง alert สำหรับ SLA Violations > 10% of total tasks
- Monitor "At Risk Tasks" เพื่อ proactive intervention
- Review "Top 10 Slowest Tasks" weekly เพื่อ prioritize optimization

**Baseline Management**:
- Review baseline statistics monthly
- Adjust MIN_SAMPLES based on task frequency (high frequency = higher MIN_SAMPLES)
- Use multiple baseline_keys สำหรับ different contexts (peak/off-peak, weekday/weekend)
- Archive old baselines เพื่อ historical analysis

**Performance Optimization**:
- Focus on tasks with high "Slowdown Factor" และ high "Occurrences"
- Use "Violation %" เพื่อ quantify severity
- Validate optimization ด้วย "Baseline vs Actual Duration Trend"
- Document optimization efforts และ track impact

**Capacity Planning**:
- Use "SLA Violation Heatmap" เพื่อ identify peak hours
- Monitor trends เพื่อ predict future capacity needs
- Plan resource scaling based on violation patterns

---

#### 🔄 Integration with Other Dashboards

| Dashboard | Integration Point | Use Case |
|-----------|------------------|----------|
| **Task Performance** | Duration analysis | Deep dive into slow tasks |
| **Resource & Pool** | Resource correlation | Link performance to resource constraints |
| **Error & Debugging** | Failure correlation | Check if violations lead to failures |
| **Job Flow Visualization** | Dependency impact | Assess downstream impact of violations |

---

#### 🎓 Key Concepts

**P50 (Median)**:
- 50% ของ tasks รันเสร็จภายในเวลานี้
- ใช้เป็น "typical" performance

**P95 (95th Percentile)**:
- 95% ของ tasks รันเสร็จภายในเวลานี้
- ใช้เป็น SLA threshold (ยอมรับได้ว่า 5% อาจเกิน)

**P99 (99th Percentile)**:
- 99% ของ tasks รันเสร็จภายในเวลานี้
- ใช้เป็น "worst case" planning

**Recommended SLA**:
- P95 * 1.15 (เพิ่ม 15% buffer)
- ให้ margin สำหรับ variability

---

### 🔑 สรุปความแตกต่าง Airflow 3.x Schema

การเปลี่ยนแปลงสำคัญที่ต้องระวังเมื่อเขียน SQL queries:

| Airflow 2.x | Airflow 3.x | เหตุผลในการเปลี่ยน | Impact |
|-------------|-------------|-------------------|--------|
| `is_active` | `bundle_name IS NOT NULL` | Bundle-based deployment model | ต้องเปลี่ยน WHERE clause |
| `is_active = true` | `is_paused = false` | ชื่อชัดเจนกว่า | ต้องเปลี่ยน column name |
| `execution_date` | `logical_date` | ชื่อสื่อความหมายมากกว่า | ต้องเปลี่ยน column name |
| `dataset` | `asset` | Terminology ที่ชัดเจนกว่า | ต้องเปลี่ยน table name |
| `dataset_event` | `asset_event` | สอดคล้องกับ asset terminology | ต้องเปลี่ยน table name |
| `dag_schedule_dataset_reference` | `dag_schedule_asset_reference` | สอดคล้องกับ asset terminology | ต้องเปลี่ยน table name |
| `sla_miss` | ❌ **ถูกลบออก** | SLA tracking ถูก redesign | ไม่สามารถใช้ table นี้ได้ |
| `stack_trace` | `stacktrace` | Column name ไม่มี underscore | ต้องเปลี่ยน column name ใน import_error table |
| `schedule_interval` | `timetable_summary` | Timetable-based scheduling | ต้องเปลี่ยน column name ใน dag table |
| `tags` | ❌ **ถูกลบออก** | Tags ไม่มีใน dag table แล้ว | ไม่สามารถใช้ column นี้ได้ |

**Migration Tips**:
- ใช้ search & replace สำหรับ column/table names
- Test queries กับ Airflow 3.x database ก่อน deploy
- Update documentation และ runbooks
- Train team เกี่ยวกับ schema changes

---

### ⏰ Grafana Time Range Variables

**ทุก dashboards** ใช้ **Grafana time range variables** แทน hardcoded `INTERVAL`:

**เดิม (Hardcoded):**
```sql
WHERE start_date > NOW() - INTERVAL '24 hours'
WHERE start_date > NOW() - INTERVAL '7 days'
```

**ใหม่ (Dynamic Time Range):**
```sql
WHERE start_date >= $__timeFrom()
  AND start_date <= $__timeTo()
```

**ข้อดี:**
- ✅ **Flexible**: ผู้ใช้เลือก time range ได้เอง (Last 1h, 6h, 24h, 7d, 30d, Custom)
- ✅ **Consistent**: Time range sync กับทุก panels ใน dashboard
- ✅ **Better UX**: ใช้ Grafana time picker UI มาตรฐาน
- ✅ **Dynamic**: ไม่ต้อง hardcode time windows

**Default Time Range**: ทุก dashboard ตั้งค่าเริ่มต้นเป็น **"Last 24 hours"** (`from: "now-24h", to: "now"`)

**การใช้งาน:**
1. เปิด dashboard ใน Grafana
2. คลิกที่ time picker ด้านบนขวา
3. เลือก time range ที่ต้องการ (Quick ranges หรือ Custom range)
4. ทุก panels จะ refresh และแสดงข้อมูลตาม time range ที่เลือก

---

## 📚 Additional Resources

- **[README.md](README.md)** - Main documentation
- **[DEPLOYMENT.md](DEPLOYMENT.md)** - Detailed deployment guide
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common issues and solutions
- **[AIRFLOW-3X-SCHEMA-VALIDATION.md](AIRFLOW-3X-SCHEMA-VALIDATION.md)** - Schema validation details
- **[Apache Airflow 3.x Documentation](https://airflow.apache.org/docs/apache-airflow/stable/)** - Official documentation

---

## 🎯 Summary

เอกสารนี้ครอบคลุม **10 Grafana Dashboards** สำหรับ monitoring Apache Airflow 3.x โดยละเอียด:

1. **Airflow Metrics** - Real-time monitoring จาก Prometheus
2. **Airflow DAGs** - ภาพรวมสถานะ DAGs และ Tasks
3. **Airflow DAGs Status Grid** - Visual grid layout ของ DAG status
4. **Airflow Task Performance** - วิเคราะห์ performance และ retry patterns
5. **Airflow Resource & Pool** - ติดตาม resource utilization
6. **Airflow Error & Debugging** - Monitor errors และ failures
7. **Airflow DAG Dependencies & Lineage** - ติดตาม dependencies และ data lineage
8. **Airflow DAG Tasks Explorer** - Interactive drill-down สำหรับ explore tasks ใน DAG ที่เลือก
9. **Airflow Job Flow Visualization** - Control-M style monitoring พร้อม performance anomaly detection และ critical path analysis
10. **Airflow SLA & Baseline Monitoring** - SLA compliance tracking และ performance baseline comparison

แต่ละ dashboard มีคำอธิบายละเอียดเกี่ยวกับ:
- **วัตถุประสงค์**: ใช้ดูอะไร
- **SQL Queries**: พร้อมคำอธิบายแต่ละส่วน
- **Column explanations**: ทำไมถึงเลือกใช้ column นั้น
- **Business value**: ประโยชน์ทางธุรกิจ
- **Best practices**: แนวทางปฏิบัติที่ดี

**🆕 New in this version**:
- เพิ่ม **SLA & Baseline Monitoring Dashboard** สำหรับ data-driven SLA tracking
- ใช้ Grafana Time Range Variables (`$__timeFrom()`, `$__timeTo()`) ในทุก dashboards
- รองรับ Airflow 3.x schema changes
- Foreign Data Wrapper (FDW) สำหรับ cross-database queries

