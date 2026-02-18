#!/bin/bash

set -e

echo "=========================================="
echo "Sync DAGs from Git Repository"
echo "=========================================="
echo ""

# Configuration
GIT_REPO="https://github.com/preedep/airflowtoolkit.git"
GIT_BRANCH="develop"
TEMP_DIR="/tmp/airflowtoolkit-dags-sync"

# Check if Airflow is running
echo "🔍 Checking if Airflow is running..."
if ! kubectl get deployment airflow-scheduler -n airflow &> /dev/null; then
    echo "❌ Error: Airflow is not deployed yet"
    echo "   Please run ./deploy.sh first"
    exit 1
fi

echo "✅ Airflow is running"
echo ""

# Clone or pull latest from Git
if [ -d "$TEMP_DIR" ]; then
    echo "📥 Pulling latest changes from Git..."
    cd "$TEMP_DIR"
    git fetch origin
    git reset --hard origin/$GIT_BRANCH
    cd -
else
    echo "📥 Cloning repository from Git..."
    git clone --depth 1 --branch $GIT_BRANCH $GIT_REPO $TEMP_DIR
fi

echo "✅ Git sync complete"
echo ""

# Check if dags directory exists
if [ ! -d "$TEMP_DIR/dags" ]; then
    echo "❌ Error: dags directory not found in repository"
    exit 1
fi

# Get list of DAG files
DAG_FILES=$(find "$TEMP_DIR/dags" -name "*.py" -type f)
DAG_COUNT=$(echo "$DAG_FILES" | wc -l | tr -d ' ')

echo "📋 Found $DAG_COUNT DAG file(s) to sync"
echo ""

# Get all relevant pods
SCHEDULER_PODS=$(kubectl get pods -n airflow -l component=scheduler -o jsonpath='{.items[*].metadata.name}')
DAG_PROCESSOR_PODS=$(kubectl get pods -n airflow -l component=dag-processor -o jsonpath='{.items[*].metadata.name}')
WEBSERVER_PODS=$(kubectl get pods -n airflow -l component=webserver -o jsonpath='{.items[*].metadata.name}')

# Copy DAGs to scheduler pods
for POD in $SCHEDULER_PODS; do
    echo "📦 Syncing to scheduler pod: $POD"
    for DAG_FILE in $DAG_FILES; do
        DAG_NAME=$(basename "$DAG_FILE")
        kubectl cp "$DAG_FILE" airflow/$POD:/opt/airflow/dags/$DAG_NAME -c scheduler
    done
    echo "✅ Synced to $POD"
done

# Copy DAGs to dag-processor pods
for POD in $DAG_PROCESSOR_PODS; do
    echo "📦 Syncing to dag-processor pod: $POD"
    for DAG_FILE in $DAG_FILES; do
        DAG_NAME=$(basename "$DAG_FILE")
        kubectl cp "$DAG_FILE" airflow/$POD:/opt/airflow/dags/$DAG_NAME -c dag-processor
    done
    echo "✅ Synced to $POD"
done

# Copy DAGs to webserver pods (if any)
if [ -n "$WEBSERVER_PODS" ]; then
    for POD in $WEBSERVER_PODS; do
        echo "📦 Syncing to webserver pod: $POD"
        for DAG_FILE in $DAG_FILES; do
            DAG_NAME=$(basename "$DAG_FILE")
            kubectl cp "$DAG_FILE" airflow/$POD:/opt/airflow/dags/$DAG_NAME -c webserver
        done
        echo "✅ Synced to $POD"
    done
fi

echo ""
echo "✅ All DAG files synced successfully!"
echo ""

# Verify
echo "📋 Verifying DAGs in scheduler..."
FIRST_SCHEDULER=$(echo $SCHEDULER_PODS | awk '{print $1}')
kubectl exec -n airflow $FIRST_SCHEDULER -c scheduler -- ls -la /opt/airflow/dags/

echo ""
echo "⏳ Waiting for DAGs to be parsed (30 seconds)..."
sleep 30

echo ""
echo "📊 Checking parsed DAGs..."
kubectl exec -n airflow deployment/airflow-scheduler -c scheduler -- airflow dags list 2>&1 | grep -v "^Error:" | tail -20

echo ""
echo "=========================================="
echo "✅ Sync Complete!"
echo "=========================================="
echo ""
echo "🌐 Access Airflow UI: http://localhost:30080"
echo "   Username: admin"
echo "   Password: admin"
echo ""
echo "💡 To sync DAGs again after Git changes:"
echo "   git push origin $GIT_BRANCH"
echo "   ./sync_dags_from_git.sh"
echo ""
echo "🔄 Synced from: $GIT_REPO (branch: $GIT_BRANCH)"
echo ""
