#!/bin/bash

set -e

echo "=========================================="
echo "Airflow 3.x on Kubernetes Deployment"
echo "=========================================="
echo ""

# Load environment variables from .env file if it exists
if [ -f .env ]; then
    echo "📄 Loading configuration from .env file..."
    export $(grep -v '^#' .env | xargs)
else
    echo "⚠️  No .env file found, using defaults..."
fi

# Set default AIRFLOW_HOST if not defined
AIRFLOW_HOST=${AIRFLOW_HOST:-http://localhost:30080}
echo "🌐 Airflow Host: $AIRFLOW_HOST"
echo ""

# Detect platform and set appropriate storage class
STORAGE_CLASS="hostpath"
if kubectl get storageclass microk8s-hostpath &> /dev/null; then
    STORAGE_CLASS="microk8s-hostpath"
    echo "✅ Detected microk8s platform"
elif kubectl get storageclass hostpath &> /dev/null; then
    STORAGE_CLASS="hostpath"
    echo "✅ Detected Docker Desktop platform"
else
    echo "⚠️  No known storage class found, using default: $STORAGE_CLASS"
fi

echo "Using storage class: $STORAGE_CLASS"
echo ""

# Create temporary directory for processed manifests
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

# Process PVC files with correct storage class
for pvc_file in k8s/database/postgresql-pvc.yaml k8s/monitoring/prometheus-pvc.yaml k8s/monitoring/grafana-pvc.yaml; do
    sed "s/storageClassName: .*/storageClassName: $STORAGE_CLASS/" "$pvc_file" > "$TMP_DIR/$(basename $pvc_file)"
done

# Process Airflow values.yaml with correct storage class
sed "s/storageClassName: .*/storageClassName: $STORAGE_CLASS/" k8s/airflow/values.yaml > "$TMP_DIR/values.yaml"

# Process Grafana dashboard files with AIRFLOW_HOST
for dashboard_file in k8s/monitoring/grafana-airflow-*.yaml; do
    sed "s|\"query\": \"http://localhost:30080\"|\"query\": \"$AIRFLOW_HOST\"|g; s|\"value\": \"http://localhost:30080\"|\"value\": \"$AIRFLOW_HOST\"|g; s|\"text\": \"http://localhost:30080\"|\"text\": \"$AIRFLOW_HOST\"|g" "$dashboard_file" > "$TMP_DIR/$(basename $dashboard_file)"
done

# Also process the DAG tasks explorer dashboard
if [ -f k8s/monitoring/grafana-airflow-dag-tasks-dashboard.yaml ]; then
    sed "s|\"query\": \"http://localhost:30080\"|\"query\": \"$AIRFLOW_HOST\"|g; s|\"value\": \"http://localhost:30080\"|\"value\": \"$AIRFLOW_HOST\"|g; s|\"text\": \"http://localhost:30080\"|\"text\": \"$AIRFLOW_HOST\"|g" k8s/monitoring/grafana-airflow-dag-tasks-dashboard.yaml > "$TMP_DIR/grafana-airflow-dag-tasks-dashboard.yaml"
fi

echo "Step 1: Creating namespaces..."
kubectl apply -f k8s/namespaces.yaml

echo ""
echo "Step 2: Deploying PostgreSQL..."
kubectl apply -f k8s/database/postgresql-secret.yaml
kubectl apply -f "$TMP_DIR/postgresql-pvc.yaml"
kubectl apply -f k8s/database/airflow-extension-init-configmap.yaml
kubectl apply -f k8s/database/postgresql-deployment.yaml
kubectl apply -f k8s/database/postgresql-service.yaml

echo "Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=ready pod -l app=postgresql -n database --timeout=300s

echo ""
echo "Step 3: Deploying Prometheus and StatsD Exporter..."
kubectl apply -f k8s/monitoring/prometheus-rbac.yaml
kubectl apply -f "$TMP_DIR/prometheus-pvc.yaml"
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
kubectl apply -f "$TMP_DIR/grafana-pvc.yaml"
kubectl apply -f k8s/monitoring/grafana-datasources.yaml
kubectl apply -f k8s/monitoring/grafana-dashboards-config.yaml
kubectl apply -f "$TMP_DIR/grafana-airflow-dashboard.yaml"
kubectl apply -f "$TMP_DIR/grafana-airflow-db-dashboard.yaml"
kubectl apply -f "$TMP_DIR/grafana-airflow-status-dashboard.yaml"
kubectl apply -f "$TMP_DIR/grafana-airflow-task-performance-dashboard.yaml"
kubectl apply -f "$TMP_DIR/grafana-airflow-resource-pool-dashboard.yaml"
kubectl apply -f "$TMP_DIR/grafana-airflow-error-debug-dashboard.yaml"
kubectl apply -f "$TMP_DIR/grafana-airflow-dependencies-dashboard.yaml"
kubectl apply -f "$TMP_DIR/grafana-airflow-dag-tasks-dashboard.yaml"
kubectl apply -f "$TMP_DIR/grafana-airflow-job-flow-dashboard.yaml"
kubectl apply -f k8s/monitoring/grafana-deployment.yaml
kubectl apply -f k8s/monitoring/grafana-service.yaml

echo "Waiting for Grafana to be ready..."
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=300s

echo ""
echo "Step 5: Adding Airflow Helm repository..."
helm repo add apache-airflow https://airflow.apache.org
helm repo update

echo ""
echo "Step 6: Deploying Airflow Connections and Baseline DAG..."
kubectl apply -f k8s/airflow/airflow-connections-secret.yaml
kubectl apply -f k8s/airflow/baseline-dag-configmap.yaml

echo ""
echo "Step 7: Installing Airflow 3.x with Example DAGs..."
helm upgrade --install airflow apache-airflow/airflow \
  --namespace airflow \
  --values "$TMP_DIR/values.yaml" \
  --version 1.18.0 \
  --timeout 10m

echo ""
echo "Waiting for Airflow components to be ready..."
kubectl wait --for=condition=ready pod -l component=api-server -n airflow --timeout=600s
kubectl wait --for=condition=ready pod -l component=scheduler -n airflow --timeout=600s
kubectl wait --for=condition=ready pod -l component=dag-processor -n airflow --timeout=600s

echo ""
echo "Step 8: Exposing Airflow UI via NodePort..."
kubectl apply -f k8s/airflow/api-server-nodeport.yaml

echo ""
echo "Step 9: Copying Baseline DAG to Airflow DAGs volume..."
# Create temporary pod to copy DAG file to PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: dag-copier
  namespace: airflow
spec:
  restartPolicy: Never
  containers:
  - name: copier
    image: busybox:latest
    command: ['sh', '-c', 'sleep 60']
    volumeMounts:
    - name: dags
      mountPath: /opt/airflow/dags
  volumes:
  - name: dags
    persistentVolumeClaim:
      claimName: airflow-dags
EOF

# Wait for pod to be ready
kubectl wait --for=condition=ready pod/dag-copier -n airflow --timeout=60s

# Copy DAG file
kubectl cp dags/baseline_compute_daily.py airflow/dag-copier:/opt/airflow/dags/baseline_compute_daily.py

# Verify copy
echo "Verifying DAG file..."
kubectl exec -n airflow dag-copier -- ls -la /opt/airflow/dags/baseline_compute_daily.py

# Delete temporary pod
kubectl delete pod dag-copier -n airflow

echo "✅ Baseline DAG copied successfully"

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
