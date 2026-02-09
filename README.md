# Airflow Toolkit

Complete Kubernetes deployment for Apache Airflow 3.x with monitoring stack.

## Quick Start

```bash
./deploy.sh
```

## Documentation

See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed instructions.

## Components

- **Airflow 3.x**: Latest version with KubernetesExecutor
- **PostgreSQL 16**: Metadata database
- **Prometheus**: Metrics collection
- **Grafana**: Metrics visualization
- **StatsD Exporter**: Airflow metrics export

## Access

- Airflow UI: http://localhost:30080 (admin/admin)
- Grafana: http://localhost:30030 (admin/admin)
- Prometheus: http://localhost:30090
