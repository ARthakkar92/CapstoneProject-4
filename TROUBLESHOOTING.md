# Troubleshooting — Kubernetes & Application Issues

Real problems encountered while deploying and running the application on Kubernetes, and how each was diagnosed and fixed.

---

## nginx path-prefix asset 404s (frontend and admin)

**Symptom**: Frontend loaded a blank page; browser console showed 404s on `/akplacesolution/static/js/main.js` etc.

**Cause**: `PUBLIC_URL` baked a path prefix into the built React app's asset references, but nginx's `root`-based config served files from the actual filesystem root, not the prefixed path — a mismatch between where the browser requested files and where nginx looked for them.

**Fix**: Rebuilt the frontend with a root-relative path (no prefix). For admin specifically, an additional bug surfaced: the Dockerfile appended `-admin` to an *empty* `USER_NAME`, producing `/-admin` instead of `/admin`. Fixed by rebuilding with `USER_NAME=admin` and using nginx's `alias` directive (not `root`) under a dedicated `location /admin/` block, so the prefix is correctly stripped from the filesystem lookup.

---

## Docker network isolation (`backend-service` DNS failure)

**Symptom**: Frontend/admin nginx containers crashed on startup: `host not found in upstream "backend-service"`.

**Cause**: The nginx configs (designed for Kubernetes, where Service DNS names resolve automatically) were being tested via plain `docker run`, where no such DNS entry exists outside a Kubernetes cluster.

**Fix**: For local Docker testing, added a network alias (`docker network connect --alias backend-service ...`) to the backend container so nginx's `proxy_pass` target resolved correctly. No changes were needed once actually deployed to Kubernetes — the Service object provides this DNS entry natively there.

---

## Cross-namespace Ingress backend reference

**Symptom**: `services "prometheus-grafana" not found` in Ingress events, despite the service existing and running correctly.

**Cause**: Kubernetes Ingress can only reference Services in the same namespace as the Ingress itself. The application Ingress (in the `shopnow` namespace) was mistakenly trying to reference Grafana's service, which lives in the `monitoring` namespace.

**Fix**: Created a separate, dedicated Ingress for Grafana inside the `monitoring` namespace, resulting in two independent Application Load Balancers — one for the app, one for monitoring.

---

## ALB controller missing `SetRulePriorities` permission

**Symptom**: Ingress updates failed to reconcile, with repeated `FailedDeployModel` events: `AccessDenied ... elasticloadbalancing:SetRulePriorities`.

**Cause**: The IAM policy attached to the AWS Load Balancer Controller's service account was slightly out of date and missing a permission required for managing multiple routing rules on one ALB.

**Fix**: Updated the controller's IAM policy to the latest official version published in the `aws-load-balancer-controller` project, which included the missing action.

---

## Alert never firing despite a genuinely broken pod

**Symptom**: Manually breaking the backend's image tag (to simulate an outage) never triggered the `DeploymentReplicasUnavailable` alert, even after waiting well past the alert's threshold window.

**Cause**: Kubernetes' rolling update strategy kept the *old*, healthy pod running alongside the new, broken one until the new one became ready — so the number of available replicas never actually dropped below the desired count. A second attempt (scaling the deployment to 0 replicas) also failed to trigger the alert, because Kubernetes reduces both "available" and "desired" replica counts to 0 together, so the "available < desired" condition was still never true.

**Fix**: Directly scaled the *old* ReplicaSet to 0 (bypassing the Deployment controller's normal self-healing behavior), which forced genuine unavailability while the desired replica count stayed at 1 — correctly triggering the alert.

---





