#!/bin/bash

set -e

DAGS_DIR="k8s/airflow/dags"
NAMESPACE="airflow"
CONFIGMAP_NAME="airflow-dags"

echo "=========================================="
echo "Syncing DAGs to Kubernetes"
echo "=========================================="
echo ""

# Check if dags directory exists
if [ ! -d "$DAGS_DIR" ]; then
    echo "Error: DAGs directory '$DAGS_DIR' not found!"
    exit 1
fi

# Count DAG files
DAG_COUNT=$(find "$DAGS_DIR" -name "*.py" -not -path "*/\.*" | wc -l | tr -d ' ')
echo "Found $DAG_COUNT Python file(s) in $DAGS_DIR"
echo ""

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "Error: Namespace '$NAMESPACE' does not exist!"
    echo "Please run ./deploy.sh first to create the Airflow deployment."
    exit 1
fi

# Delete existing ConfigMap if it exists
if kubectl get configmap "$CONFIGMAP_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "Deleting existing ConfigMap..."
    kubectl delete configmap "$CONFIGMAP_NAME" -n "$NAMESPACE"
fi

# Create ConfigMap from dags directory
echo "Creating ConfigMap from DAGs directory..."
kubectl create configmap "$CONFIGMAP_NAME" \
    --from-file="$DAGS_DIR" \
    --namespace="$NAMESPACE"

echo ""
echo "ConfigMap created successfully!"
echo ""

# List files in ConfigMap
echo "Files in ConfigMap:"
kubectl get configmap "$CONFIGMAP_NAME" -n "$NAMESPACE" -o jsonpath='{.data}' | jq -r 'keys[]' 2>/dev/null || \
kubectl get configmap "$CONFIGMAP_NAME" -n "$NAMESPACE" -o json | grep -o '"[^"]*\.py"' | tr -d '"'

echo ""
echo "=========================================="
echo "Restarting Airflow components..."
echo "=========================================="
echo ""

# Restart scheduler to pick up new DAGs
echo "Restarting scheduler..."
kubectl rollout restart deployment airflow-scheduler -n "$NAMESPACE"

# Restart dag-processor
echo "Restarting dag-processor..."
kubectl rollout restart deployment airflow-dag-processor -n "$NAMESPACE"

# Restart triggerer
echo "Restarting triggerer..."
kubectl rollout restart statefulset airflow-triggerer -n "$NAMESPACE"

echo ""
echo "Waiting for scheduler to be ready..."
kubectl rollout status deployment airflow-scheduler -n "$NAMESPACE" --timeout=120s

echo ""
echo "Waiting for dag-processor to be ready..."
kubectl rollout status deployment airflow-dag-processor -n "$NAMESPACE" --timeout=120s

echo ""
echo "=========================================="
echo "DAG Sync Complete!"
echo "=========================================="
echo ""
echo "Your DAGs should now be visible in Airflow UI:"
echo "  http://localhost:30080"
echo ""
echo "To sync DAGs again after making changes, run:"
echo "  ./sync-dags.sh"
echo ""
