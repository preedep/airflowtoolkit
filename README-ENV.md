# Environment Configuration

## การตั้งค่า Airflow Host URL

### 📝 วิธีการใช้งาน

1. **สร้างไฟล์ `.env`** (copy จาก `.env.example`):
   ```bash
   cp .env.example .env
   ```

2. **แก้ไขค่า `AIRFLOW_HOST`** ใน `.env`:
   ```bash
   # สำหรับ Docker Desktop / MicroK8s
   AIRFLOW_HOST=http://localhost:30080

   # สำหรับ Production
   AIRFLOW_HOST=https://airflow.company.com

   # สำหรับ Staging
   AIRFLOW_HOST=http://airflow-staging:8080
   ```

3. **Deploy** - `deploy.sh` จะอ่านค่าจาก `.env` อัตโนมัติ:
   ```bash
   ./deploy.sh
   ```

### 🎯 ผลลัพธ์

เมื่อ deploy เสร็จ:
- ✅ Grafana dashboards จะใช้ `AIRFLOW_HOST` จาก `.env` เป็นค่า default
- ✅ คลิก DAG ID ใน Grafana → เปิด Airflow UI ตาม URL ที่กำหนด
- ✅ ผู้ใช้สามารถเปลี่ยน URL ใน Grafana UI ได้ตามต้องการ

### 🔧 การทำงาน

`deploy.sh` จะ:
1. โหลดค่าจาก `.env` (ถ้ามี)
2. ใช้ `http://localhost:30080` เป็น default (ถ้าไม่มี `.env`)
3. แทนที่ค่า `airflow_url` variable ใน dashboard YAML files
4. Deploy dashboards ที่ processed แล้ว

### 📋 ตัวอย่าง

**ไฟล์ `.env`:**
```bash
AIRFLOW_HOST=https://airflow.prod.company.com
```

**ผลลัพธ์ใน Grafana:**
- Default `airflow_url` = `https://airflow.prod.company.com`
- คลิก DAG ID → เปิด `https://airflow.prod.company.com/dags/my_dag`

### ⚠️ หมายเหตุ

- ไฟล์ `.env` ถูก gitignore แล้ว (ไม่ commit ลง git)
- ใช้ `.env.example` เป็น template
- ค่า default คือ `http://localhost:30080` (ถ้าไม่มี `.env`)
