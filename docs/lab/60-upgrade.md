# Upgrade to latest version

Upgrading Terraform Enterprise is a deliberate, sequenced operation — not a `helm upgrade` you fire and forget. In this section you follow the recommended upgrade workflow: review the release notes, run the pre-upgrade check to catch problems before they cause downtime, drain the node, and then apply the upgrade.

You are upgrading from **2.0.5** (the version you deployed) to **2.1.0**.

## Planning checklist

HashiCorp publishes a [planning checklist](https://developer.hashicorp.com/terraform/enterprise/deploy/manage/upgrade) to follow for every environment, from test through production, and for each intermediate release you need to apply:

- [ ] Select a target version and confirm its compatibility with your environments
- [ ] Identify pre-requisite intermediate releases
- [ ] Schedule maintenance window
- [ ] Capture configuration
- [ ] Backup PostgreSQL, Redis, and object storage
- [ ] Download the container images for each intermediate release
- [ ] Run the pre-upgrade checks for your runtime and resolve any failures or warnings
- [ ] Define rollback criteria and rehearse the rollback procedure
- [ ] Upgrade Terraform Enterprise
- [ ] Notify stakeholders

HashiCorp also recommends running the upgrade sequence in a test environment first.

In this lab you follow the parts of the checklist that fit a short session: you select the target version, run the pre-upgrade check, and upgrade. A production upgrade needs every item, including the maintenance window, the backups, and a rehearsed rollback.

## Review the release notes

Before any upgrade, read the release notes for every version between your current release and the target. This is where breaking changes, deprecated configuration keys, and required intermediate releases are documented.

1. Open the [Terraform Enterprise releases page](https://developer.hashicorp.com/terraform/enterprise/releases).
1. Find the **2.1.0** entry and open its release notes.
1. Look for any **Breaking changes** section. Note any configuration variables that have been renamed or removed — you'll need to update `overrides.yaml` before the upgrade.

   !> **2.1.0 contains a breaking change.** Read the release notes carefully before proceeding. The pre-upgrade check in the next section will also surface this — but knowing about it in advance lets you prepare the fix before you start the maintenance window.

1. Also confirm the **Last required release** marker. If any intermediate version is listed as required, you must upgrade through it first. For this lab, a direct upgrade from `2.0.5` to `2.1.0` is supported.

## Check your Cloud Shell session

The lab takes time, so your Cloud Shell session may have expired. Check that you still have your working environment before continuing.

1. In Cloud Shell, make sure you're in the lab repository directory:
   ```sh
   cd txc2026-lab-2963
   ```
   If this works, your session is still good. Skip to the next section.

1. Otherwise, open a new Cloud Shell window
1. [Log in to the OpenShift cluster](20-deploy.md#log-in-to-the-openshift-cluster) again.
1. Clone the repository and regenerate `overrides.yaml`:
   ```sh
   git clone https://github.com/hashicorp/txc2026-lab-2963
   cd txc2026-lab-2963
   ./prepare-helm.sh
   ```
   Ignore the "Next steps" printed at the end of the script output. Terraform Enterprise is already installed, so you don't run the install command again.
1. Add the Helm repository:
   ```sh
   helm repo add hashicorp https://helm.releases.hashicorp.com
   ```

## Run the pre-upgrade check

The pre-upgrade check runs the Terraform Enterprise `2.1.0` container with a special entrypoint that validates your configuration and connectivity without modifying anything. It exits with a non-zero code if the upgrade would fail, so you can fix problems now rather than during a live upgrade.

This is a Helm-based workflow that runs a temporary Kubernetes Job in your existing namespace.

1. Update the Helm repository to pick up the chart version for `2.1.0`:
   ```sh
   helm repo update
   ```

1. Find the chart version whose `APP VERSION` is `2.1.0`:
   ```sh
   helm search repo hashicorp/terraform-enterprise --versions | grep 2.1.0
   ```
   Note the value in the **CHART VERSION** column — you'll use it as `<TARGET_CHART_VERSION>` below.

1. Render the pre-upgrade check Job manifest using your existing `overrides.yaml`:
   ```sh
   helm template terraform-enterprise hashicorp/terraform-enterprise \
     -n <your-username> \
     --version 2.1.0 \
     -f overrides.yaml \
     --set preupgradeCheck.enabled=true \
     --set preupgradeCheck.tfeNamespace=true \
     --set openshift.enabled=true \
     --set image.tag=2.1.0 \
     --show-only templates/preupgrade-check-job.yaml \
     > preupgrade.yaml
   ```

1. Apply the Job to your namespace:
   ```sh
   oc apply -f preupgrade.yaml
   ```

1. Wait for the Job to complete and review its output:
   ```sh
   oc wait --for=condition=complete \
     job/terraform-enterprise-preupgrade-check \
     --timeout=300s

   oc logs --tail=-1 -l preupgrade-check.hashicorp.com/name=terraform-enterprise-preupgrade-check
   ```

   A passing check looks like:
   ```
   Terraform Enterprise Pre-Upgrade Check
   Current environment version: 2.0.5
   Target version: 2.1.0
   ---
   ✓ archivist
     ✓ write_access

   ✓ cloud
     ✓ cloud-sdk

   ✓ config
     ✓ general

   ✓ database
     ✓ connection
     ✓ extensions
     ✓ user_permissions
     ✓ version

   ✓ license
     ✓ valid_license

   ✓ redis
     ✓ config
     ✓ connection
     ✓ permissions
     ✓ version

   ✓ tls
     ✓ ca_bundle

   ✓ upgrade
     ✓ validation

   Status: OK | Time: 1.7s | Checks: 14 Passed, 0 Warning, 0 Failed

   Pre-upgrade checks indicate this environment is ready to upgrade to 2.1.0
   ```

   !> If the output shows a **breaking change warning** for `2.1.0`, read the warning message carefully. It will tell you exactly which configuration key needs to change. Update `overrides.yaml` accordingly before continuing.

1. Clean up the Job:
   ```sh
   oc delete job/terraform-enterprise-preupgrade-check --ignore-not-found
   rm preupgrade.yaml
   ```

## Drain the node

Before applying the upgrade you need to stop Terraform Enterprise from picking up new work. The `tfectl node drain` command lets active runs finish and then blocks new ones from starting — this is safer than hard-stopping the pod mid-run.

1. Get the name of the Terraform Enterprise pod:
   ```sh
   oc get pods
   ```

1. Drain the node:
   ```sh
   oc exec <pod-name> -- tfectl node drain
   ```

   You should see:
   ```
   Starting node drain activity. This process runs in the background. Please monitor its progress before proceeding with a complete application shutdown.
   Node drain completed successfully: Triggering sidekiq stop
   Using ProcessManager to stop sidekiq
   Stopping sidekiq-run wrapper (PID: 247)
   Sidekiq is not running.
   Sidekiq has been stopped.
   Stopping task worker.
   Terminate signal sent to task worker, it will now begin graceful shutdown
   ```

   ?> Since you just deployed a fresh installation there are no active runs, so the drain completes immediately. In production this step gives long-running plans time to finish gracefully.

## Apply the upgrade

With the node drained and the pre-upgrade check passing, update `overrides.yaml` to the target image tag and run `helm upgrade`.

1. Open `overrides.yaml` and update the image tag:
   ```sh
   nano overrides.yaml
   ```
   Find the `image` section and change the tag to `2.1.0`:
   ```yaml
   image:
     repository: images.releases.hashicorp.com/hashicorp
     name: terraform-enterprise
     tag: "2.1.0"
     pullPolicy: IfNotPresent
   ```
   If the pre-upgrade check flagged a breaking change that requires a configuration key rename, make that edit here too.

1. Apply the upgrade:
   ```sh
   helm upgrade terraform-enterprise hashicorp/terraform-enterprise \
     --version <TARGET_CHART_VERSION> \
     --namespace <your-username> \
     -f overrides.yaml \
     --wait
   ```
   Helm streams events as the new pod starts. The `--wait` flag blocks until the rollout completes. Database migrations run automatically during startup and may take a few minutes to complete.

1. Watch the rollout:
   ```sh
   oc rollout status deployment/terraform-enterprise
   ```
   When it completes you will see:
   ```
   deployment "terraform-enterprise" successfully rolled out
   ```

## Validate the upgrade

1. Check that the pod is running the new version:
   ```sh
   oc exec deployment/terraform-enterprise -- tfectl app health readiness
   ```
   All subsystems should show `OK`.

1. Confirm the running version:
   ```sh
   oc exec deployment/terraform-enterprise -- tfectl app version
   ```

2. Open the application:
   ```
   https://tfe.<your-username>.example.com
   ```
   The footer shows the running version — confirm it reads `2.1.0`.

3. Run a quick smoke test — trigger a `terraform plan` from Cloud Shell and confirm the run completes successfully in the Terraform Enterprise web UI.

?> **Checkpoint** — Terraform Enterprise is now running `2.1.0`. You reviewed the release notes, caught the breaking change with the pre-upgrade check before it caused an outage, drained the node safely, and validated the upgraded installation. In the next section you'll work through some troubleshooting scenarios.

⇨ [Continue to Troubleshooting](70-troubleshoot.md)
