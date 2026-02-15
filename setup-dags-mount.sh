#!/bin/bash

set -e

echo "=========================================="
echo "Setting up DAGs Mount for Airflow"
echo "=========================================="
echo ""

NAMESPACE="airflow"

# Check if Airflow is deployed
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "Error: Airflow namespace not found!"
    echo "Please run ./deploy.sh first to deploy Airflow."
    exit 1
fi

echo "Step 1: Creating initial DAGs ConfigMap..."
kubectl apply -f k8s/airflow/dags-configmap.yaml

echo ""
echo "Step 2: Patching Airflow deployments to mount DAGs..."

# Patch scheduler
echo "Patching scheduler..."
kubectl patch deployment airflow-scheduler -n "$NAMESPACE" --type='strategic' --patch '
spec:
  template:
    spec:
      containers:
      - name: scheduler
        volumeMounts:
        - name: dags
          mountPath: /opt/airflow/dags
          readOnly: true
      volumes:
      - name: dags
        configMap:
          name: airflow-dags
'

# Patch dag-processor
echo "Patching dag-processor..."
kubectl patch deployment airflow-dag-processor -n "$NAMESPACE" --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/volumes/1",
    "value": {
      "name": "dags",
      "configMap": {
        "name": "airflow-dags"
      }
    }
  }
]'

# Patch triggerer
echo "Patching triggerer..."
kubectl patch statefulset airflow-triggerer -n "$NAMESPACE" --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/volumes/1",
    "value": {
      "name": "dags",
      "configMap": {
        "name": "airflow-dags"
      }
    }
  }
]'

echo ""
echo "Step 3: Syncing DAG files..."
./sync-dags.sh

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "DAGs folder is now mounted to Airflow!"
echo ""
echo "To add or update DAGs:"
echo "  1. Add/modify Python files in k8s/airflow/dags/"
echo "  2. Run: ./sync-dags.sh"
echo ""
echo "Your DAGs will be available at: http://localhost:30080"
echo ""
