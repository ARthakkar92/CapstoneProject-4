# Testing — ShopNow DevOps Pipeline

This document covers manual test cases used to validate infrastructure, the CI/CD pipeline, the deployed application, and monitoring/alerting. Each test includes the command(s) to run and the expected result.

---

## 1. Infrastructure tests

### 1.1 Terraform state integrity

```bash
cd terraform
terraform plan
```
**Expected**: `No changes. Your infrastructure matches the configuration.` A plan showing unexpected destroy/replace actions indicates configuration drift — do not apply without reviewing.

### 1.2 EKS cluster and nodes healthy

```bash
kubectl get nodes
```
**Expected**: 2 nodes, both `STATUS: Ready`.

### 1.3 Jenkins server reachable and running

```bash
curl -I http://<jenkins_public_ip>:8080/login
sudo systemctl status jenkins
```
**Expected**: HTTP `200` or `403` response; `systemctl status` shows `active (running)`.

---

## 2. CI/CD pipeline tests

### 2.1 Webhook triggers a build automatically

```bash
git commit --allow-empty -m "Test webhook trigger"
git push origin main
```
**Expected**: A new Jenkins build starts within a few seconds without manual intervention (visible on the Jenkins job page, "Started by GitHub push").

### 2.2 Pipeline completes all stages successfully

Check the Jenkins console output for the triggered build.
**Expected**: `Finished: SUCCESS`, with all stages (Checkout, Verify Tools, Build × 3, Push to ECR, Deploy to EKS, Verify Deployment) shown green.

### 2.3 Images actually updated in ECR

```bash
aws ecr describe-images --repository-name <name>-shopnow/backend --region <region> --query "imageDetails[0].imagePushedAt"
```
**Expected**: A timestamp matching the most recent pipeline run.

### 2.4 Deployment picks up the new image

```bash
kubectl rollout status deployment backend -n shopnow
kubectl describe deployment backend -n shopnow | grep Image
```
**Expected**: Rollout completes without timeout; image tag matches what was just pushed.

---

## 3. Application functionality tests

### 3.1 Backend health check

```bash
curl http://<ingress_address>/api/health
```
**Expected**: `{"status":"OK","message":"ShopNow API is running"}`

### 3.2 Product listing returns data

```bash
curl http://<ingress_address>/api/products
```
**Expected**: JSON array with 6 seeded products (or more, if added since).

### 3.3 Frontend loads and renders products

Open `http://<ingress_address>/` in a browser.
**Expected**: Page loads fully (no blank screen), navbar and hero section render, product grid shows items with images and prices, browser console has no 404 errors on `/static/*` assets.

### 3.4 Admin dashboard loads

Open `http://<ingress_address>/admin/` in a browser.
**Expected**: Admin UI renders correctly, no console errors, assets load from `/admin/static/*`.

### 3.5 Database connectivity

```bash
kubectl logs -n shopnow deployment/backend | grep -i mongo
```
**Expected**: A log line confirming successful MongoDB connection, no repeated connection retry/error messages.

---

## 4. Kubernetes deployment integrity tests

### 4.1 All pods running and ready

```bash
kubectl get pods -n shopnow
```
**Expected**: 4 pods (`admin`, `backend`, `frontend`, `mongo`), all `1/1 Ready`, `STATUS: Running`, `RESTARTS: 0` (or low, if intentionally tested).

### 4.2 Services correctly route to pods

```bash
kubectl get endpoints -n shopnow
```
**Expected**: Each service (`backend-service`, `frontend-service`, `admin-service`, `mongo`) shows a non-empty endpoint IP:port matching a running pod.

### 4.3 Ingress routes correctly by path

```bash
curl -I http://<ingress_address>/          # → frontend
curl -I http://<ingress_address>/admin/    # → admin
curl http://<ingress_address>/api/health   # → backend
```
**Expected**: Each path returns a response from the correct service (verify via response headers/content, not just status code — a misrouted path can still return `200` from the wrong service).

### 4.4 Auto-scaling responds to load

```bash
kubectl get hpa -n shopnow
```
**Expected**: `TARGETS` shows a real percentage (not `<unknown>`), confirming metrics-server is feeding live data to the HPA. To test actual scale-up, generate sustained load against the backend and watch `REPLICAS` increase toward `MAXPODS`.

---

## 5. Monitoring and alerting tests

### 5.1 Prometheus is scraping all expected targets

```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 &
curl -s http://localhost:9090/api/v1/targets | grep -o '"health":"[a-z]*"' | sort | uniq -c
```
**Expected**: Majority `"health":"up"`; check specifically that the `jenkins` job shows `up`.

### 5.2 Grafana dashboards render live data

Open Grafana → Dashboards → "ShopNow Application Monitoring".
**Expected**: All panels show real values (pod counts, CPU/memory graphs with data points), not "No data" or "N/A" across the board.

### 5.3 Alert fires and email is delivered (full lifecycle test)

```bash
# Break the backend deployment
kubectl set image deployment/backend backend=<ecr_registry>/<repo>/backend:nonexistent-tag -n shopnow

# Force the old ReplicaSet to scale down so the outage is real
kubectl get rs -n shopnow -l app=backend   # find the old, healthy RS name
kubectl scale rs <old-rs-name> -n shopnow --replicas=0

# Wait ~2 minutes, then check
kubectl get pods -n shopnow -l app=backend
```
**Expected**: An email arrives at the configured address with subject/content referencing `DeploymentReplicasUnavailable`, `deployment: backend`.

```bash
# Restore
kubectl set image deployment/backend backend=<ecr_registry>/<repo>/backend:latest -n shopnow
```
**Expected**: A second "RESOLVED" email arrives within a few minutes once the pod is healthy again.

### 5.4 Jenkins build-failure alert (optional)

Push a commit that intentionally breaks a pipeline stage (e.g. a syntax error in the Jenkinsfile), observe the build fail, and confirm the `JenkinsBuildFailed` alert fires and an email is sent. Revert the change afterward.

---

## Test results log

| Test | Date | Result | Notes |
|---|---|---|---|
| 1.1 Terraform state integrity |2026-08-16 |PASS |terraform plan shows no unexpected changes |
| 2.1 Webhook trigger |2026-08-16 |Pass |Build auto-triggered on push, confirmed in Jenkins console log |
| 2.2 Pipeline success |2026-08-16 |Pass |All stages green, Finished: SUCCESS |
| 3.3 Frontend renders |2026-08-16 |Pass |Homepage loads with 6 products, no console errors |
| 3.4 Admin renders |2026-08-16 |Pass |	Dashboard loads correctly at /admin/, no console errors |
| 4.1 Pods healthy |2026-08-16 |Pass |	4/4 pods 1/1 Running |
| 4.4 HPA responds |2026-08-16 |Pass |	kubectl get hpa shows real CPU percentage |
| 5.3 Alert lifecycle |2026-08-16 |Pass |	DeploymentReplicasUnavailable fired and resolved, both emails received |

*(Fill in dates/results when running through this checklist for final submission.)*
