# Troubleshoot

In this section you will simulate three common failure scenarios, observe the symptoms in IBM Cloud Logs and IBM Cloud Monitoring, and use `tfectl` to diagnose and recover each one.

Keep the IBM Cloud Logs and IBM Cloud Monitoring tabs you opened in the [Observability](40-observe.md) section open alongside this page.

---

## Scenario 1 — Every run fails immediately (OOM on the run container)

Terraform Enterprise spawns a short-lived Kubernetes Job for each plan or apply. The `TFE_CAPACITY_MEMORY` setting controls how much memory (in MiB) that Job's container is allowed. At the default of `2048` MiB a run has plenty of headroom; set it to `1` MiB and every run container is OOMKilled the moment it starts — while Terraform Enterprise itself stays perfectly healthy.

### Simulate the failure

1. Open `overrides.yaml` and make two changes under `env.variables`:
   - Set `TFE_CAPACITY_MEMORY` to `"1"` to force every run container to OOMKill
   - Set `TFE_RUN_PIPELINE_KUBERNETES_DEBUG_ENABLED` to `"true"` so Kubernetes keeps failed Job pods around long enough to inspect
   ```sh
   nano overrides.yaml
   ```
   ```yaml
   env:
     variables:
       TFE_CAPACITY_MEMORY: "1"
       TFE_RUN_PIPELINE_KUBERNETES_DEBUG_ENABLED: "true"
   ```
   Save the file.

1. Apply the change — this restarts the Terraform Enterprise pod with the new configuration:
   ```sh
   helm upgrade terraform-enterprise hashicorp/terraform-enterprise \
     --version <CURRENT_CHART_VERSION> \
     --namespace <your-username> \
     -f overrides.yaml \
     --wait
   ```

1. Trigger a new Terraform plan from the user interface

   ![](images/70-new-plan.png ':size=600')

   The run moves to **Planning** but stalls and will eventually fail — the run container cannot load the Terraform binary into a 1 MiB memory limit.

### Diagnose

1. Confirm Terraform Enterprise itself is healthy — the application pod has nothing wrong:
   ```sh
   oc exec deployment/terraform-enterprise -- tfectl app health readiness
   ```
   All subsystems show `OK`. The problem is not inside the TFE pod.

1. In Cloud Shell, list pods in your agents namespace — because `TFE_RUN_PIPELINE_KUBERNETES_DEBUG_ENABLED` is set, the failed Job pod is not immediately deleted:
   ```sh
   oc get pods n <your-username>-agents
   ```
   You will see a pod like `tfe-task-xxxxxxxx` in `CreateContainerError` status.

1. Describe the failed pod to find the failure reason:
   ```sh
   oc describe pod <tfe-task-pod-name> -n <your-username>-agents
   ```
   Look for the `Events` section
   ```
   Reason: Failed
    Error: container create failed: clone: Cannot allocate memory
   ```

### Recover

1. Open `overrides.yaml` and restore `TFE_CAPACITY_MEMORY` to its original value:
   ```sh
   nano overrides.yaml
   ```
   ```yaml
   env:
     variables:
       TFE_CAPACITY_MEMORY: "512"
   ```

1. Apply the fix:
   ```sh
   helm upgrade terraform-enterprise hashicorp/terraform-enterprise \
     --version <CURRENT_CHART_VERSION> \
     --namespace <your-username> \
     -f overrides.yaml \
     --wait
   ```

1. Trigger a new plan to confirm runs succeed again.

?> **What to remember:** when runs fail instantly and `tfectl` shows all green, the problem is in the run container, not the application. `oc describe pod <run-pod>` is a fast path to the root cause.

## Scenario 2 — Application errors when Redis is unavailable

Terraform Enterprise depends on external services: PostgreSQL, Redis, and object storage. When one of them goes away, the application is still running but can't do its job. In this lab Redis runs in your namespace as the `tfe-redis` deployment, so you can simulate an outage by scaling it down to zero.

### Simulate the failure

1. Scale the Redis deployment down to zero pods:
   ```sh
   oc scale deployment/tfe-redis --replicas=0
   ```

1. Check that the Redis pod is gone:
   ```sh
   oc get pods
   ```
   Only the `terraform-enterprise` pod remains.

1. Go back to the Terraform Enterprise tab in your browser and refresh the page. Refreshing the UI may lead to some errors: the page can fail to load or show an error page.

### Diagnose

1. In IBM Cloud Logs, check the Terraform Enterprise dashboard for readiness failures and the logs for ERROR:
   ```
   ERROR
   ```
   You will see repeated errors about failing to reach Redis.

   ![](images/70-readiness-failures.png ':size=600')

1. From Cloud Shell, run health readiness to see which subsystem failed:
   ```sh
   oc exec deploy/terraform-enterprise -- tfectl app health readiness
   ```
   The `Status` is no longer `OK`, and `redis` is reported as failing. Other subsystems that depend on Redis may fail with it:
   ```
   Node: terraform-enterprise-xxxxxxxxx-xxxxx
   Status: ERROR

   Checks:
   archivist    ERROR
   atlas        OK
   database     OK
   redis        ERROR
   task-worker  OK
   vault        OK
   ```

1. Run full diagnostics for more detail:
   ```sh
   oc exec deploy/terraform-enterprise -- tfectl app diagnostics
   ```
   The `redis` subsystem shows `✗` with a timeout error.

### Recover

1. Scale the Redis deployment back up:
   ```sh
   oc scale deployment/tfe-redis --replicas=1
   ```

1. Wait for the Redis pod to be `Running`:
   ```sh
   oc get pods --watch
   ```
   Press **Ctrl-C** once it is.

1. Confirm health is restored:
   ```sh
   oc exec deploy/terraform-enterprise -- tfectl app health readiness
   ```
   All subsystems should show `OK` again. If they don't, wait a minute and run the command again — Terraform Enterprise needs a moment to reconnect.

?> **What to remember:** when the UI goes dark, run `tfectl app health readiness` first. It tells you which dependency is failing, check your logs and metrics for errors.

---

?> **Checkpoint** — You've diagnosed and recovered failure scenarios: a capacity problem (no agents), a dependency outage (Redis down). You used `tfectl`, `oc`, IBM Cloud Logs, and IBM Cloud Monitoring together to pinpoint each problem.

⇨ [Continue to Conclusion](90-conclusion.md)
