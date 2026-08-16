# Troubleshooting — Issues Encountered and Resolutions

This document captures real problems hit while building this pipeline, organized by sprint/area. Kept for anyone reproducing this setup, and as evidence of debugging process for review.

---

## Sprint 1 — Jenkins, Docker, ECR

### Jenkins repo GPG key errors (`NO_PUBKEY`)
**Symptom**: `apt-get update` failed with `NO_PUBKEY 7198F4B714ABFC68`, `Package jenkins has no installation candidate`.
**Cause**: Jenkins rotates its signing keys periodically; the documented `jenkins.io-2023.key` was outdated. Additionally, piping the ASCII-armored key directly into a `signed-by` keyring path (rather than dearmoring it) produced an unusable keyring.
**Fix**: Downloaded the current key (`jenkins.io-2026.key`) and used `apt-key add` (simpler, proven reliable in this environment) instead of manual `gpg --dearmor`.

### Jenkins fails to start after install
**Symptom**: `systemctl status jenkins` showed `Failed with result 'exit-code'`, repeatedly restarting.
**Cause**: Jenkins 2.568+ requires Java 21; the instance had Java 17 installed (in the wrong order — Jenkins installed before Java was upgraded).
**Fix**: Installed `openjdk-21-jre` *before* installing Jenkins, and used `update-alternatives` to confirm the active `java` binary was version 21.

### EC2 instance type rejected for Free Tier
**Symptom**: `InvalidParameterCombination: The specified instance type is not eligible for Free Tier` for `t3.medium`.
**Fix**: Switched to `t2.micro` initially, later to `t3.small` (not free-tier, but small ongoing cost accepted for headroom running Jenkins + Docker together).

### nginx path-prefix asset 404s (frontend and admin)
**Symptom**: Frontend loaded a blank page; browser console showed 404s on `/akplacesolution/static/js/main.js` etc.
**Cause**: `PUBLIC_URL` baked a path prefix into the built React app's asset references, but nginx's `root`-based config served files from the actual root path, not the prefixed one — a mismatch between where the browser requested files and where nginx looked for them.
**Fix**: For local Docker testing, rebuilt with an empty prefix (root-relative paths). For admin specifically, an additional bug: the Dockerfile appended `-admin` to an *empty* `USER_NAME`, producing `/-admin` instead of `/admin`. Fixed by rebuilding with `USER_NAME=admin` and using nginx's `alias` directive (not `root`) under a dedicated `location /admin/` block, so the prefix is correctly stripped from the filesystem lookup.

### Docker container network isolation (`backend-service` DNS failure)
**Symptom**: Frontend/admin nginx containers crashed on startup: `host not found in upstream "backend-service"`.
**Cause**: nginx configs (designed for Kubernetes, where Service DNS names resolve automatically) were being tested via plain `docker run`, where no such DNS entry exists.
**Fix**: For local testing, added a network alias (`docker network connect --alias backend-service ...`) to the backend container so nginx's `proxy_pass` target resolved correctly. This was purely a local-testing workaround — no changes were needed once deployed to actual Kubernetes, where the Service object provides this DNS entry natively.

---

## Sprint 2 — Terraform, EKS

### AMI drift forcing accidental instance replacement
**Symptom**: `terraform plan` proposed destroying and recreating the working Jenkins instance, triggered by a `data "aws_ami"` lookup with `most_recent = true` picking up a newer AMI than the one actually running.
**Fix**: Pinned the AMI to a fixed ID instead of a dynamic lookup, eliminating drift on every plan.

### EKS node group stuck in `CREATING`, never joining
**Symptom**: Node group sat in `CREATING` for 15+ minutes with no nodes ever appearing.
**Cause**: `t3.medium` instance type rejected for Free Tier, same root cause as the EC2 issue above — but this time the failure was silent from `kubectl`'s perspective, only visible in `aws autoscaling describe-scaling-activities`.
**Fix**: Switched node group `instance_types` to `t3.small`. **Lesson**: when an EKS node group hangs in `CREATING` with empty `health.issues`, check the underlying Auto Scaling Group's activity log directly — EKS doesn't always surface launch failures at the node group level.

### Interrupted `terraform apply` leaving a tainted resource
**Symptom**: After Ctrl+C during a stuck node group creation, `terraform plan` showed the node group as `tainted` requiring destroy/recreate.
**Fix**: This was expected and correct Terraform behavior — a tainted resource genuinely needs replacement. Applied cleanly once the underlying instance-type issue was fixed.

### EKS authentication mode blocking access entries
**Symptom**: `aws eks create-access-entry` failed: `The cluster's authentication mode must be set to one of [API, API_AND_CONFIG_MAP]`.
**Cause**: Cluster was created with the default `CONFIG_MAP`-only auth mode.
**Fix**: Added `access_config { authentication_mode = "API_AND_CONFIG_MAP" }` to the `aws_eks_cluster` resource. **Caveat**: changing this field alone (without also setting `bootstrap_cluster_creator_admin_permissions` explicitly) caused Terraform to force a full cluster replacement rather than an in-place update on the next apply — setting both fields together the first time avoids this.

### Deleting an EKS cluster with an attached node group
**Symptom**: `ResourceInUseException: Cluster has nodegroups attached` during a forced cluster replacement.
**Fix**: Destroyed the node group first (`terraform destroy -target=aws_eks_node_group.main`), then let the cluster replacement proceed.

### IAM permission gaps discovered incrementally
Jenkins' EC2 IAM role initially had only narrow ECR/EKS permissions. Each new capability added (reading EKS cluster details, S3 state access, EC2/VPC/IAM resource management for `terraform plan`, CloudFormation for `eksctl`) surfaced a new `AccessDenied` error requiring an additional policy attachment. **Lesson**: for a `terraform plan` to succeed, the executing identity needs read access to *every* resource type in the state file, not just the ones it's expected to modify.

---

## Sprint 4 — CI/CD to EKS

### Jenkins building from stale/unsynced source
**Symptom**: Jenkins pipeline built and deployed the *old*, broken version of the admin Dockerfile, even after local fixes.
**Cause**: Manual debugging and fixes were being made in a separate local clone (`~/capstone/shopNow`) that was never connected to the actual Git repo (`CapstoneProject-4`) Jenkins builds from.
**Fix**: Synced all fixed files into the correct repo directory, confirmed via `git status`, then committed and pushed. **Lesson**: when debugging locally across multiple directories, periodically verify which directory is actually the one wired into the CI/CD pipeline.

### Missing Kubernetes manifests in Jenkins' checkout
**Symptom**: `kubectl apply -f k8s/namespace/namespace.yaml`: file not found, despite the file existing on the EC2 instance's disk.
**Cause**: The `k8s/` directory existed locally but was never `git add`ed/pushed — Jenkins' fresh checkout naturally didn't have it.
**Fix**: Committed and pushed the full `k8s/` directory.

### Cross-namespace Ingress backend reference
**Symptom**: `services "prometheus-grafana" not found` in Ingress events, despite the service existing.
**Cause**: Kubernetes Ingress can only reference Services in the same namespace as the Ingress itself — the app Ingress (`shopnow` namespace) tried referencing Grafana's service (`monitoring` namespace).
**Fix**: Created a separate, dedicated Ingress for Grafana in the `monitoring` namespace, resulting in two independent ALBs.

### ALB controller missing `SetRulePriorities` permission
**Symptom**: `FailedDeployModel` events on Ingress updates: `AccessDenied ... elasticloadbalancing:SetRulePriorities`.
**Fix**: Updated the ALB controller's IAM policy to the latest official version from the `aws-load-balancer-controller` repo, which included this and other newer required actions.

---

## Sprint 5 — Monitoring, alerting

### Alertmanager silently ignoring custom SMTP config
**Symptom**: Multiple `helm upgrade` attempts with a custom `alertmanager.config` reported success, but the live Alertmanager pod kept loading the chart's default empty config (`receiver: "null"`, no SMTP settings).
**Root cause (found via Prometheus Operator logs)**: `undefined receiver "null" used in route`. The custom config's `receivers:` list replaced the default list entirely, removing the `null` receiver that the built-in `Watchdog` sub-route depended on — this broke config validation, and the operator silently kept the last-known-good (default) config instead.
**Fix**: Explicitly included a `- name: 'null'` receiver alongside the custom `email-notifications` one, and kept the `Watchdog` sub-route pointing at it.

### A stray leading space breaking a Helm values file
**Symptom**: A second, seemingly-correct SMTP config update still didn't apply.
**Cause**: The values YAML file had a leading space before the top-level `alertmanager:` key (` alertmanager:` instead of `alertmanager:`), which is invalid at that position and caused Helm to misparse/ignore the block.
**Fix**: Recreated the file via a heredoc to guarantee no leading whitespace; verified with `cat -A`.

### Alert never firing despite a genuinely broken pod
**Symptom**: Manually breaking the backend image (`kubectl set image ... :nonexistent-tag`) never triggered the `PodDown`/`DeploymentReplicasUnavailable` alert.
**Cause**: Kubernetes' rolling update strategy kept the *old*, healthy pod running alongside the new broken one until the new one became ready — so `available_replicas` never actually dropped below `desired_replicas`. Later, scaling the deployment to 0 replicas was also tried, but since Kubernetes drops *both* `available` and `desired` to 0 together, the "available < desired" condition was still never true.
**Fix**: Manually scaled the *old* ReplicaSet to 0 directly (`kubectl scale rs <old-rs> --replicas=0`), bypassing the Deployment controller's self-healing and forcing genuine unavailability while `spec.replicas` stayed at 1.

### Deprecated kube-state-metrics field names in imported dashboards
**Symptom**: An imported community Grafana dashboard (ID 6417 / 315) showed "N/A" on most panels.
**Cause**: The dashboard used older, since-renamed kube-state-metrics metric names not present in the current chart version.
**Fix**: Abandoned the broken import in favor of the dashboards bundled directly with the `kube-prometheus-stack` chart (guaranteed version-matched), plus a custom-built dashboard for application-specific and Jenkins metrics.

### Manually-imported dashboards disappearing after pod restarts
**Symptom**: A dashboard imported through Grafana's UI (Jenkins dashboard, ID 9964) vanished after the Grafana pod restarted.
**Cause**: UI-imported dashboards live in Grafana's internal (ephemeral) SQLite database, not persistent storage.
**Fix**: Re-created dashboards as Kubernetes ConfigMaps labeled `grafana_dashboard: "1"`, which Grafana's sidecar container auto-loads and which persist as real cluster resources — surviving restarts and versioned in Git.

---

## General lessons

- **Verify state after every automated step, don't assume success from a clean exit code** — several of the above issues (Helm "upgraded successfully" but config unchanged, Terraform "applied" but wrong resource state) looked successful on the surface.
- **When something "should" work but doesn't, check the layer below the one you're debugging** — e.g. an Ingress routing issue was actually an IAM permission issue; an alert not firing was actually a Kubernetes scheduling behavior, not a Prometheus rule bug.
- **Keep infrastructure and application source in one repo, or be very deliberate about syncing** — the biggest recurring time-sink in this project was debugging against the wrong copy of a file.
