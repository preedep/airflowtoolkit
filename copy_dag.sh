#!/bin/bash

set -e

echo "=========================================="
echo "Copy Baseline DAG to Airflow"
echo "=========================================="
echo ""

# Check if Airflow is running
echo "🔍 Checking if Airflow is running..."
if ! kubectl get deployment airflow-scheduler -n airflow &> /dev/null; then
    echo "❌ Error: Airflow is not deployed yet"
    echo "   Please run ./deploy.sh first"
    exit 1
fi

echo "✅ Airflow is running"
echo ""

# Check if DAG file exists
if [ ! -f "dags/baseline_compute_daily.py" ]; then
    echo "❌ Error: DAG file not found at dags/baseline_compute_daily.py"
    exit 1
fi

echo "📦 Creating temporary pod to copy DAG file..."

# Delete existing dag-copier pod if exists
kubectl delete pod dag-copier -n airflow 2>/dev/null || true

# Create temporary pod
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
    command: ['sh', '-c', 'sleep 120']
    volumeMounts:
    - name: dags
      mountPath: /opt/airflow/dags
  volumes:
  - name: dags
    persistentVolumeClaim:
      claimName: airflow-dags
EOF

echo "⏳ Waiting for pod to be ready..."
kubectl wait --for=condition=ready pod/dag-copier -n airflow --timeout=60s

echo "📋 Copying DAG file to Airflow dags volume..."
kubectl cp dags/baseline_compute_daily.py airflow/dag-copier:/opt/airflow/dags/baseline_compute_daily.py

echo "✅ Verifying DAG file..."
kubectl exec -n airflow dag-copier -- ls -la /opt/airflow/dags/baseline_compute_daily.py

echo "🧹 Cleaning up temporary pod..."
kubectl delete pod dag-copier -n airflow

echo ""
echo "✅ DAG file copied successfully!"
echo ""

# Wait for DAG to be parsed
echo "⏳ Waiting for DAG to be parsed by dag-processor..."
echo "   This may take 1-3 minutes depending on the number of DAGs"
echo ""

# Try to check if DAG is parsed (with retries)
MAX_RETRIES=6
RETRY_INTERVAL=10
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "🔍 Checking if DAG is parsed (attempt $RETRY_COUNT/$MAX_RETRIES)..."
    
    if kubectl exec -n airflow deployment/airflow-scheduler -- airflow dags list 2>&1 | grep -q baseline_compute_daily; then
        echo "✅ DAG found in Airflow!"
        
        # Check if DAG is paused
        IS_PAUSED=$(kubectl exec -n airflow deployment/airflow-scheduler -- airflow dags list 2>&1 | grep baseline_compute_daily | awk '{print $5}')
        
        if [ "$IS_PAUSED" = "True" ]; then
            echo "🔓 Unpausing DAG..."
            kubectl exec -n airflow deployment/airflow-scheduler -- airflow dags unpause baseline_compute_daily
            echo "✅ DAG is now active!"
        else
            echo "✅ DAG is already active!"
        fi
        
        # Success - exit loop
        break
    else
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo "⏳ DAG not yet parsed, waiting ${RETRY_INTERVAL} seconds..."
            sleep $RETRY_INTERVAL
        else
            echo ""
            echo "⚠️  DAG not yet parsed after $((MAX_RETRIES * RETRY_INTERVAL)) seconds."
            echo "   This is normal if you have many DAGs or just deployed Airflow."
            echo ""
            echo "   The DAG will appear in Airflow UI within a few minutes."
            echo "   You can manually unpause it in the UI or run:"
            echo "   kubectl exec -n airflow deployment/airflow-scheduler -- airflow dags unpause baseline_compute_daily"
        fi
    fi
done

echo ""
echo "=========================================="
echo "✅ Complete!"
echo "=========================================="
echo ""
echo "🌐 Access Airflow UI: http://localhost:30080"
echo "   Username: admin"
echo "   Password: admin"
echo ""
echo "🚀 To trigger the DAG manually:"
echo "   kubectl exec -n airflow deployment/airflow-scheduler -- airflow dags trigger baseline_compute_daily"
echo ""
