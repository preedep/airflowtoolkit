# Airflow Toolkit

[🇹🇭 ภาษาไทย](#ภาษาไทย) | [🇬🇧 English](#english)

---

## ภาษาไทย

### 📋 ภาพรวม

ระบบติดตั้ง Apache Airflow 3.x แบบสมบูรณ์บน Kubernetes (Docker Desktop) พร้อมระบบ monitoring ที่ครบครัน ออกแบบตาม best practices ด้วยการแยก namespace และ persistent storage

### ✨ คุณสมบัติ

- ✅ **Apache Airflow 3.0.2** - เวอร์ชันล่าสุดพร้อม KubernetesExecutor
- ✅ **PostgreSQL 16** - Database สำหรับ metadata พร้อม persistent storage
- ✅ **Prometheus** - รวบรวม metrics จาก Airflow
- ✅ **Grafana** - Dashboard สำหรับแสดง metrics แบบ real-time
- ✅ **StatsD Exporter** - แปลง Airflow metrics เป็น Prometheus format
- ✅ **Namespace Isolation** - แยก components ตาม best practices
- ✅ **Persistent Volumes** - เก็บข้อมูล DAGs, logs และ database แบบถาวร

### 🏗️ สถาปัตยกรรม

```
┌─────────────────────────────────────────────────────────────┐
│                 Kubernetes Cluster (Docker Desktop)          │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Namespace: airflow                                     │ │
│  │  • API Server (UI) - NodePort 30080                   │ │
│  │  • Scheduler - จัดการ DAG execution                   │ │
│  │  • DAG Processor - ประมวลผล DAG files                │ │
│  │  • Triggerer - จัดการ deferrable tasks               │ │
│  │  • Workers - รัน tasks (KubernetesExecutor)           │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Namespace: database                                    │ │
│  │  • PostgreSQL 16 - Metadata DB (10Gi PVC)             │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Namespace: monitoring                                  │ │
│  │  • Prometheus - NodePort 30090                        │ │
│  │  • StatsD Exporter - รับ metrics จาก Airflow         │ │
│  │  • Grafana - NodePort 30030 (พร้อม Dashboard)        │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### 🚀 เริ่มต้นใช้งาน

#### ข้อกำหนดเบื้องต้น

1. **Docker Desktop** พร้อม Kubernetes enabled
2. **kubectl** CLI tool
3. **Helm 3** package manager

#### ติดตั้งแบบอัตโนมัติ

```bash
# ให้สิทธิ์ execute script
chmod +x deploy.sh

# รัน deployment
./deploy.sh
```

Script จะทำการติดตั้งทุกอย่างโดยอัตโนมัติ (~5-10 นาที):
- สร้าง namespaces (airflow, database, monitoring)
- Deploy PostgreSQL พร้อม persistent storage
- Deploy Prometheus และ StatsD Exporter
- Deploy Grafana พร้อม Airflow dashboard
- Install Airflow 3.x ด้วย Helm
- Expose services ผ่าน NodePort

### 🌐 เข้าถึงระบบ

หลังจากติดตั้งสำเร็จ สามารถเข้าถึงได้ที่:

| Service | URL | Username | Password |
|---------|-----|----------|----------|
| **Airflow UI** | http://localhost:30080 | admin | admin |
| **Grafana** | http://localhost:30030 | admin | admin |
| **Prometheus** | http://localhost:30090 | - | - |

### 📊 Grafana Dashboards

ระบบมี **7 Dashboards** สำหรับ monitoring Airflow จากมุมมองต่างๆ:
- **Airflow Metrics** - Real-time metrics จาก Prometheus
- **Airflow DAGs** - ภาพรวมสถานะ DAGs และ Tasks
- **Airflow DAGs Status Grid** - แสดงสถานะ DAGs แบบ grid layout
- **Airflow Task Performance** - วิเคราะห์ performance, retry rate, queue time
- **Airflow Resource & Pool** - ติดตาม pool usage และ slot allocation
- **Airflow Error & Debugging** - ติดตาม errors และ failures
- **Airflow DAG Dependencies & Lineage** - ติดตาม dependencies และ asset relationships

📖 **[ดูรายละเอียดทั้งหมดและ SQL queries ใน GRAFANA_DASHBOARDS.md](GRAFANA_DASHBOARDS.md)**

### 📁 โครงสร้างโปรเจค

```
airflowtoolkit/
├── k8s/
│   ├── namespaces.yaml                    # Namespace definitions
│   ├── database/                          # PostgreSQL manifests
│   │   ├── postgresql-secret.yaml
│   │   ├── postgresql-pvc.yaml
│   │   ├── postgresql-deployment.yaml
│   │   └── postgresql-service.yaml
│   ├── airflow/                           # Airflow configurations
│   │   ├── values.yaml                    # Helm values
│   │   ├── api-server-nodeport.yaml       # NodePort service
│   │   └── example-dag.py                 # ตัวอย่าง DAG
│   └── monitoring/                        # Monitoring stack
│       ├── prometheus-*.yaml              # Prometheus configs
│       ├── statsd-*.yaml                  # StatsD Exporter
│       └── grafana-*.yaml                 # Grafana configs
├── deploy.sh                              # Deployment script
├── cleanup.sh                             # Cleanup script
├── DEPLOYMENT.md                          # คู่มือการติดตั้งแบบละเอียด
├── TROUBLESHOOTING.md                     # คู่มือแก้ไขปัญหา
└── README.md                              # ไฟล์นี้
```

### 🛠️ คำสั่งที่มีประโยชน์

```bash
# ดูสถานะ pods ทั้งหมด
kubectl get pods -A

# ดู logs ของ scheduler
kubectl logs -f -n airflow -l component=scheduler

# ดู logs ของ API server
kubectl logs -f -n airflow -l component=api-server

# Scale scheduler
kubectl scale deployment airflow-scheduler -n airflow --replicas=2

# เข้าไปใน pod
kubectl exec -it <pod-name> -n airflow -- bash

# Port forward (ถ้า NodePort ไม่ทำงาน)
kubectl port-forward -n airflow svc/airflow-api-server 8080:8080
```

### 🔧 การปรับแต่ง

#### เปลี่ยน Airflow Version

แก้ไขใน `k8s/airflow/values.yaml`:
```yaml
images:
  airflow:
    tag: "3.0.2"  # เปลี่ยนเป็น version ที่ต้องการ
```

#### เพิ่ม DAGs

1. **วิธีที่ 1**: Copy DAG files เข้า persistent volume
2. **วิธีที่ 2**: ใช้ Git-sync (แก้ไข values.yaml):
```yaml
dags:
  gitSync:
    enabled: true
    repo: https://github.com/your-repo/dags.git
    branch: main
    subPath: dags
```

#### ปรับ Resources

แก้ไขใน `k8s/airflow/values.yaml`:
```yaml
scheduler:
  resources:
    limits:
      memory: "2Gi"
      cpu: "2000m"
```

### 🧹 ลบทุกอย่าง

```bash
# ลบทุก components
./cleanup.sh

# หรือลบแบบ manual
helm uninstall airflow -n airflow
kubectl delete -f k8s/monitoring/
kubectl delete -f k8s/database/
kubectl delete -f k8s/namespaces.yaml
```

### 📚 เอกสารเพิ่มเติม

- **[DEPLOYMENT.md](DEPLOYMENT.md)** - คู่มือการติดตั้งแบบละเอียด พร้อมคำอธิบายแต่ละขั้นตอน
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - คู่มือแก้ไขปัญหาที่พบบ่อย พร้อมวิธีแก้ไข
- **[GRAFANA_DASHBOARDS.md](GRAFANA_DASHBOARDS.md)** - คู่มือ Grafana Dashboards ทั้ง 7 อัน พร้อม SQL queries

### ⚠️ หมายเหตุ

- **Production Use**: ควรเปลี่ยน default passwords และใช้ secrets management
- **Resource Limits**: ปรับ resource limits ให้เหมาะกับ workload
- **Backup**: สำรอง PostgreSQL database เป็นประจำ
- **Monitoring**: ติดตาม metrics ใน Grafana เพื่อ optimize performance

### 🤝 Contributing

Pull requests are welcome! สำหรับการเปลี่ยนแปลงใหญ่ กรุณาเปิด issue เพื่อหารือก่อน

### 📄 License

MIT License - ใช้งานได้อย่างอิสระ

---

## English

### 📋 Overview

Complete production-ready Apache Airflow 3.x deployment on Kubernetes (Docker Desktop) with comprehensive monitoring stack. Designed following best practices with namespace isolation and persistent storage.

### ✨ Features

- ✅ **Apache Airflow 3.0.2** - Latest version with KubernetesExecutor
- ✅ **PostgreSQL 16** - Metadata database with persistent storage
- ✅ **Prometheus** - Metrics collection from Airflow
- ✅ **Grafana** - Real-time metrics visualization dashboard
- ✅ **StatsD Exporter** - Converts Airflow metrics to Prometheus format
- ✅ **Namespace Isolation** - Components separated following best practices
- ✅ **Persistent Volumes** - Persistent storage for DAGs, logs, and database

### 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              Kubernetes Cluster (Docker Desktop)             │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Namespace: airflow                                     │ │
│  │  • API Server (UI) - NodePort 30080                   │ │
│  │  • Scheduler - Manages DAG execution                  │ │
│  │  • DAG Processor - Processes DAG files                │ │
│  │  • Triggerer - Handles deferrable tasks               │ │
│  │  • Workers - Execute tasks (KubernetesExecutor)       │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Namespace: database                                    │ │
│  │  • PostgreSQL 16 - Metadata DB (10Gi PVC)             │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Namespace: monitoring                                  │ │
│  │  • Prometheus - NodePort 30090                        │ │
│  │  • StatsD Exporter - Receives Airflow metrics         │ │
│  │  • Grafana - NodePort 30030 (with Dashboard)          │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### 🚀 Quick Start

#### Prerequisites

1. **Docker Desktop** with Kubernetes enabled
2. **kubectl** CLI tool
3. **Helm 3** package manager

#### Automated Deployment

```bash
# Make script executable
chmod +x deploy.sh

# Run deployment
./deploy.sh
```

The script will automatically install everything (~5-10 minutes):
- Create namespaces (airflow, database, monitoring)
- Deploy PostgreSQL with persistent storage
- Deploy Prometheus and StatsD Exporter
- Deploy Grafana with Airflow dashboard
- Install Airflow 3.x using Helm
- Expose services via NodePort

### 🌐 Access

After successful deployment, access the services at:

| Service | URL | Username | Password |
|---------|-----|----------|----------|
| **Airflow UI** | http://localhost:30080 | admin | admin |
| **Grafana** | http://localhost:30030 | admin | admin |
| **Prometheus** | http://localhost:30090 | - | - |

### 📊 Grafana Dashboards

The system includes **7 Dashboards** for monitoring Airflow from different perspectives:
- **Airflow Metrics** - Real-time metrics from Prometheus
- **Airflow DAGs** - Overview of DAG and Task status
- **Airflow DAGs Status Grid** - DAG status in grid layout
- **Airflow Task Performance** - Analyze performance, retry rate, queue time
- **Airflow Resource & Pool** - Monitor pool usage and slot allocation
- **Airflow Error & Debugging** - Track errors and failures
- **Airflow DAG Dependencies & Lineage** - Monitor dependencies and asset relationships

📖 **[See full details and SQL queries in GRAFANA_DASHBOARDS.md](GRAFANA_DASHBOARDS.md)**

### 📁 Project Structure

```
airflowtoolkit/
├── k8s/
│   ├── namespaces.yaml                    # Namespace definitions
│   ├── database/                          # PostgreSQL manifests
│   │   ├── postgresql-secret.yaml
│   │   ├── postgresql-pvc.yaml
│   │   ├── postgresql-deployment.yaml
│   │   └── postgresql-service.yaml
│   ├── airflow/                           # Airflow configurations
│   │   ├── values.yaml                    # Helm values
│   │   ├── api-server-nodeport.yaml       # NodePort service
│   │   └── example-dag.py                 # Example DAG
│   └── monitoring/                        # Monitoring stack
│       ├── prometheus-*.yaml              # Prometheus configs
│       ├── statsd-*.yaml                  # StatsD Exporter
│       └── grafana-*.yaml                 # Grafana configs
├── deploy.sh                              # Deployment script
├── cleanup.sh                             # Cleanup script
├── DEPLOYMENT.md                          # Detailed deployment guide
├── TROUBLESHOOTING.md                     # Troubleshooting guide
└── README.md                              # This file
```

### 🛠️ Useful Commands

```bash
# View all pods status
kubectl get pods -A

# View scheduler logs
kubectl logs -f -n airflow -l component=scheduler

# View API server logs
kubectl logs -f -n airflow -l component=api-server

# Scale scheduler
kubectl scale deployment airflow-scheduler -n airflow --replicas=2

# Execute into pod
kubectl exec -it <pod-name> -n airflow -- bash

# Port forward (if NodePort doesn't work)
kubectl port-forward -n airflow svc/airflow-api-server 8080:8080
```

### 🔧 Customization

#### Change Airflow Version

Edit `k8s/airflow/values.yaml`:
```yaml
images:
  airflow:
    tag: "3.0.2"  # Change to desired version
```

#### Add DAGs

1. **Method 1**: Copy DAG files to persistent volume
2. **Method 2**: Use Git-sync (edit values.yaml):
```yaml
dags:
  gitSync:
    enabled: true
    repo: https://github.com/your-repo/dags.git
    branch: main
    subPath: dags
```

#### Adjust Resources

Edit `k8s/airflow/values.yaml`:
```yaml
scheduler:
  resources:
    limits:
      memory: "2Gi"
      cpu: "2000m"
```

### 🧹 Cleanup

```bash
# Remove all components
./cleanup.sh

# Or manual cleanup
helm uninstall airflow -n airflow
kubectl delete -f k8s/monitoring/
kubectl delete -f k8s/database/
kubectl delete -f k8s/namespaces.yaml
```

### 📚 Documentation

- **[DEPLOYMENT.md](DEPLOYMENT.md)** - Detailed deployment guide with step-by-step instructions
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common issues and solutions
- **[GRAFANA_DASHBOARDS.md](GRAFANA_DASHBOARDS.md)** - Complete guide to all 7 Grafana Dashboards with SQL queries

### ⚠️ Important Notes

- **Production Use**: Change default passwords and use proper secrets management
- **Resource Limits**: Adjust resource limits based on your workload
- **Backup**: Regularly backup PostgreSQL database
- **Monitoring**: Monitor metrics in Grafana to optimize performance

### 🤝 Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change.

### 📄 License

MIT License - Free to use

---

## 🔗 Quick Links

- [Apache Airflow Documentation](https://airflow.apache.org/docs/)
- [Airflow Helm Chart](https://airflow.apache.org/docs/helm-chart/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)

## 📞 Support

For issues and questions:
- Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) first
- Review [DEPLOYMENT.md](DEPLOYMENT.md) for detailed instructions
- Open an issue on GitHub
