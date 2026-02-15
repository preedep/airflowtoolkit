# DAGs Sync Guide

คู่มือการ sync DAG files จาก local folder ไปยัง Airflow บน Kubernetes

---

## 🇹🇭 ภาษาไทย

### ภาพรวม

ระบบนี้ใช้ **Kubernetes ConfigMap** ในการ mount DAG files จาก local folder `k8s/airflow/dags/` ไปยัง Airflow pods ทำให้สามารถพัฒนา DAGs บน local machine และ sync ไปยัง Kubernetes ได้ง่าย

### วิธีการทำงาน

1. DAG files ถูกเก็บใน `k8s/airflow/dags/` บน local machine
2. Script `sync-dags.sh` สร้าง ConfigMap จาก DAG files
3. ConfigMap ถูก mount เข้าไปใน Airflow pods ที่ `/opt/airflow/dags`
4. Airflow scheduler และ dag-processor จะ parse DAGs จาก ConfigMap

### การติดตั้งครั้งแรก

หลังจากติดตั้ง Airflow แล้ว ให้รัน:

```bash
./setup-dags-mount.sh
```

Script นี้จะ:
- สร้าง ConfigMap สำหรับ DAGs
- Patch Airflow deployments ให้ mount ConfigMap
- Sync DAG files ครั้งแรก
- Restart Airflow components

### การเพิ่ม/แก้ไข DAGs

#### 1. เพิ่ม DAG ใหม่

```bash
# สร้างไฟล์ DAG ใหม่
cat > k8s/airflow/dags/my_new_dag.py << 'EOF'
from datetime import datetime
from airflow import DAG
from airflow.operators.bash import BashOperator

with DAG(
    'my_new_dag',
    start_date=datetime(2024, 1, 1),
    schedule_interval='@daily',
    catchup=False,
) as dag:
    task = BashOperator(
        task_id='hello',
        bash_command='echo "Hello from my new DAG!"',
    )
EOF

# Sync ไปยัง Kubernetes
./sync-dags.sh
```

#### 2. แก้ไข DAG ที่มีอยู่

```bash
# แก้ไขไฟล์ DAG
vim k8s/airflow/dags/example_dag.py

# Sync การเปลี่ยนแปลง
./sync-dags.sh
```

#### 3. ลบ DAG

```bash
# ลบไฟล์ DAG
rm k8s/airflow/dags/old_dag.py

# Sync การเปลี่ยนแปลง
./sync-dags.sh
```

### โครงสร้าง DAGs Folder

```
k8s/airflow/dags/
├── .airflowignore          # ไฟล์ที่ไม่ต้องการให้ Airflow parse
├── README.md               # คำอธิบาย
├── example_dag.py          # ตัวอย่าง DAG
├── my_dag_1.py            # DAG ของคุณ
├── my_dag_2.py            # DAG ของคุณ
└── utils/                  # Utility modules (optional)
    └── helpers.py
```

### Scripts ที่มีให้ใช้

#### `setup-dags-mount.sh`
ติดตั้งระบบ DAG sync ครั้งแรก (รันครั้งเดียวหลังจาก deploy Airflow)

```bash
./setup-dags-mount.sh
```

#### `sync-dags.sh`
Sync DAG files ไปยัง Kubernetes (รันทุกครั้งที่มีการเปลี่ยนแปลง DAGs)

```bash
./sync-dags.sh
```

### ข้อจำกัดของ ConfigMap

⚠️ **ข้อจำกัดสำคัญ**:
- ConfigMap มีขนาดจำกัดที่ **1MB**
- เหมาะสำหรับ DAGs ไม่เกิน 20-30 ไฟล์
- ถ้ามี DAGs จำนวนมาก ควรใช้ Git-sync หรือ PVC แทน

### Alternative: Git-sync (สำหรับ Production)

สำหรับ production หรือ DAGs จำนวนมาก แนะนำให้ใช้ Git-sync:

1. แก้ไข `k8s/airflow/values.yaml`:
```yaml
dags:
  gitSync:
    enabled: true
    repo: https://github.com/your-org/airflow-dags.git
    branch: main
    subPath: dags
    wait: 60  # Sync every 60 seconds
```

2. Re-deploy Airflow:
```bash
helm upgrade airflow apache-airflow/airflow \
  --namespace airflow \
  --values k8s/airflow/values.yaml
```

### Troubleshooting

#### DAGs ไม่แสดงใน UI

1. ตรวจสอบ ConfigMap:
```bash
kubectl get configmap airflow-dags -n airflow
kubectl describe configmap airflow-dags -n airflow
```

2. ตรวจสอบว่า volume ถูก mount:
```bash
kubectl describe pod -n airflow -l component=scheduler
```

3. ตรวจสอบ logs:
```bash
kubectl logs -n airflow -l component=dag-processor --tail=50
```

#### DAG มี Import Error

ตรวจสอบว่า dependencies ครบถ้วน:
```bash
# เข้าไปใน scheduler pod
kubectl exec -it -n airflow <scheduler-pod> -- bash

# ทดสอบ import
python -c "from airflow import DAG"
```

#### ConfigMap เต็ม (>1MB)

ถ้า DAGs มีขนาดใหญ่เกินไป:
1. ใช้ Git-sync แทน ConfigMap
2. หรือใช้ PersistentVolume

### Best Practices

1. **ใช้ .airflowignore**: ระบุไฟล์ที่ไม่ต้องการให้ parse
2. **แยก utilities**: วาง helper functions ในโฟลเดอร์แยก
3. **Version control**: เก็บ DAGs ใน Git repository
4. **Test locally**: ทดสอบ DAG syntax ก่อน sync
5. **Sync บ่อยๆ**: รัน `./sync-dags.sh` ทุกครั้งที่แก้ไข

---

## 🇬🇧 English

### Overview

This system uses **Kubernetes ConfigMap** to mount DAG files from local folder `k8s/airflow/dags/` to Airflow pods, allowing easy DAG development on local machine and syncing to Kubernetes.

### How It Works

1. DAG files are stored in `k8s/airflow/dags/` on local machine
2. Script `sync-dags.sh` creates ConfigMap from DAG files
3. ConfigMap is mounted to Airflow pods at `/opt/airflow/dags`
4. Airflow scheduler and dag-processor parse DAGs from ConfigMap

### Initial Setup

After deploying Airflow, run:

```bash
./setup-dags-mount.sh
```

This script will:
- Create ConfigMap for DAGs
- Patch Airflow deployments to mount ConfigMap
- Sync DAG files for the first time
- Restart Airflow components

### Adding/Modifying DAGs

#### 1. Add New DAG

```bash
# Create new DAG file
cat > k8s/airflow/dags/my_new_dag.py << 'EOF'
from datetime import datetime
from airflow import DAG
from airflow.operators.bash import BashOperator

with DAG(
    'my_new_dag',
    start_date=datetime(2024, 1, 1),
    schedule_interval='@daily',
    catchup=False,
) as dag:
    task = BashOperator(
        task_id='hello',
        bash_command='echo "Hello from my new DAG!"',
    )
EOF

# Sync to Kubernetes
./sync-dags.sh
```

#### 2. Modify Existing DAG

```bash
# Edit DAG file
vim k8s/airflow/dags/example_dag.py

# Sync changes
./sync-dags.sh
```

#### 3. Delete DAG

```bash
# Remove DAG file
rm k8s/airflow/dags/old_dag.py

# Sync changes
./sync-dags.sh
```

### DAGs Folder Structure

```
k8s/airflow/dags/
├── .airflowignore          # Files to ignore
├── README.md               # Documentation
├── example_dag.py          # Example DAG
├── my_dag_1.py            # Your DAG
├── my_dag_2.py            # Your DAG
└── utils/                  # Utility modules (optional)
    └── helpers.py
```

### Available Scripts

#### `setup-dags-mount.sh`
Initial setup for DAG sync system (run once after Airflow deployment)

```bash
./setup-dags-mount.sh
```

#### `sync-dags.sh`
Sync DAG files to Kubernetes (run every time DAGs change)

```bash
./sync-dags.sh
```

### ConfigMap Limitations

⚠️ **Important Limitations**:
- ConfigMap size limit is **1MB**
- Suitable for up to 20-30 DAG files
- For more DAGs, use Git-sync or PVC instead

### Alternative: Git-sync (for Production)

For production or many DAGs, use Git-sync:

1. Edit `k8s/airflow/values.yaml`:
```yaml
dags:
  gitSync:
    enabled: true
    repo: https://github.com/your-org/airflow-dags.git
    branch: main
    subPath: dags
    wait: 60  # Sync every 60 seconds
```

2. Re-deploy Airflow:
```bash
helm upgrade airflow apache-airflow/airflow \
  --namespace airflow \
  --values k8s/airflow/values.yaml
```

### Troubleshooting

#### DAGs Not Showing in UI

1. Check ConfigMap:
```bash
kubectl get configmap airflow-dags -n airflow
kubectl describe configmap airflow-dags -n airflow
```

2. Verify volume mount:
```bash
kubectl describe pod -n airflow -l component=scheduler
```

3. Check logs:
```bash
kubectl logs -n airflow -l component=dag-processor --tail=50
```

#### DAG Import Errors

Check dependencies:
```bash
# Enter scheduler pod
kubectl exec -it -n airflow <scheduler-pod> -- bash

# Test import
python -c "from airflow import DAG"
```

#### ConfigMap Full (>1MB)

If DAGs are too large:
1. Use Git-sync instead of ConfigMap
2. Or use PersistentVolume

### Best Practices

1. **Use .airflowignore**: Specify files to skip parsing
2. **Separate utilities**: Put helper functions in separate folder
3. **Version control**: Keep DAGs in Git repository
4. **Test locally**: Test DAG syntax before syncing
5. **Sync frequently**: Run `./sync-dags.sh` after every change

---

## Quick Reference

```bash
# Initial setup (run once)
./setup-dags-mount.sh

# Sync DAGs (run after changes)
./sync-dags.sh

# View DAGs in ConfigMap
kubectl get configmap airflow-dags -n airflow -o yaml

# Check scheduler logs
kubectl logs -f -n airflow -l component=scheduler

# Check dag-processor logs
kubectl logs -f -n airflow -l component=dag-processor
```
