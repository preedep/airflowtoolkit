# Troubleshooting Guide

## Issues Fixed During Deployment

### 1. StatsD Exporter Configuration Error

**Problem**: StatsD Exporter pod was crashing with error:
```
error loading config: invalid match: airflow.*.*.*.operator_successes_*
```

**Root Cause**: The StatsD mapping configuration used invalid glob patterns. The `*` wildcard in patterns like `airflow.*.*.*.operator_successes_*` is not valid in StatsD exporter mapping syntax.

**Solution**: Updated `k8s/monitoring/statsd-mapping-config.yaml` to use simpler, valid patterns:
- Removed complex multi-wildcard patterns
- Used simple single-wildcard patterns like `airflow.pool.open_slots.*`
- Removed quotes from match patterns (quotes are not needed)

**Files Modified**:
- `k8s/monitoring/statsd-mapping-config.yaml`

### 2. Airflow 3.x Architecture Changes

**Problem**: Airflow 3.x no longer has a separate `webserver` component. The deployment was looking for a webserver pod that doesn't exist.

**Root Cause**: Airflow 3.x consolidated the webserver into the `api-server` component. The Helm chart structure changed significantly.

**Solution**: 
- Created a separate NodePort service (`api-server-nodeport.yaml`) to expose the API server
- Updated deployment script to wait for `api-server` component instead of `webserver`
- Updated Helm chart version from 1.15.0 to 1.18.0 (Airflow 3.0.2)

**Files Created**:
- `k8s/airflow/api-server-nodeport.yaml`

**Files Modified**:
- `deploy.sh`
- `k8s/airflow/values.yaml` (updated Airflow version to 3.0.2)

### 3. Triggerer OOMKilled

**Observation**: The triggerer pod was killed due to out-of-memory error and restarted.

**Current Status**: Pod restarted successfully and is now running. The default resource limits in values.yaml may need adjustment for production workloads.

**Recommendation**: Monitor the triggerer pod memory usage and increase limits if needed:
```yaml
triggerer:
  resources:
    limits:
      memory: "1Gi"  # Increase from 512Mi if needed
```

## Common Issues

### Pods Not Starting

**Check pod status**:
```bash
kubectl get pods -n <namespace>
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
```

### Database Connection Issues

**Verify PostgreSQL is running**:
```bash
kubectl get pods -n database
kubectl logs -n database -l app=postgresql
```

**Test connection from Airflow pod**:
```bash
kubectl exec -it <airflow-pod> -n airflow -- \
  nc -zv postgresql.database.svc.cluster.local 5432
```

### Metrics Not Showing in Grafana

1. **Check Prometheus targets**: http://localhost:30090/targets
2. **Verify StatsD Exporter is running**:
   ```bash
   kubectl get pods -n monitoring -l app=statsd-exporter
   kubectl logs -n monitoring -l app=statsd-exporter
   ```
3. **Check Airflow is sending metrics**:
   ```bash
   kubectl logs -n airflow -l component=scheduler | grep -i statsd
   ```

### NodePort Not Accessible

**Verify services**:
```bash
kubectl get svc -A | grep NodePort
```

**For Docker Desktop**, ensure Kubernetes is enabled and ports are not blocked by firewall.

**Alternative - Port Forward**:
```bash
# Airflow UI
kubectl port-forward -n airflow svc/airflow-api-server 8080:8080

# Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090
```

### Persistent Volume Issues

**Check PVC status**:
```bash
kubectl get pvc -A
```

**For Docker Desktop**, the default `hostpath` storage class should work automatically.

## Verification Steps

### 1. Check All Pods Are Running

```bash
kubectl get pods -A
```

Expected output: All pods should be in `Running` or `Completed` status.

### 2. Verify Services

```bash
kubectl get svc -A
```

Expected NodePort services:
- `airflow-api-server-nodeport`: 30080
- `grafana`: 30030
- `prometheus`: 30090

### 3. Test Airflow UI

Open browser: http://localhost:30080
- Username: `admin`
- Password: `admin`

### 4. Test Grafana

Open browser: http://localhost:30030
- Username: `admin`
- Password: `admin`
- Navigate to Dashboards → Airflow Metrics Dashboard

### 5. Test Prometheus

Open browser: http://localhost:30090
- Check Targets: http://localhost:30090/targets
- Query metrics: `airflow_scheduler_heartbeat`

## Logs Collection

**Collect all logs for debugging**:
```bash
# Airflow logs
kubectl logs -n airflow -l component=scheduler --tail=100 > scheduler.log
kubectl logs -n airflow -l component=api-server --tail=100 > api-server.log
kubectl logs -n airflow -l component=dag-processor --tail=100 > dag-processor.log

# Database logs
kubectl logs -n database -l app=postgresql --tail=100 > postgresql.log

# Monitoring logs
kubectl logs -n monitoring -l app=prometheus --tail=100 > prometheus.log
kubectl logs -n monitoring -l app=grafana --tail=100 > grafana.log
kubectl logs -n monitoring -l app=statsd-exporter --tail=100 > statsd-exporter.log
```

## Reset and Redeploy

If you need to start fresh:

```bash
# Clean everything
./cleanup.sh

# Wait for all resources to be deleted
kubectl get pods -A

# Redeploy
./deploy.sh
```

## Performance Tuning

### Resource Limits

Adjust in `k8s/airflow/values.yaml`:

```yaml
scheduler:
  resources:
    limits:
      memory: "2Gi"  # Increase for large DAG counts
      cpu: "2000m"

triggerer:
  resources:
    limits:
      memory: "1Gi"  # Increase if OOMKilled
```

### Database Performance

For production, consider:
- Using external managed PostgreSQL
- Increasing PostgreSQL resources
- Enabling connection pooling

### DAG Processing

Monitor DAG parsing time in Grafana. If slow:
- Reduce DAG complexity
- Increase dag-processor resources
- Use `.airflowignore` to skip unnecessary files

## Getting Help

**View Airflow logs**:
```bash
kubectl logs -n airflow -l component=scheduler -f
```

**Check Airflow configuration**:
```bash
kubectl exec -it -n airflow <scheduler-pod> -- airflow config list
```

**Database migrations status**:
```bash
kubectl logs -n airflow -l component=run-airflow-migrations
```
