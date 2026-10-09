# Deploy Terraform Enterprise

## What is Terraform?

[Terraform](https://www.terraform.io) is an infrastructure as code tool. You describe the infrastructure you want — servers, networks, databases, Kubernetes clusters — in declarative configuration files, and Terraform works out the steps to create, update, or delete resources to match. It works with any cloud or service that has a provider, so you use one workflow across IBM Cloud, AWS, Azure, and more.

Terraform on its own works well for an individual. For a team, it quickly raises questions: where is the state file stored and who can read it? Who is allowed to apply changes to production? How do you keep credentials off laptops? How do you audit what changed?

## What does Terraform Enterprise add?

Terraform Enterprise is the self-hosted platform that answers those questions. You run it in your own environment, and it gives your teams a shared, governed place to run Terraform:

| Capability | What it brings |
|---|---|
| **Remote runs** | Plans and applies run in a consistent, managed environment instead of on individual laptops |
| **Secure state management** | State is stored centrally, encrypted, versioned, and access-controlled |
| **Team access control** | Role-based permissions on organizations, projects, and workspaces |
| **Policy as code** | Guardrails for cost, security, and compliance (Terraform Policy, Sentinel or OPA) are enforced before changes are applied |
| **Private registry** | Share approved modules and providers across your organization |
| **VCS and API integration** | Trigger runs from Git commits, pull requests, or the API |
| **Audit and self-hosting** | Keep data and workloads in your own infrastructure, with an audit trail of every change |

## Deploying Terraform Enterprise

Installing Terraform Enterprise involves many moving parts — but Terraform is all about automation, so you should not have to click through a dozen configuration screens!

IBM provides [HashiCorp Validated Designs](https://developer.hashicorp.com/validated-designs/terraform/installation-guide/introduction) and supporting Terraform modules to accelerate Terraform Enterprise deployments on AWS, Google Cloud, and Azure. For IBM Cloud, IBM offers a [Terraform Enterprise deployable architecture](https://cloud.ibm.com/catalog?search=%22terraform%20enterprise%22) that provisions everything in one shot — VPC, Cloud Object Storage, PostgreSQL, Redis, and the Terraform Enterprise workload itself.

## What's already provisioned for you

For this lab, the heavy lifting is done. The following infrastructure is already up and waiting:

| Resource | Purpose |
|---|---|
| **Red Hat OpenShift cluster** | Where Terraform Enterprise will run as a Kubernetes workload |
| **S3-compatible bucket** | Terraform Enterprise blob storage for state files and run artifacts |
| **PostgreSQL database** | Terraform Enterprise application database |
| **Redis service** | Terraform Enterprise cache and coordination layer |
| **Logging & Monitoring** | Pre-wired to the cluster for observability |

Your job is to deploy Terraform Enterprise onto this infrastructure using [Helm](https://helm.sh) and the official [Terraform Enterprise Helm chart](https://github.com/hashicorp/terraform-enterprise-helm).

## Open Cloud Shell

IBM Cloud Shell gives you a browser-based terminal with all the tools you need — `helm`, `oc`, and more — already installed, no setup required.

1. In the IBM Cloud console, click the **Cloud Shell** icon (>_) in the top right navigation bar.
   ![](images/20-cloud-shell-icon.png ':size=200')
1. Wait a few seconds for the shell to initialize. You should see a prompt like:
   ```
   [user@cloudshell ~]$
   ```

   ?> Cloud Shell sessions time out after 60 minutes of inactivity.

## Log in to the OpenShift cluster

Before running any `oc` or `helm` commands you need to authenticate against the OpenShift cluster.

1. Go to the [list of OpenShift clusters](https://cloud.ibm.com/containers/cluster-management/clusters?platformType=openshift).
2. Click the cluster named **tfe**.
3. Click **OpenShift web console**.
   ![](images/20-openshift-web-console.png ':size=500')

   !> You may get a popup blocked message depending of your web browser configuration. If so, allow popups from this site and click the button again.
4. In the OpenShift web console, click your username in the top-right corner and select **Copy login command**.
   ![](images/20-copy-login-command.png ':size=300')
5. Click **Display Token**. Copy the `oc login` command — it looks like:
   ```
   oc login --token=sha256~xxxx --server=https://your-cluster.example.com:6443
   ```
6. Switch back to Cloud Shell and paste the command, then press **Enter**.
   ```sh
   oc login --token=sha256~xxxx --server=https://your-cluster.example.com:6443
   ```
   You should see:
   ```
   Logged into "https://your-cluster.example.com:6443" as "your-username" using the token provided.
   ```

## Clone the lab repository

The lab repository contains the helper script that will configure Helm for your specific environment.

1. Clone the repository:
   ```sh
   git clone https://github.com/hashicorp/txc2026-lab-2963
   ```
1. Change into the lab directory:
   ```sh
   cd txc2026-lab-2963
   ```

## Generate the Helm overrides

[Helm](https://helm.sh) is the package manager for Kubernetes. A **Helm chart** is a versioned, reusable bundle of Kubernetes manifests — deployments, services, secrets, config maps — packaged together with a templating engine so you can customise them without forking the source. Instead of writing raw YAML for every Kubernetes object, you provide a small `values.yaml` (or an overrides file) and Helm renders the full manifest set for your environment.

The official [terraform-enterprise-helm](https://github.com/hashicorp/terraform-enterprise-helm) chart from HashiCorp wraps the entire Terraform Enterprise workload. It handles:

| What the chart manages | Why it matters |
|---|---|
| Deployment & pod spec | Correct container image, resource requests, liveness probes |
| TLS / ingress wiring | Terminates HTTPS with the certificate you supply |
| External service config | Injects your PostgreSQL, Redis, and S3 connection details as environment variables |
| License file | Injects the HashiCorp licence as a Kubernetes secret |

Using the chart means you get a tested, upgradeable installation path — upgrading Terraform Enterprise is a single `helm upgrade` command rather than manually editing a dozen manifest files.

The chart is configured through an `overrides.yaml` file. Rather than filling it in manually, the `prepare-helm.sh` script reads your provisioned services and generates the file automatically.

1. Run the script:
   ```sh
   ./prepare-helm.sh
   ```
   The script will:
   - Retrieve the connection strings for PostgreSQL, Redis, and the S3 bucket
   - Obtain the Terraform Enterprise license
   - Produce a ready-to-use `overrides.yaml` in the current directory

   At the end you will see output similar to:
   ```
   ✓ overrides.yaml generated

   Next steps:
     helm repo add hashicorp https://helm.releases.hashicorp.com
     helm repo update
     helm upgrade --install terraform-enterprise hashicorp/terraform-enterprise \
       --version <version> --namespace <your-username> -f overrides.yaml
   ```

   ?> The output is tailored to your user. Copy the commands as you go through the steps below.

1. Take a moment to look at the generated file:
   ```sh
   more overrides.yaml
   ```
   Press **Space** to page down and **q** to quit. You will find the PostgreSQL, Redis, and S3 settings the script filled in for you.

## Deploy Terraform Enterprise with Helm

1. Add the HashiCorp Helm repository, so Helm knows where to download the Terraform Enterprise chart from:
   ```sh
   helm repo add hashicorp https://helm.releases.hashicorp.com
   helm repo update
   ```
   `helm repo add` registers the repository under the name `hashicorp`. `helm repo update` refreshes the list of available charts and versions.
1. Scroll back to the output of `./prepare-helm.sh` and copy the `helm upgrade --install` command printed there. Paste it in Cloud Shell and run it. The command looks like this example:
   ```sh
   helm upgrade --install terraform-enterprise hashicorp/terraform-enterprise \
     --version <version> --namespace <your-username> -f overrides.yaml
   ```

   !> Don't copy the example above. The `<version>` and `<your-username>` placeholders only show the shape of the command. The one printed by the script has your real values.

   Helm returns within a few seconds with a summary similar to:
   ```
   Release "terraform-enterprise" does not exist. Installing it now.
   NAME: terraform-enterprise
   LAST DEPLOYED: Thu Oct  8 21:17:46 2026
   NAMESPACE: tfelab-123
   STATUS: deployed
   REVISION: 1
   DESCRIPTION: Install complete
   TEST SUITE: None
   ```
   `STATUS: deployed` means Helm has created the Kubernetes resources, not that Terraform Enterprise is ready. The full first initialization typically takes **5-10 minutes** while the pod pulls its image and completes its startup sequence.

### Monitor the rollout — Option A: Cloud Shell

1. Check the current pod status at any time:
   ```sh
   oc get pods
   ```
   The **STATUS** column progresses through `Pending` → `Init:0/1` → `PodInitializing` → `Running`. Re-run the command as needed, or use it with `--watch` to have it refresh automatically:
   ```sh
   oc get pods --watch
   ```
   Press **Ctrl-C** to exit `watch` once the pod is **Running**.

2. To see exactly what the container is doing during startup, tail its logs:
   ```sh
   oc logs -f -l app=terraform-enterprise
   ```
   <!-- Look for a line like `TFE is now ready to use. Happy Terraforming!` to confirm the application has finished initialising. -->

### Monitor the rollout — Option B: OpenShift web console

1. Open the OpenShift web console URL.
2. Select your project (`<your-username>`) from the project drop-down.
3. In the left sidebar, under **Workloads**, click **Topology**. You will see the `terraform-enterprise` deployment represented as a circle.
   ![](images/20-monitor-deployment.png ':size=800')
4. Watch the circle — it turns **solid blue** once all pods are healthy. A progress ring indicates the rollout is still in progress.
5. Click the circle, then open the **Resources** tab to see the pod list.
6. Click a pod name → **Logs** to stream the container output directly in the browser.
<!-- 7. Look for `TFE is now ready to use. Happy Terraforming!`. -->

<!-- ## Access Terraform Enterprise

Once the pod is **Running** and you have seen `TFE is now ready to use. Happy Terraforming!` in the logs, get the public URL of the application.

**Option A — Cloud Shell:** retrieve the OpenShift route:
```sh
oc get routes
```
The **HOST/PORT** column shows the hostname. Open that URL in your browser.

**Option B — OpenShift web console:** in the **Topology** view, click the `terraform-enterprise` circle and look for the external route link in the top-right corner of the panel (the small arrow-in-a-box icon).

![](images/20-topology-route.png ':size=800')


Either way, you should land on the Terraform Enterprise login page.

![](images/20-tfe-login.png ':size=400') -->

?> **Checkpoint** — Terraform Enterprise is starting. In the next section you will verify the health of all its subsystems before you start using it.

⇨ [Continue to Health](30-health.md)
