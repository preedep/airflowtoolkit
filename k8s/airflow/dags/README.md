# DAGs Directory

วาง DAG files ของคุณในโฟลเดอร์นี้

## การใช้งาน

1. **เพิ่ม DAG ใหม่**: วาง Python file ในโฟลเดอร์นี้
2. **Sync ไปยัง Airflow**: รัน `./sync-dags.sh` จาก root directory
3. **ตรวจสอบใน UI**: เปิด http://localhost:30080

## ตัวอย่าง

ดูไฟล์ `example_dag.py` เป็นตัวอย่างการเขียน DAG

## หมายเหตุ

- ไฟล์ที่ระบุใน `.airflowignore` จะไม่ถูก parse
- DAG จะถูก sync ผ่าน ConfigMap
- หลังจาก sync จะมีการ restart scheduler และ dag-processor อัตโนมัติ
