#!/bin/bash

set -e

echo "=========================================="
echo "Cleaning up Airflow Kubernetes Deployment"
echo "=========================================="
echo ""

echo "Uninstalling Airflow..."
helm uninstall airflow -n airflow || true

echo ""
echo "Deleting monitoring resources..."
kubectl delete -f k8s/monitoring/ --ignore-not-found=true

echo ""
echo "Deleting database resources..."
kubectl delete -f k8s/database/ --ignore-not-found=true

echo ""
echo "Deleting namespaces..."
kubectl delete -f k8s/namespaces.yaml --ignore-not-found=true

echo ""
echo "Cleanup complete!"
echo ""
