# Plan and apply

In this section you will create the initial admin user, set up your first organization, and run your first Terraform plan and apply through Terraform Enterprise using the CLI-driven workflow.

## Create your user

### Create the initial admin user

Fresh Terraform Enterprise installations have no users. The `initial-user.sh` script in the lab repo automates the process — it retrieves the Initial Admin Creation Token (IACT) from the pod and calls the API to seed the first admin account.

1. From Cloud Shell, run the script:
   ```sh
   ./create-initial-user.sh
   ```
   The script prints the credentials for the new admin user:
   ```
   ✓ Initial admin user created

   Username: <username>>
   Password: <generated-password>
   TFE URL:  https://<your-username>.tfe.example.com
   Token:    12345
             (saved to user.token)
   ```
   ?> Copy the password — you will need it in the next step.

### Log in and create your first organization

1. Open Terraform Enterprise in your browser, using the URL printed by `./create-initial-user.sh` in the previous step. It looks like:
   ```
   https://tfe.<your-username>.example.com
   ```

   !> Don't copy the example above. Use the URL from your script output.

2. Log in with the credentials printed by the script.
   ![](images/50-tfe-login.png ':size=400')
   You land on the **Create organization** page

## Create an organization

An organization is the top-level container in Terraform Enterprise. It groups the projects and workspaces that a team works on, and it is where you manage who can access them.

Organizations are useful because they:

- Separate teams or business units, so each has its own workspaces, state, and variables
- Scope access control — users are given permissions through teams within an organization
- Hold shared resources such as the private registry, policies, and settings
- Let one Terraform Enterprise installation serve many teams

Every workspace belongs to an organization, so you need one before you can run Terraform. In this lab one organization is enough.

1. Create a new organization named **myorg**
   ```
   myorg
   ```
2. Click **Create organization**.
   ![](images/50-create-org.png ':size=800')

You now have a working Terraform Enterprise installation with an admin user and an organization ready to go.

## Create a workspace

A workspace is where Terraform Enterprise manages one set of infrastructure. Each workspace holds its own configuration, variables, state file and run history, and has its own access permissions. Locally, you keep a separate working directory for each configuration; in Terraform Enterprise, the workspace does that job, with the state stored centrally and securely instead of on your machine.

Before connecting Terraform to Terraform Enterprise you need a workspace to hold your state and run history.

Terraform Enterprise supports three workflow types for triggering runs:

- **CLI-driven** — you run `terraform plan` / `terraform apply` from your terminal; the CLI streams output back to you while the run executes remotely inside Terraform Enterprise.
- **API-driven** — a pipeline or script POSTs a configuration bundle directly to the Terraform Enterprise API and polls for results. No local Terraform installation required.
- **VCS-driven** — Terraform Enterprise connects to a version-control repository (GitHub, GitLab, etc.) and triggers runs automatically on every push to a branch.

In this section you use the **CLI-driven** workflow. You run commands locally in Cloud Shell, but the actual plan and apply execute inside your Terraform Enterprise instance on OpenShift.

1. In the Terraform Enterprise web UI, make sure you are in the `myorg` organization.
1. Click **Create a workspace**.
1. Choose **CLI-driven workflow**.
1. Set the workspace name to
   ```
   myworkspace
   ```
2. Click **Create**.

## Log in from the Terraform CLI

The Terraform CLI needs a token to authenticate against your Terraform Enterprise instance. When you create a workspace with the CLI-driven workflow, Terraform Enterprise shows you the exact `terraform login` command pre-filled with your hostname.

The setup script you ran earlier already wrote a token to `$HOME/.terraform.d/credentials.tfrc.json`, so the CLI is authenticated and you can skip the `terraform login` step.

1. View the configured credentials
   ```sh
   cat $HOME/.terraform.d/credentials.tfrc.json
   ```

Your Terraform CLI is authenticated to your Terraform Enterprise instance.

## Author Terraform files

The lab repository contains a simple `main.tf`. You need to add a `cloud` block that points Terraform at your Terraform Enterprise instance and workspace.

1. On the **myworkspace** overview page, copy the `terraform { ... }` snippet shown in the CLI-driven workflow panel. It looks like:
   ```hcl
   terraform {
     cloud {
       hostname     = "tfe.<your-username>.example.com"
       organization = "myorg"

       workspaces {
         name = "myworkspace"
       }
     }
   }
   ```
1. Open `main.tf` in your editor (or use `nano`):
   ```sh
   nano main.tf
   ```
1. Paste the `terraform { ... }` block at the top of the file, then save.

1. Re-initialize Terraform so it picks up the new backend:
   ```sh
   terraform init
   ```
   You should see:
   ```
   Initializing HCP Terraform...

   Initializing provider plugins...

   HCP Terraform has been successfully initialized!
   ```

## Plan

The `main.tf` configuration requires a `vpc_name` variable to discover the shared student VPC.

### Try a plan without variables

Run a plan now, before setting any variables, to see what happens when a required variable is missing.

1. From Cloud Shell, run:
   ```sh
   terraform plan
   ```
   Terraform Enterprise will fail the plan because `var.vpc_name` has no default value. The output is similar to:
   ```
   Running plan in Terraform Enterprise. Output will stream here. Pressing Ctrl-C
   will stop streaming the logs, but will not stop the plan running remotely.

   Preparing the remote plan...

   To view this run in a browser, visit:
   https://tfelab-123.tfe-123456.example.com/app/myorg/myworkspace/runs/run-cwNGH8U7jR3Pzkzr

   Waiting for the plan to start...

   Terraform v1.15.5
   on linux_amd64
   Initializing plugins and modules...
   ╷
   │ Error: No value for required variable
   │
   │   on main.tf line 14:
   │   14: variable "vpc_name" {
   │
   │ The root module input variable "vpc_name" is not set, and has no default
   │ value. Use a -var or -var-file command line argument to provide a value for
   │ this variable.
   ```

   Notice that the plan started and failed inside Terraform Enterprise, not on your machine. The run link in the output opens the failed run in the web UI.

   ?> Now is a good time to look at what Terraform Enterprise recorded for this run. Switch to the IBM Cloud Logs and IBM Cloud Monitoring tabs you kept open in the previous section. Refresh them to see the log entries from the run, including the agent pod, and the run metrics change.

### Add the variable and plan again

1. Open your workspace in the Terraform Enterprise web UI:
   ```
   https://tfe.<your-username>.example.com
   ```
1. Navigate to **myorg** > **myworkspace** > **Variables**.
1. Under **Workspace variables**, click **+ Add variable**.
1. Select **Terraform variable**.
1. Set the **Key** to:
   ```
   vpc_name
   ```
1. Set the **Value** to your shared student VPC name:
   ```
   tfelab-2963-student
   ```
1. Click **Save variable**.

1. Run the plan again:
   ```sh
   terraform plan
   ```
   Terraform will print a link to the run in Terraform Enterprise, then stream the plan output back to your terminal:
   ```
   Running plan in Terraform Cloud. Output will stream here. Pressing Ctrl-C
   will stop streaming the logs, but will not stop the plan from running
   remotely.

   Preparing the remote plan...

   To view this run in a browser, open:
   https://<your-username>.tfe.example.com/app/myorg/myworkspace/runs/run-xxxxxxxxxxxxxxxx
   ```
1. Click the link to follow the run in the Terraform Enterprise web UI.

## Apply

1. Run an apply:
   ```sh
   terraform apply
   ```
   Terraform Enterprise will execute the plan and, if it produces changes, ask you to confirm before applying.

1. Type `yes` at the confirmation prompt:
   ```
   Do you want to perform these actions in Terraform Cloud?
     Terraform Cloud will perform the actions described above.
     Only 'yes' will be accepted to approve.

   Enter a value: yes
   ```
1. Again, click the run link to follow the apply in the Terraform Enterprise web UI.

1. Once complete, the run status will show **Applied** and the state is now stored centrally in Terraform Enterprise.

## Look at the agent pods

Each plan and apply runs in its own short-lived agent pod in the `<your-username>-agents` namespace. Normally these pods are deleted automatically as soon as the run finishes. In this lab they are kept, because the `overrides.yaml` generated earlier sets `TFE_RUN_PIPELINE_KUBERNETES_DEBUG_ENABLED`. That lets you inspect them after the fact.

1. Go back to the OpenShift web console.
1. Select the `<your-username>-agents` project from the project drop-down.
1. In the left sidebar, under **Workloads**, click **Pods**. You will see one pod for each plan and apply you ran.
1. Click a pod name, then open the **Logs** tab to see exactly what ran inside the agent: the Terraform version, the plugin initialization, and the plan or apply output.

?> In a production installation you would leave this setting off, so agent pods clean themselves up and don't pile up in the cluster. You would also likely run your agents on potentially a different cluster, in dedicated agent pools, rather than next to Terraform Enterprise. Refer to the [HashiCorp Validated Designs](https://developer.hashicorp.com/validated-designs/terraform/installation-guide/introduction) for best practices.

?> **Checkpoint** — You've run your first plan and apply through Terraform Enterprise. The run executed inside OpenShift as a short-lived agent pod and the resulting state is now stored centrally in Terraform Enterprise. In the next section you will upgrade your Terraform Enterprise instance.

⇨ [Continue to Upgrade](60-upgrade.md)
