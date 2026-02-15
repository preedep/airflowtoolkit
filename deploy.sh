#!/bin/bash

set -e

echo "=========================================="
echo "Airflow 3.x on Kubernetes Deployment"
echo "=========================================="
echo ""

echo "Step 1: Creating namespaces..."
kubectl apply -f k8s/namespaces.yaml

echo ""
echo "Step 2: Deploying PostgreSQL..."
kubectl apply -f k8s/database/postgresql-secret.yaml
kubectl apply -f k8s/database/postgresql-pvc.yaml
kubectl apply -f k8s/database/postgresql-deployment.yaml
kubectl apply -f k8s/database/postgresql-service.yaml

echo "Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=ready pod -l app=postgresql -n database --timeout=300s

echo ""
echo "Step 3: Deploying Prometheus and StatsD Exporter..."
kubectl apply -f k8s/monitoring/prometheus-rbac.yaml
kubectl apply -f k8s/monitoring/prometheus-pvc.yaml
kubectl apply -f k8s/monitoring/prometheus-config.yaml
kubectl apply -f k8s/monitoring/prometheus-deployment.yaml
kubectl apply -f k8s/monitoring/prometheus-service.yaml

kubectl apply -f k8s/monitoring/statsd-mapping-config.yaml
kubectl apply -f k8s/monitoring/statsd-exporter-deployment.yaml
kubectl apply -f k8s/monitoring/statsd-exporter-service.yaml

echo "Waiting for Prometheus to be ready..."
kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=300s

echo "Waiting for StatsD Exporter to be ready..."
kubectl wait --for=condition=ready pod -l app=statsd-exporter -n monitoring --timeout=300s

echo ""
echo "Step 4: Deploying Grafana..."
kubectl apply -f k8s/monitoring/grafana-pvc.yaml
kubectl apply -f k8s/monitoring/grafana-datasources.yaml
kubectl apply -f k8s/monitoring/grafana-dashboards-config.yaml
kubectl apply -f k8s/monitoring/grafana-airflow-dashboard.yaml
kubectl apply -f k8s/monitoring/grafana-airflow-db-dashboard.yaml
kubectl apply -f k8s/monitoring/grafana-deployment.yaml
kubectl apply -f k8s/monitoring/grafana-service.yaml

echo "Waiting for Grafana to be ready..."
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=300s

echo ""
echo "Step 5: Adding Airflow Helm repository..."
helm repo add apache-airflow https://airflow.apache.org
helm repo update

echo ""
echo "Step 6: Installing Airflow 3.x with Example DAGs..."
helm install airflow apache-airflow/airflow \
  --namespace airflow \
  --values k8s/airflow/values.yaml \
  --version 1.18.0 \
  --timeout 10m

echo ""
echo "Waiting for Airflow components to be ready..."
kubectl wait --for=condition=ready pod -l component=api-server -n airflow --timeout=600s
kubectl wait --for=condition=ready pod -l component=scheduler -n airflow --timeout=600s
kubectl wait --for=condition=ready pod -l component=dag-processor -n airflow --timeout=600s

echo ""
echo "Step 7: Exposing Airflow UI via NodePort..."
kubectl apply -f k8s/airflow/api-server-nodeport.yaml

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo "🌐 Access URLs (Docker Desktop):"
echo "  - Airflow UI:    http://localhost:30080"
echo "  - Grafana:       http://localhost:30030"
echo "  - Prometheus:    http://localhost:30090"
echo ""
echo "🔑 Default Credentials:"
echo "  Airflow:  admin / admin"
echo "  Grafana:  admin / admin"
echo ""
echo "📊 Airflow Example DAGs:"
echo "  Airflow is configured with load_examples=True"
echo "  You will see 30+ example DAGs in the UI"
echo "  These DAGs will generate metrics for Grafana dashboard"
echo ""
echo "📝 Useful Commands:"
echo "  kubectl get pods -n airflow"
echo "  kubectl get pods -n monitoring"
echo "  kubectl get pods -n database"
echo "  kubectl logs -f -n airflow -l component=scheduler"
echo "  kubectl logs -f -n airflow -l component=dag-processor"
echo ""
echo "🧹 To clean up everything:"
echo "  ./cleanup.sh"
echo ""
