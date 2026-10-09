# Observe logs and metrics

Terraform Enterprise emits structured logs from every internal service and exposes a Prometheus-compatible metrics endpoint. In this section you open IBM Cloud Logs to explore those logs in real time, then open IBM Cloud Monitoring to see the metrics dashboard pre-built for your installation. Keep both tabs open — you'll return to them during the Troubleshoot section.

Your lab environment came with IBM Cloud Logs and IBM Cloud Monitoring already provisioned and configured. Here's what each service does and how Terraform Enterprise feeds into it:

| Service | What it receives | How it gets there |
|---|---|---|
| **IBM Cloud Logs** | All Terraform Enterprise service logs (`atlas`, `nginx`, `sidekiq`, `vault`) and audit logs | The IBM Cloud Logs agent deployed on the OpenShift cluster collects stdout/stderr from every pod and ships them automatically |
| **IBM Cloud Monitoring** | Prometheus metrics from the Terraform Enterprise `/metrics` endpoint | The Monitoring agent on the cluster scrapes the metrics endpoint and forwards time-series to your IBM Cloud Monitoring instance |

You don't need to configure anything — both pipelines were set up when the cluster was provisioned.

## Logs

### Why forward logs to a central system

Forwarding Terraform Enterprise logs to a central logging system or SIEM of your choice is the right thing to do in production. It lets you:

- Aggregate logs from Terraform Enterprise and your other applications in one place
- Keep historical data beyond the life of a pod, which is lost when the pod restarts or is rescheduled
- Search, correlate, and alert across systems
- Meet audit and compliance requirements

In this lab, the destination is IBM Cloud Logs. Any SIEM that can ingest container logs works the same way.

### Open IBM Cloud Logs

IBM Cloud Logs is IBM's scalable log management service. It ingests, indexes, and retains logs from cloud-native workloads, and gives you a real-time **Explore logs** view for search and analysis plus alerts and dashboards.

1. In the IBM Cloud console, click the **Menu** icon (☰) > **Observability**.
2. Click **Logging** in the left pane, then click **Instances** tab.
   ![](images/40-logging.png ':size=800')
3. Click **Dashboard**.

   The IBM Cloud Logs UI opens in a new tab.

4. In the left navigation, click the **Explore logs** icon > **Logs**.

   You land on the live log stream. Entries scroll in as Terraform Enterprise writes them. Each line shows the timestamp, severity, pod name, and the raw log message.

   ![](images/40-tfe-logs.png ':size=800')

### Filter to Terraform Enterprise logs

With all cluster workloads logging to the same instance, you need to scope the view to just your Terraform Enterprise pod.

1. In the search bar at the top, to see logs from a specific internal service — for example, only the application server — type:
   ```
   component:atlas
   ```
   The `component` field is set by Terraform Enterprise in every log line. Example values are:

   | Component | What it covers |
   |---|---|
   | `atlas` | Main application server (API requests, run lifecycle events) |
   | `nginx` | Reverse proxy (HTTP access log, TLS termination) |
   | `sidekiq` | Background job queue (worker start/finish, job errors) |
   | `vault` | Internal secrets manager |

!> Log entries from short-lived agent pods (in `<your-username>-agents`) also flow into IBM Cloud Logs. As you go through the next sections, refresh the dashboard to view the activity of agent pods.

?> IBM Cloud Logs also supports log-based alerts — you can trigger a notification when a pattern like `component:atlas level:ERROR` appears. Explore the **Alerts** section on your own after the lab.

### Dedicated dashboard

1. In the left navigation, click the **Dashboards** icon > **Custom Dashboards**.

1. Click **Terraform Enterprise**. The dashboard surfaces pre-filtered log views for each component — bookmark it for troubleshooting.

   ![](images/40-tfe-dashboard.png ':size=600')

## Metrics

### Why forward metrics to a central system

Forwarding Terraform Enterprise metrics to a central monitoring system of your choice is the right thing to do in production. It lets you:

- View Terraform Enterprise next to your other applications and infrastructure on shared dashboards
- Keep historical data to spot trends and plan capacity, beyond the life of a pod
- Alert on problems before your users notice them
- Correlate metrics with logs when troubleshooting

In this lab, the destination is IBM Cloud Monitoring. Any monitoring system that can scrape Prometheus-format metrics works the same way.

### Open IBM Cloud Monitoring

IBM Cloud Monitoring is IBM's cloud-native metrics platform. It collects time-series data from Prometheus-compatible endpoints, Kubernetes infrastructure, and IBM Cloud services, and surfaces them through dashboards and a **Metrics Explorer**.

Terraform Enterprise exposes metrics in Prometheus format at port `9090` on the `/metrics` path. The Monitoring agent scrapes this endpoint on each polling cycle (every 10 seconds) and forwards the metrics to your IBM Cloud Monitoring instance.

1. In the IBM Cloud console, click the **Menu** icon (☰) > **Observability**.
1. Click **Monitoring** in the left pane, then click Instances tab.
   ![](images/40-monitoring.png ':size=800')
1. Click **Dashboard**.

   The IBM Cloud Monitoring UI opens.

### Explore the Terraform Enterprise dashboard

A pre-built dashboard for Terraform Enterprise is included with your lab instance.

1. In the left navigation, click **Dashboards**.
1. Under **All Dashboards**, open **Terraform Enterprise - <your username>**.

   ![](images/40-tfe-monitoring-dashboard.png ':size=800')

   The dashboard is built on the [metrics])https://developer.hashicorp.com/terraform/enterprise/deploy/reference/metrics) Terraform Enterprise exposes about runs and the job queue:

   | Metric | Type | What it shows |
   |---|---|---|
   | `tfe_run_count` | gauge | Number of running containers being used for Terraform runs |
   | `tfe_run_limit` | gauge | Maximum number of concurrent runs, set by `TFE_CAPACITY_CONCURRENCY` |
   | `tfe_run_current_count` | gauge | Number of active Terraform runs, labeled by organization, workspace, and status |
   | `tfe_sidekiq_sidekiq_queue_size` | gauge | Current size of the job queue |
   | `tfe_sidekiq_sidekiq_queue_latency` | gauge | Seconds since the oldest job in the queue was enqueued |
   | `tfe_sidekiq_sidekiq_busy` | gauge | Number of workers currently processing jobs |
   | `tfe_sidekiq_sidekiq_enqueued` | gauge | Number of enqueued jobs |
   | `tfe_sidekiq_sidekiq_scheduled` | gauge | Number of jobs scheduled for future execution |
   | `tfe_sidekiq_sidekiq_processed` | gauge | Number of processed jobs |
   | `tfe_sidekiq_sidekiq_failed` | gauge | Number of failed jobs |
   | `tfe_sidekiq_sidekiq_retries` | gauge | Number of jobs scheduled for retry |
   | `tfe_sidekiq_sidekiq_dead` | gauge | Number of jobs that have exhausted their retries |

1. Later in the lab when you trigger a run from Cloud Shell (`terraform plan`), go back to this page and watch the run panels change.

### Explore metrics manually

The **Metrics Explorer** lets you query any raw metric by name.

1. In the IBM Cloud Monitoring left navigation, click **Explore**.
1. In the metric search box, type:
   ```
   tfe_
   ```
   All Terraform Enterprise metric names start with the `tfe_` prefix. Select any metric from the autocomplete list.

?> IBM Cloud Monitoring also supports metric-based alerts. Explore the **Alerts** section on your own after the lab.

?> **Checkpoint** — IBM Cloud Logs is showing Terraform Enterprise service logs in real time and you know how to filter by namespace and component. IBM Cloud Monitoring is showing the pre-built Terraform Enterprise dashboard with live metrics. Keep both browser tabs open — you'll need them in the Troubleshoot section.

⇨ [Continue to Plan and Apply](50-plan-apply.md)
