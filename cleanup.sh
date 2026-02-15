#!/bin/bash

set -e

echo "=========================================="
echo "Cleaning up Airflow Deployment"
echo "=========================================="
echo ""

# Uninstall Airflow
echo "Step 1: Uninstalling Airflow..."
helm uninstall airflow -n airflow 2>/dev/null || echo "  (Airflow not installed)"

echo ""
echo "Step 2: Deleting Airflow resources..."
kubectl delete -f k8s/airflow/api-server-nodeport.yaml -n airflow 2>/dev/null || true

echo ""
echo "Step 3: Deleting monitoring resources..."
kubectl delete -f k8s/monitoring/ 2>/dev/null || echo "  (No monitoring resources)"

echo ""
echo "Step 4: Deleting database resources..."
kubectl delete -f k8s/database/ 2>/dev/null || echo "  (No database resources)"

echo ""
echo "Step 5: Deleting PersistentVolumeClaims..."
kubectl delete pvc --all -n airflow 2>/dev/null || true
kubectl delete pvc --all -n database 2>/dev/null || true
kubectl delete pvc --all -n monitoring 2>/dev/null || true

echo ""
echo "Step 6: Deleting namespaces..."
kubectl delete -f k8s/namespaces.yaml 2>/dev/null || echo "  (Namespaces not found)"

echo ""
echo "Step 7: Waiting for namespaces to be deleted..."
kubectl wait --for=delete namespace/airflow --timeout=60s 2>/dev/null || true
kubectl wait --for=delete namespace/database --timeout=60s 2>/dev/null || true
kubectl wait --for=delete namespace/monitoring --timeout=60s 2>/dev/null || true

echo ""
echo "=========================================="
echo "Cleanup Complete!"
echo "=========================================="
echo ""
echo "All resources have been removed."
echo "You can now run ./deploy.sh to start fresh."
echo ""
echo ""
