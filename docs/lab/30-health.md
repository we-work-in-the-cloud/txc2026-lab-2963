# Check health

Terraform Enterprise is deployed — now make sure it's actually healthy before you start using it. In this section you will check readiness and diagnostics from the CLI and explore the admin console.

## Check application readiness

Terraform Enterprise ships with `tfectl`, a CLI built into the pod that lets you inspect the application without going through the API. You run it by `exec`-ing into the pod with `oc`.

The pod name is generated (`terraform-enterprise-xxxxxxxxx-xxxxx`), so you don't have to look it up. Pointing `oc exec` at the `terraform-enterprise` deployment (`deploy/terraform-enterprise`) runs the command in one of its pods.

1. Check that Terraform Enterprise is ready to accept requests:
   ```sh
   oc exec deploy/terraform-enterprise -- tfectl app health readiness
   ```
   A healthy response looks like:
   ```
   Node: terraform-enterprise-6ffb9fdf4f-ls6tx
   Status: OK

   Checks:
   archivist    OK
   atlas        OK
   database     OK
   redis        OK
   task-worker  OK
   vault        OK
   ```
   ?> If `Status` is not `OK` yet, don't wait here. The application can take a few minutes to fully initialise after the pod becomes `Running`. Carry on with the next sections — you will confirm readiness again at the end of this page.

## Run diagnostics

The `tfectl app diagnostics` command performs a deeper check — it probes every Terraform Enterprise subsystem (database, Redis, blob storage, licensing) and reports any warnings or errors.

1. Run diagnostics against the pod:
   ```sh
   oc exec deploy/terraform-enterprise -- tfectl app diagnostics
   ```
   You will see each subsystem listed with a `✓`, `⚠`, or `✗` symbol, followed by a summary line. Everything should show `✓`:
   ```
   ---
   ✓ archivist
     ✓ write_access

   ✓ atlas
     ✓ health_status

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

   ✓ task-worker
     ✓ drivers
     ✓ external_services
     ✓ health_status

   ✓ tls
     ✓ ca_bundle

   ✓ vault
     ✓ health_status

   Status: OK | Time: 0.7s | Checks: 18 Passed, 0 Warning, 0 Failed
   ```

   ?> If any subsystem shows a warning, note it down — it won't block the lab but is useful context for the later Troubleshoot section.

## Generate a System API token

The Terraform Enterprise admin console requires a System API token to authenticate. Generate one directly from the pod.

1. Generate the token:
   ```sh
   oc exec deploy/terraform-enterprise -- tfectl admin api-token generate --description "lab-admin"
   ```
   The command prints the token value. **Copy it now** — you won't be able to retrieve it again.

## Access the admin console

The admin console is a web UI where you can monitor your Terraform Enterprise installation.

1. List the routes exposed by the cluster:
   ```sh
   oc get routes
   ```
   You will see more than one route. Find the one whose **PORT** column is `admin-https-port` — its **HOST/PORT** value is the admin console address.
1. Open that host in your browser, with `https://` in front of it. It looks like:
   ```
   https://<your-username>-admin.tfe-123456.example.com
   ```
1. Enter the System API token you generated above when prompted.
   ![](images/30-admin-console-login.png ':size=800')
1. Explore the **Dashboard** — it shows the running version, operational mode, and the health status of all subsystems you just checked from the CLI.
   ![](images/30-admin-console-dashboard.png ':size=800')
1. Expand **Node readiness** and _Run diagnostics on all nodes_ to perform similar actions as you did in the CLI.

## Confirm readiness

If the admin console dashboard shows everything green, Terraform Enterprise is ready and you can skip to the checkpoint. Follow the steps below only if something is not green, or if you are curious to see the CLI confirm it.

1. Run the readiness check again:
   ```sh
   oc exec deploy/terraform-enterprise -- tfectl app health readiness
   ```
   `Status` should be `OK` and every check in the list should show `OK`, like the output you saw at the start of this page.
1. If `Status` is still not `OK`, check whether the application has finished starting. Terraform Enterprise logs a lot, so search the full log for the ready message instead of scrolling through it:
   ```sh
   oc logs deploy/terraform-enterprise | grep Happy
   ```
   A started application prints:
   ```
   TFE is now ready to use. Happy Terraforming!
   ```
1. If nothing is printed, the application is still starting or hit a problem. Search the log for errors:
   ```sh
   oc logs deploy/terraform-enterprise | grep -i error
   ```
   Wait a minute and run the readiness check again.

?> **Checkpoint** — Terraform Enterprise is healthy and the admin console is accessible. In the next section you will set up observability.

⇨ [Continue to Observability](40-observe.md)
