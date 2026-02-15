#!/usr/bin/env python3
"""
Generate Grafana dashboard with DAG status grid layout (Dynamic)
This dashboard uses a single SQL query to dynamically show all DAGs without hardcoding.
"""
import json

print("Generating dynamic DAG status grid dashboard...")
print("This dashboard will automatically show all DAGs from the database.")

# Create a single dynamic table panel that shows all DAGs
# This will automatically update when DAGs are added/removed
panels = [
    {
        "datasource": "Airflow PostgreSQL",
        "fieldConfig": {
            "defaults": {
                "custom": {
                    "align": "center",
                    "displayMode": "color-background",
                    "cellOptions": {
                        "type": "auto"
                    }
                },
                "mappings": [],
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "light-gray", "value": None},
                        {"color": "light-gray", "value": 0},
                        {"color": "dark-gray", "value": 1},
                        {"color": "green", "value": 2},
                        {"color": "red", "value": 3},
                        {"color": "blue", "value": 4},
                        {"color": "yellow", "value": 5}
                    ]
                }
            },
            "overrides": [
                {
                    "matcher": {"id": "byName", "options": "DAG"},
                    "properties": [
                        {"id": "custom.width", "value": 200},
                        {"id": "custom.displayMode", "value": "color-background"}
                    ]
                },
                {
                    "matcher": {"id": "byName", "options": "Status"},
                    "properties": [
                        {"id": "custom.width", "value": 100},
                        {"id": "custom.displayMode", "value": "color-background"}
                    ]
                }
            ]
        },
        "gridPos": {"h": 30, "w": 24, "x": 0, "y": 0},
        "id": 1,
        "options": {
            "showHeader": True,
            "cellHeight": "sm",
            "footer": {"show": False},
            "sortBy": [{"desc": False, "displayName": "DAG"}]
        },
        "pluginVersion": "9.0.0",
        "targets": [
            {
                "datasource": "Airflow PostgreSQL",
                "format": "table",
                "rawSql": """
WITH dag_status AS (
  SELECT 
    d.dag_id,
    d.is_paused,
    dr.state as latest_state,
    dr.start_date as latest_start
  FROM dag d
  LEFT JOIN LATERAL (
    SELECT state, start_date
    FROM dag_run
    WHERE dag_run.dag_id = d.dag_id
    ORDER BY start_date DESC
    LIMIT 1
  ) dr ON true
  WHERE d.bundle_name IS NOT NULL
)
SELECT 
  SUBSTRING(dag_id, 1, 30) as "DAG",
  CASE 
    WHEN latest_state = 'running' THEN 2
    WHEN latest_state = 'failed' THEN 3
    WHEN latest_state = 'success' THEN 4
    WHEN is_paused = true THEN 1
    WHEN latest_start IS NOT NULL THEN 5
    ELSE 0
  END as "Status",
  CASE 
    WHEN latest_state = 'running' THEN 'Running'
    WHEN latest_state = 'failed' THEN 'Failed'
    WHEN latest_state = 'success' THEN 'Success'
    WHEN is_paused = true THEN 'Paused'
    WHEN latest_start IS NOT NULL THEN 'Idle'
    ELSE 'Never Run'
  END as "State"
FROM dag_status
ORDER BY dag_id;
                """,
                "refId": "A"
            }
        ],
        "title": "All DAGs Status (Dynamic)",
        "type": "table"
    }
]

# Create dashboard JSON
dashboard = {
    "annotations": {
        "list": []
    },
    "editable": True,
    "gnetId": None,
    "graphTooltip": 0,
    "id": None,
    "links": [],
    "panels": panels,
    "refresh": "30s",
    "schemaVersion": 27,
    "style": "dark",
    "tags": ["airflow", "status", "grid"],
    "templating": {
        "list": []
    },
    "time": {
        "from": "now-6h",
        "to": "now"
    },
    "timepicker": {},
    "timezone": "",
    "title": "Airflow DAGs Status Grid",
    "uid": "airflow-dags-status-grid",
    "version": 1
}

# Create ConfigMap YAML
configmap = {
    "apiVersion": "v1",
    "kind": "ConfigMap",
    "metadata": {
        "name": "grafana-airflow-status-dashboard",
        "namespace": "monitoring",
        "labels": {
            "grafana_dashboard": "1"
        }
    },
    "data": {
        "airflow-status-dashboard.json": json.dumps(dashboard, indent=2)
    }
}

# Write to file as YAML with proper indentation
dashboard_json = json.dumps(dashboard, indent=2)
# Indent each line of JSON by 4 spaces for YAML
indented_json = '\n'.join('    ' + line for line in dashboard_json.split('\n'))

yaml_content = f"""apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-airflow-status-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  airflow-status-dashboard.json: |
{indented_json}
"""

with open('k8s/monitoring/grafana-airflow-status-dashboard.yaml', 'w') as f:
    f.write(yaml_content)

print(f"✅ Generated dynamic dashboard with {len(panels)} panel(s)")
print("📊 This dashboard will automatically show all DAGs from the database")
print("📁 File: k8s/monitoring/grafana-airflow-status-dashboard.yaml")
print("")
print("💡 To group by app/naming convention:")
print("   - Modify the SQL query to extract app name from DAG ID")
print("   - Example: SPLIT_PART(dag_id, '_', 1) as app_name")
