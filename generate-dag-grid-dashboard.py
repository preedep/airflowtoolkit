#!/usr/bin/env python3
"""
Generate Grafana dashboard with DAG status grid layout
"""
import json
import subprocess

# Get list of DAGs from database
result = subprocess.run([
    'kubectl', 'exec', '-n', 'database',
    subprocess.run(['kubectl', 'get', 'pod', '-n', 'database', '-l', 'app=postgresql', 
                   '-o', 'jsonpath={.items[0].metadata.name}'], 
                   capture_output=True, text=True).stdout.strip(),
    '--', 'psql', '-U', 'airflow', '-d', 'airflow', '-t', '-A', '-c',
    "SELECT dag_id FROM dag WHERE bundle_name IS NOT NULL ORDER BY dag_id;"
], capture_output=True, text=True)

dag_ids = [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]

print(f"Found {len(dag_ids)} DAGs")

# Grid configuration
COLS = 20  # Number of columns in grid (more compact)
PANEL_WIDTH = 1.2  # Width of each panel (24 / 20 = 1.2)
PANEL_HEIGHT = 2  # Height of each panel (smaller)

panels = []
panel_id = 1

for idx, dag_id in enumerate(dag_ids):
    row = idx // COLS
    col = idx % COLS
    
    x_pos = col * PANEL_WIDTH
    y_pos = row * PANEL_HEIGHT
    
    # Truncate DAG name for display (shorter for compact view)
    display_name = dag_id[:10] if len(dag_id) > 10 else dag_id
    
    panel = {
        "datasource": "Airflow PostgreSQL",
        "fieldConfig": {
            "defaults": {
                "color": {
                    "mode": "thresholds"
                },
                "mappings": [
                    {
                        "options": {
                            "0": {
                                "color": "light-gray",
                                "index": 0,
                                "text": display_name
                            },
                            "1": {
                                "color": "dark-gray",
                                "index": 1,
                                "text": display_name
                            },
                            "2": {
                                "color": "green",
                                "index": 2,
                                "text": display_name
                            },
                            "3": {
                                "color": "red",
                                "index": 3,
                                "text": display_name
                            },
                            "4": {
                                "color": "blue",
                                "index": 4,
                                "text": display_name
                            },
                            "5": {
                                "color": "yellow",
                                "index": 5,
                                "text": display_name
                            }
                        },
                        "type": "value"
                    }
                ],
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {
                            "color": "gray",
                            "value": None
                        }
                    ]
                },
                "unit": "none"
            },
            "overrides": []
        },
        "gridPos": {
            "h": PANEL_HEIGHT,
            "w": PANEL_WIDTH,
            "x": x_pos,
            "y": y_pos
        },
        "id": panel_id,
        "options": {
            "colorMode": "background",
            "graphMode": "none",
            "justifyMode": "center",
            "orientation": "auto",
            "reduceOptions": {
                "values": False,
                "calcs": ["lastNotNull"],
                "fields": ""
            },
            "textMode": "name"
        },
        "pluginVersion": "9.0.0",
        "targets": [
            {
                "datasource": "Airflow PostgreSQL",
                "format": "table",
                "rawSql": f"""
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
  WHERE d.dag_id = '{dag_id}'
)
SELECT 
  CASE 
    WHEN latest_state = 'running' THEN 2
    WHEN latest_state = 'failed' THEN 3
    WHEN latest_state = 'success' THEN 4
    WHEN is_paused = true THEN 1
    WHEN latest_start IS NOT NULL THEN 5
    ELSE 0
  END as value
FROM dag_status;
                """,
                "refId": "A"
            }
        ],
        "title": "",
        "type": "stat"
    }
    
    panel_id += 1
    panels.append(panel)

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

print(f"Generated dashboard with {len(panels)} panels")
print("File: k8s/monitoring/grafana-airflow-status-dashboard.yaml")
