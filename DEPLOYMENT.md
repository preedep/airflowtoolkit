# Airflow 3.x on Kubernetes with Monitoring

การติดตั้ง Apache Airflow 3.x บน Kubernetes (Docker Desktop) พร้อม PostgreSQL, Prometheus และ Grafana

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Namespace: airflow                                     │ │
│  │  - Webserver (NodePort: 30080)                        │ │
│  │  - Scheduler                                           │ │
│  │  - Triggerer                                           │ │
│  │  - Workers (KubernetesExecutor)                       │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Namespace: database                                    │ │
│  │  - PostgreSQL (with PVC)                              │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Namespace: monitoring                                  │ │
│  │  - Prometheus (NodePort: 30090)                       │ │
│  │  - StatsD Exporter                                    │ │
│  │  - Grafana (NodePort: 30030)                          │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **Docker Desktop** with Kubernetes enabled
2. **kubectl** CLI tool
3. **Helm 3** package manager

### ตรวจสอบ Prerequisites

```bash
# ตรวจสอบ Kubernetes
kubectl version --client
kubectl cluster-info

# ตรวจสอบ Helm
helm version
```

## Quick Start

### 1. Deploy ทั้งหมดด้วย Script

```bash
chmod +x deploy.sh
./deploy.sh
```

Script จะทำการ:
- สร้าง namespaces (airflow, database, monitoring)
- Deploy PostgreSQL พร้อม persistent storage
- Deploy Prometheus และ StatsD Exporter
- Deploy Grafana พร้อม Airflow dashboard
- Install Airflow 3.x ด้วย Helm

### 2. เข้าถึง Services

หลังจาก deployment สำเร็จ:

- **Airflow UI**: http://localhost:30080
  - Username: `admin`
  - Password: `admin`

- **Grafana**: http://localhost:30030
  - Username: `admin`
  - Password: `admin`
  - Dashboard: "Airflow Metrics Dashboard"

- **Prometheus**: http://localhost:30090

## Manual Deployment

หากต้องการ deploy แบบ manual:

### 1. สร้าง Namespaces

```bash
kubectl apply -f k8s/namespaces.yaml
```

### 2. Deploy PostgreSQL

```bash
kubectl apply -f k8s/database/postgresql-secret.yaml
kubectl apply -f k8s/database/postgresql-pvc.yaml
kubectl apply -f k8s/database/postgresql-deployment.yaml
kubectl apply -f k8s/database/postgresql-service.yaml

# รอให้ PostgreSQL พร้อม
kubectl wait --for=condition=ready pod -l app=postgresql -n database --timeout=300s
```

### 3. Deploy Monitoring Stack

```bash
# Prometheus
kubectl apply -f k8s/monitoring/prometheus-rbac.yaml
kubectl apply -f k8s/monitoring/prometheus-pvc.yaml
kubectl apply -f k8s/monitoring/prometheus-config.yaml
kubectl apply -f k8s/monitoring/prometheus-deployment.yaml
kubectl apply -f k8s/monitoring/prometheus-service.yaml

# StatsD Exporter
kubectl apply -f k8s/monitoring/statsd-mapping-config.yaml
kubectl apply -f k8s/monitoring/statsd-exporter-deployment.yaml
kubectl apply -f k8s/monitoring/statsd-exporter-service.yaml

# Grafana
kubectl apply -f k8s/monitoring/grafana-pvc.yaml
kubectl apply -f k8s/monitoring/grafana-datasources.yaml
kubectl apply -f k8s/monitoring/grafana-dashboards-config.yaml
kubectl apply -f k8s/monitoring/grafana-airflow-dashboard.yaml
kubectl apply -f k8s/monitoring/grafana-deployment.yaml
kubectl apply -f k8s/monitoring/grafana-service.yaml
```

### 4. Deploy Airflow

```bash
# เพิ่ม Helm repository
helm repo add apache-airflow https://airflow.apache.org
helm repo update

# Install Airflow
helm install airflow apache-airflow/airflow \
  --namespace airflow \
  --values k8s/airflow/values.yaml \
  --version 1.15.0 \
  --timeout 10m
```

## Configuration

### PostgreSQL

- **Database**: `airflow`
- **User**: `airflow`
- **Password**: `airflow123` (แก้ไขใน `k8s/database/postgresql-secret.yaml`)
- **Storage**: 10Gi PVC

### Airflow

- **Executor**: KubernetesExecutor
- **Version**: 3.0.0
- **Metrics**: StatsD enabled
- **DAGs**: Persistent volume (5Gi)
- **Logs**: Persistent volume (10Gi)

### Monitoring

- **Prometheus**: เก็บ metrics จาก Airflow ผ่าน StatsD Exporter
- **Grafana**: Dashboard แสดง Airflow metrics
- **StatsD Exporter**: แปลง StatsD metrics เป็น Prometheus format

## Useful Commands

### ตรวจสอบ Status

```bash
# ดู pods ทั้งหมด
kubectl get pods -A

# ดู pods ใน namespace airflow
kubectl get pods -n airflow

# ดู services
kubectl get svc -A
```

### ดู Logs

```bash
# Airflow Scheduler
kubectl logs -f -n airflow -l component=scheduler

# Airflow Webserver
kubectl logs -f -n airflow -l component=webserver

# PostgreSQL
kubectl logs -f -n database -l app=postgresql

# Prometheus
kubectl logs -f -n monitoring -l app=prometheus
```

### Troubleshooting

```bash
# ดู events
kubectl get events -n airflow --sort-by='.lastTimestamp'

# Describe pod
kubectl describe pod <pod-name> -n airflow

# เข้าไปใน pod
kubectl exec -it <pod-name> -n airflow -- bash

# Port forward (ถ้า NodePort ไม่ทำงาน)
kubectl port-forward -n airflow svc/airflow-webserver 8080:8080
```

### Scale Components

```bash
# Scale scheduler
kubectl scale deployment airflow-scheduler -n airflow --replicas=2

# Scale webserver
kubectl scale deployment airflow-webserver -n airflow --replicas=2
```

## Cleanup

ลบทุกอย่างออกจาก cluster:

```bash
chmod +x cleanup.sh
./cleanup.sh
```

หรือ manual:

```bash
# Uninstall Airflow
helm uninstall airflow -n airflow

# ลบ monitoring
kubectl delete -f k8s/monitoring/

# ลบ database
kubectl delete -f k8s/database/

# ลบ namespaces
kubectl delete -f k8s/namespaces.yaml
```

## Metrics Available in Grafana

Dashboard แสดง metrics ต่อไปนี้:

1. **Scheduler Heartbeat**: ตรวจสอบว่า scheduler ทำงานอยู่
2. **Executor Open Slots**: จำนวน slots ว่างสำหรับ tasks
3. **Task Queue Status**: tasks ที่รออยู่และกำลังทำงาน
4. **DAG Processing Time**: เวลาที่ใช้ในการ parse DAGs
5. **Task Success Rate**: อัตราความสำเร็จของ tasks แยกตาม DAG
6. **Task Failure Rate**: อัตราความล้มเหลวของ tasks แยกตาม DAG

## Customization

### เปลี่ยน Airflow Version

แก้ไขใน `k8s/airflow/values.yaml`:

```yaml
images:
  airflow:
    tag: "3.0.0"  # เปลี่ยนเป็น version ที่ต้องการ
```

### เพิ่ม DAGs

1. สร้าง DAG files ใน persistent volume
2. หรือใช้ Git-sync (แก้ไข values.yaml):

```yaml
dags:
  gitSync:
    enabled: true
    repo: https://github.com/your-repo/dags.git
    branch: main
    subPath: dags
```

### เปลี่ยน Database Password

1. แก้ไข `k8s/database/postgresql-secret.yaml`
2. แก้ไข `k8s/airflow/values.yaml` ส่วน `data.metadataConnection.pass`
3. Re-deploy

## Best Practices

1. **Namespaces**: แยก components ตาม namespace เพื่อ isolation
2. **Persistent Storage**: ใช้ PVC สำหรับ database, DAGs และ logs
3. **Resource Limits**: กำหนด CPU/Memory limits ทุก component
4. **Monitoring**: ใช้ Prometheus + Grafana ติดตาม metrics
5. **Security**: เปลี่ยน default passwords ใน production
6. **Backup**: สำรอง PostgreSQL database เป็นประจำ

## Troubleshooting Common Issues

### Pod ไม่ start

```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
```

### Database Connection Error

ตรวจสอบว่า PostgreSQL service พร้อมใช้งาน:

```bash
kubectl get svc -n database
kubectl exec -it <airflow-pod> -n airflow -- nc -zv postgresql.database.svc.cluster.local 5432
```

### Metrics ไม่แสดงใน Grafana

1. ตรวจสอบ Prometheus targets: http://localhost:30090/targets
2. ตรวจสอบ StatsD Exporter logs
3. ตรวจสอบว่า Airflow ส่ง metrics: ดู Airflow logs

## Support

สำหรับข้อมูลเพิ่มเติม:
- [Apache Airflow Documentation](https://airflow.apache.org/docs/)
- [Airflow Helm Chart](https://airflow.apache.org/docs/helm-chart/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
