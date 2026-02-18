#!/bin/bash

set -e

echo "=========================================="
echo "Setup DAGs Local Mount"
echo "=========================================="
echo ""

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
    echo "🍎 Detected: macOS (Docker Desktop)"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
    echo "🐧 Detected: Linux"
else
    echo "❌ Unsupported OS: $OSTYPE"
    exit 1
fi

# Get current directory
CURRENT_DIR=$(pwd)
DAGS_DIR="$CURRENT_DIR/dags"

echo "📁 DAGs directory: $DAGS_DIR"
echo ""

# Check if dags directory exists
if [ ! -d "$DAGS_DIR" ]; then
    echo "❌ Error: dags directory not found at $DAGS_DIR"
    exit 1
fi

# Check if baseline_compute_daily.py exists
if [ ! -f "$DAGS_DIR/baseline_compute_daily.py" ]; then
    echo "⚠️  Warning: baseline_compute_daily.py not found in dags directory"
fi

# Update values.yaml with correct path
echo "📝 Updating k8s/airflow/values.yaml with local path..."

# Create backup
cp k8s/airflow/values.yaml k8s/airflow/values.yaml.bak

# Update the hostPath in values.yaml
if [[ "$OS" == "macos" ]]; then
    # For macOS Docker Desktop, use /Users path
    sed -i '' "s|path: /Users/.*/Projects/AirflowToolkit/airflowtoolkit/dags|path: $DAGS_DIR|g" k8s/airflow/values.yaml
    sed -i '' "s|path: /home/.*/Projects/AirflowToolkit/airflowtoolkit/dags|path: $DAGS_DIR|g" k8s/airflow/values.yaml
else
    # For Linux, use /home path
    sed -i "s|path: /Users/.*/Projects/AirflowToolkit/airflowtoolkit/dags|path: $DAGS_DIR|g" k8s/airflow/values.yaml
    sed -i "s|path: /home/.*/Projects/AirflowToolkit/airflowtoolkit/dags|path: $DAGS_DIR|g" k8s/airflow/values.yaml
fi

echo "✅ Updated values.yaml with path: $DAGS_DIR"
echo ""

# Show the configuration
echo "📋 Current DAGs mount configuration:"
grep -A 3 "hostPath:" k8s/airflow/values.yaml | grep "path:"
echo ""

echo "=========================================="
echo "✅ Setup Complete!"
echo "=========================================="
echo ""
echo "📝 Next steps:"
echo "1. Review the updated k8s/airflow/values.yaml"
echo "2. If Airflow is already running, upgrade it:"
echo "   helm upgrade airflow apache-airflow/airflow -n airflow -f k8s/airflow/values.yaml --wait"
echo "3. Or deploy from scratch:"
echo "   ./deploy.sh"
echo ""
echo "💡 Your DAGs will now be automatically synced from:"
echo "   $DAGS_DIR"
echo ""
echo "🔄 Any changes to DAG files will be picked up by Airflow automatically!"
echo ""
