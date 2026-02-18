# Airflow SLA & Baseline Monitoring Dashboard

## 📊 Overview

Dashboard นี้ออกแบบตามแนวทาง **Control-M SLA Monitoring** เพื่อติดตาม:
- **SLA Compliance** - การปฏิบัติตาม SLA ของ tasks
- **Baseline Trends** - แนวโน้มการทำงานเทียบกับ baseline
- **Performance Anomalies** - การตรวจจับความผิดปกติ
- **Real-time Monitoring** - ติดตาม tasks ที่กำลังทำงาน

---

## 🎯 Dashboard Components

### 1. Executive Summary (Top Row)

#### 🟢 SLA Compliance Rate (24h)
- **Gauge Chart** แสดง % ของ tasks ที่ทำงานภายใน SLA (baseline P95)
- **Color Coding**:
  - 🔴 Red: < 80% (วิกฤต)
  - 🟡 Yellow: 80-95% (เตือน)
  - 🟢 Green: > 95% (ปกติ)
- **Query**: เปรียบเทียบ actual duration กับ baseline_p95 ใน 24 ชั่วโมงล่าสุด

#### 📊 Total Tasks (24h)
- **Stat Panel** แสดงจำนวน tasks ทั้งหมดที่รันใน 24 ชั่วโมง
- นับรวม: success, failed, running states

#### ⚠️ SLA Violations (24h)
- **Stat Panel** แสดงจำนวน tasks ที่ละเมิด SLA
- **Color Coding**:
  - 🟢 Green: 0-4 violations
  - 🟡 Yellow: 5-9 violations
  - 🔴 Red: ≥ 10 violations

#### 🚨 At Risk Tasks
- **Stat Panel** แสดง tasks ที่กำลังทำงานและใกล้เกิน SLA
- เงื่อนไข: running time > 80% ของ baseline_p95
- ช่วยเตือนก่อนเกิด violation

---

### 2. Trend Analysis (Middle Section)

#### 📈 SLA Compliance Trend (7 days)
- **Time Series Chart** แสดงแนวโน้ม SLA compliance % ย้อนหลัง 7 วัน
- **Granularity**: รายชั่วโมง
- **Use Case**: 
  - ดูแนวโน้มการปฏิบัติตาม SLA
  - ระบุช่วงเวลาที่มีปัญหา
  - วางแผน capacity planning

#### ⏱️ Baseline vs Actual Duration Trend
- **Multi-line Time Series** เปรียบเทียบ:
  - 🔵 Actual Duration (ค่าเฉลี่ยจริง)
  - 🟢 Baseline P50 (median baseline)
  - 🔴 Baseline P95 (SLA threshold)
- **Use Case**:
  - ดูว่า actual duration เข้าใกล้ SLA หรือไม่
  - ตรวจจับ performance degradation
  - Validate baseline accuracy

#### 📊 Task Duration Trend by DAG
- **Multi-series Time Series** แสดงระยะเวลาเฉลี่ยของแต่ละ DAG
- **Use Case**:
  - เปรียบเทียบ performance ระหว่าง DAGs
  - ระบุ DAG ที่มีปัญหา
  - Track performance improvement

---

### 3. Real-time Monitoring

#### 🔴 Current Running Tasks (SLA Monitor)
- **Table Panel** แสดง tasks ที่กำลังทำงาน
- **Columns**:
  - DAG ID, Task ID
  - State
  - Running Time (s)
  - Baseline P95 (s)
  - **SLA Ratio** = Running Time / Baseline P95
- **Color Coding** (SLA Ratio):
  - 🟢 Green: < 0.8 (ปลอดภัย)
  - 🟡 Yellow: 0.8-1.0 (ใกล้เกิน)
  - 🟠 Orange: 1.0-1.2 (เกิน SLA เล็กน้อย)
  - 🔴 Red: > 1.2 (เกิน SLA มาก)
- **Sort**: เรียงตาม SLA Ratio จากมากไปน้อย

---

### 4. Historical Analysis

#### 📋 Recent SLA Violations (24h)
- **Table Panel** แสดง tasks ที่ละเมิด SLA ใน 24 ชั่วโมง
- **Columns**:
  - DAG ID, Task ID
  - Start Time, End Time
  - Actual Duration (s)
  - Baseline P95 (s)
  - **Violation %** = ((Actual - Baseline) / Baseline) × 100
- **Use Case**:
  - Root cause analysis
  - Identify problematic tasks
  - Track violation patterns

#### 🐌 Top 10 Slowest Tasks (vs Baseline)
- **Table Panel** แสดง tasks ที่ช้ากว่า baseline มากที่สุด
- **Columns**:
  - DAG ID, Task ID
  - Occurrences (จำนวนครั้งที่เกิน)
  - Avg Actual (s)
  - Baseline P95 (s)
  - **Slowdown Factor** = Avg Actual / Baseline P95
- **Color Coding** (Slowdown Factor):
  - 🟢 Green: < 1.5
  - 🟡 Yellow: 1.5-2.0
  - 🟠 Orange: 2.0-3.0
  - 🔴 Red: > 3.0
- **Use Case**:
  - Prioritize optimization efforts
  - Identify chronic performance issues

#### 🔥 SLA Violation Heatmap (by Hour of Day)
- **Table Panel** แสดงจำนวน violations แยกตามชั่วโมงของวัน
- **Use Case**:
  - ระบุช่วงเวลาที่มี violations มากที่สุด
  - วางแผน resource allocation
  - Schedule maintenance windows

---

## 🚀 Deployment

### 1. Apply Dashboard ConfigMap

```bash
kubectl apply -f k8s/monitoring/grafana-dashboard-sla-configmap.yaml
```

### 2. Restart Grafana (if needed)

```bash
kubectl rollout restart deployment grafana -n monitoring
```

### 3. Access Dashboard

1. เปิด Grafana: http://localhost:30300
2. Login: `admin` / `admin`
3. ไปที่ **Dashboards** → **Browse**
4. เลือก **Airflow SLA & Baseline Monitoring**

---

## 📊 Dashboard Settings

### Auto-refresh
- **Default**: 30 seconds
- **Options**: 10s, 30s, 1m, 5m, 15m, 30m, 1h

### Time Range
- **Default**: Last 7 days
- **Recommended**: 
  - Real-time monitoring: Last 1 hour
  - Trend analysis: Last 7 days
  - Historical analysis: Last 30 days

---

## 🎨 Color Coding Reference

### SLA Ratio Thresholds
```
< 0.8   🟢 Green   - Safe (< 80% baseline)
0.8-1.0 🟡 Yellow  - At Risk (80-100% baseline)
1.0-1.2 🟠 Orange  - Minor Violation (100-120% baseline)
> 1.2   🔴 Red     - Major Violation (> 120% baseline)
```

### Compliance Rate Thresholds
```
< 80%   🔴 Red     - Critical
80-95%  🟡 Yellow  - Warning
> 95%   🟢 Green   - Healthy
```

---

## 📈 Use Cases

### 1. Daily Operations Monitoring
**Goal**: ติดตาม SLA compliance แบบ real-time

**Panels to Watch**:
- SLA Compliance Rate (24h)
- At Risk Tasks
- Current Running Tasks

**Actions**:
- ถ้า SLA Compliance < 95%: ตรวจสอบ Recent SLA Violations
- ถ้า At Risk Tasks > 5: พิจารณา scale up resources
- ถ้า SLA Ratio > 1.0: Alert team

### 2. Performance Trend Analysis
**Goal**: วิเคราะห์แนวโน้มและวางแผน capacity

**Panels to Watch**:
- SLA Compliance Trend (7 days)
- Baseline vs Actual Duration Trend
- Task Duration Trend by DAG

**Actions**:
- ถ้า trend ลดลงต่อเนื่อง: ตรวจสอบ infrastructure
- ถ้า actual duration เข้าใกล้ baseline: update baseline
- ถ้า specific DAG ช้าลง: optimize DAG code

### 3. Root Cause Analysis
**Goal**: หาสาเหตุของ SLA violations

**Panels to Watch**:
- Recent SLA Violations (24h)
- Top 10 Slowest Tasks
- SLA Violation Heatmap

**Actions**:
- ดู violation patterns (time, DAG, task)
- ตรวจสอบ logs ของ tasks ที่มีปัญหา
- วิเคราะห์ resource usage ในช่วงเวลาที่มี violations

### 4. Baseline Validation
**Goal**: ตรวจสอบความแม่นยำของ baseline

**Panels to Watch**:
- Baseline vs Actual Duration Trend
- Top 10 Slowest Tasks

**Actions**:
- ถ้า actual duration สูงกว่า baseline อย่างต่อเนื่อง: recalculate baseline
- ถ้า slowdown factor > 2.0: investigate code changes
- Run baseline_compute_daily DAG เพื่อ update baseline

---

## 🔧 Customization

### Add New Panels

1. Click **Add Panel** → **Add a new panel**
2. Select datasource: **Airflow Extension** หรือ **Airflow Metadata**
3. Write SQL query
4. Configure visualization
5. Save dashboard

### Example: Add "Failed Tasks" Panel

```sql
SELECT COUNT(*) as failed_tasks
FROM airflow.task_instance
WHERE start_date >= NOW() - INTERVAL '24 hours'
  AND state = 'failed';
```

### Modify Thresholds

1. Click panel title → **Edit**
2. ไปที่ **Field** tab
3. แก้ไข **Thresholds** values
4. Save

---

## 🎯 Best Practices

### 1. Set Alerts
- SLA Compliance Rate < 90%
- SLA Violations > 10 in 1 hour
- At Risk Tasks > 5

### 2. Regular Review
- Daily: ตรวจสอบ SLA Compliance Rate
- Weekly: วิเคราะห์ trends และ patterns
- Monthly: Review และ update baselines

### 3. Baseline Maintenance
- Run `baseline_compute_daily` DAG ทุกวัน
- Review baseline accuracy ทุกสัปดาห์
- Recalculate baselines หลัง code changes

### 4. Performance Optimization
- Focus on Top 10 Slowest Tasks
- Optimize tasks with Slowdown Factor > 2.0
- Monitor improvement after optimization

---

## 📚 Related Documentation

- [Baseline Computation](./BASELINE_COMPUTATION.md) - วิธีคำนวณ baseline
- [SLA Policy Configuration](./SLA_POLICY.md) - การตั้งค่า SLA policies
- [Grafana Datasources](./k8s/monitoring/grafana-datasources.yaml) - Database connections

---

## 🐛 Troubleshooting

### Dashboard ไม่แสดงข้อมูล

**สาเหตุ**: Datasource ไม่ถูกต้อง

**แก้ไข**:
```bash
# ตรวจสอบ datasources
kubectl get configmap grafana-datasources -n monitoring -o yaml

# Restart Grafana
kubectl rollout restart deployment grafana -n monitoring
```

### Query timeout

**สาเหตุ**: Query ช้าเกินไป

**แก้ไข**:
- เพิ่ม index ใน database
- ลด time range
- Optimize SQL queries

### ข้อมูลไม่ update

**สาเหตุ**: baseline_compute_daily DAG ไม่ทำงาน

**แก้ไข**:
```bash
# Trigger DAG manually
kubectl exec -n airflow deployment/airflow-scheduler -c scheduler -- \
  airflow dags trigger baseline_compute_daily

# Check DAG status
kubectl exec -n airflow deployment/airflow-scheduler -c scheduler -- \
  airflow dags list | grep baseline
```

---

## 📊 Sample Queries

### Get SLA Compliance by DAG

```sql
SELECT 
  ti.dag_id,
  COUNT(*) as total_runs,
  COUNT(*) FILTER (WHERE ti.duration <= tb.baseline_p95) as within_sla,
  ROUND(
    (COUNT(*) FILTER (WHERE ti.duration <= tb.baseline_p95) * 100.0) / COUNT(*),
    2
  ) as compliance_rate
FROM airflow.task_instance ti
JOIN airflow_extension.task_baseline tb 
  ON ti.dag_id = tb.dag_id 
  AND ti.task_id = tb.task_id
WHERE ti.start_date >= NOW() - INTERVAL '7 days'
  AND ti.state = 'success'
  AND ti.duration IS NOT NULL
GROUP BY ti.dag_id
ORDER BY compliance_rate ASC;
```

### Get Average Slowdown by Hour

```sql
SELECT 
  EXTRACT(HOUR FROM ti.start_date) as hour,
  ROUND(AVG(ti.duration / NULLIF(tb.baseline_p95, 0)), 2) as avg_slowdown
FROM airflow.task_instance ti
JOIN airflow_extension.task_baseline tb 
  ON ti.dag_id = tb.dag_id 
  AND ti.task_id = tb.task_id
WHERE ti.start_date >= NOW() - INTERVAL '7 days'
  AND ti.state = 'success'
  AND ti.duration IS NOT NULL
GROUP BY EXTRACT(HOUR FROM ti.start_date)
ORDER BY hour;
```

---

## 🎓 Training Resources

### Understanding SLA Monitoring
- **SLA Ratio**: Running Time / Baseline P95
  - < 1.0: Within SLA
  - \> 1.0: Violation
- **Compliance Rate**: % of tasks within SLA
- **Slowdown Factor**: How much slower than baseline

### Control-M Comparison
| Control-M | Airflow Dashboard |
|-----------|-------------------|
| Job SLA | Baseline P95 |
| Job Status | Task State |
| Performance Trend | Duration Trend |
| Alert Rules | Grafana Alerts |

---

## 🚀 Next Steps

1. ✅ Deploy dashboard ConfigMap
2. ✅ Verify datasources connection
3. ✅ Run baseline_compute_daily DAG
4. ✅ Access dashboard และตรวจสอบข้อมูล
5. ⏭️ Setup Grafana alerts
6. ⏭️ Create SLA policies
7. ⏭️ Train team on dashboard usage

---

**Dashboard Version**: 1.0  
**Last Updated**: 2026-02-18  
**Maintained by**: Airflow Toolkit Team
