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

echo "📋 Copying DAG file to all Airflow components..."
echo ""

# Get all relevant pods
SCHEDULER_PODS=$(kubectl get pods -n airflow -l component=scheduler -o jsonpath='{.items[*].metadata.name}')
DAG_PROCESSOR_PODS=$(kubectl get pods -n airflow -l component=dag-processor -o jsonpath='{.items[*].metadata.name}')
API_SERVER_PODS=$(kubectl get pods -n airflow -l component=api-server -o jsonpath='{.items[*].metadata.name}')

# Copy to scheduler pods
for POD in $SCHEDULER_PODS; do
    echo "📦 Copying to scheduler pod: $POD"
    kubectl cp dags/baseline_compute_daily.py airflow/$POD:/opt/airflow/dags/baseline_compute_daily.py -c scheduler
    echo "✅ Copied to $POD"
done

# Copy to dag-processor pods
for POD in $DAG_PROCESSOR_PODS; do
    echo "📦 Copying to dag-processor pod: $POD"
    kubectl cp dags/baseline_compute_daily.py airflow/$POD:/opt/airflow/dags/baseline_compute_daily.py -c dag-processor
    echo "✅ Copied to $POD"
done

# Copy to api-server pods (Airflow 3.x)
for POD in $API_SERVER_PODS; do
    echo "📦 Copying to api-server pod: $POD"
    kubectl cp dags/baseline_compute_daily.py airflow/$POD:/opt/airflow/dags/baseline_compute_daily.py -c api-server
    echo "✅ Copied to $POD"
done

echo ""
echo "✅ Verifying DAG file in scheduler..."
FIRST_SCHEDULER=$(echo $SCHEDULER_PODS | awk '{print $1}')
kubectl exec -n airflow $FIRST_SCHEDULER -c scheduler -- ls -la /opt/airflow/dags/baseline_compute_daily.py

echo ""
echo "✅ DAG file copied successfully!"
echo ""

# Wait for DAG to be parsed
echo "⏳ Waiting for DAG to be parsed..."
MAX_RETRIES=12
RETRY_COUNT=0
WAIT_SECONDS=10

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    echo "   Attempt $((RETRY_COUNT + 1))/$MAX_RETRIES (waiting ${WAIT_SECONDS}s)..."
    sleep $WAIT_SECONDS
    
    # Check if DAG is parsed
    if kubectl exec -n airflow deployment/airflow-scheduler -c scheduler -- airflow dags list 2>&1 | grep -q "baseline_compute_daily"; then
        echo "✅ DAG parsed successfully!"
        break
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "⚠️  DAG not yet parsed after $((MAX_RETRIES * WAIT_SECONDS)) seconds"
    echo "   Please check dag-processor logs:"
    echo "   kubectl logs -n airflow -l component=dag-processor -c dag-processor --tail=50"
    exit 1
fi

# Unpause the DAG
echo ""
echo "🔓 Unpausing baseline_compute_daily DAG..."
kubectl exec -n airflow deployment/airflow-scheduler -c scheduler -- airflow dags unpause baseline_compute_daily
echo "✅ DAG is now active!"

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
