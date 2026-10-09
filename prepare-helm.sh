#!/usr/bin/env bash
# prepare-helm.sh — Student TFE setup script
#
# Run this in IBM Cloud Shell after logging in with your lab credentials.
# It discovers all required values via ibmcloud / oc and writes overrides.yaml
# for use with helm upgrade --install.
#
# Usage: bash /path/to/scripts/prepare-helm.sh [username]
#   e.g. bash ~/scripts/prepare-helm.sh tfelab-01
#   If username is omitted, it is auto-detected from `ibmcloud target`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ============================================================
# Pre-flight: verify oc is logged in to a cluster
# ============================================================
if ! oc get pods &>/dev/null; then
  echo "ERROR: Not logged in to an OpenShift cluster."
  echo "       Copy the login command from the OpenShift console"
  exit 1
fi

# ============================================================
# Input validation
# ============================================================
resolve_username "${1:-}"

echo ""
echo "============================================================"
echo " TFE Lab Setup — generating overrides.yaml for ${USERNAME}"
echo "============================================================"
echo ""

# ============================================================
# Step 1: Discover lab basename from the infra resource group
# ============================================================
discover_infra_rg

# ============================================================
# Step 2: Set region
# ============================================================
echo ""
echo "→ Using IBM Cloud region..."
REGION=us-east
echo "  Region:           ${REGION}"

# ============================================================
# Steps 3 & 4: Target infra RG, discover cluster, ingress domain and TLS secret
# ============================================================
echo ""
discover_cluster "${REGION}"

# ============================================================
# Step 5: Detect TFE image tag from the internal registry
# ============================================================
echo ""
echo "→ Detecting TFE image tag..."
# The cluster pull secret for images.releases.hashicorp.com is managed by
# Terraform (openshift-config/pull-secret). The image is pre-pulled and pinned
# on every node via a PinnedImageSet — no internal registry mirror needed.
TFE_IMAGE_TAG=$(oc get configmap tfe-image-config \
  -n ${USERNAME} \
  -o jsonpath='{.data.tfe_image_tag}' 2>/dev/null || true)

if [[ -z "${TFE_IMAGE_TAG}" ]]; then
  echo "  WARNING: Could not detect image tag from tfe-image-config — defaulting to 2.0.5."
  TFE_IMAGE_TAG="2.0.5"
fi

echo "  TFE image tag:    ${TFE_IMAGE_TAG}"
TFE_IMAGE_REPO="images.releases.hashicorp.com/hashicorp"

# ============================================================
# Step 6: Retrieve Postgres connection info and credentials from service key
# ============================================================
echo ""
echo "→ Retrieving Postgres connection info from service key ${BASENAME}-pg..."
PG_KEY=$(ibmcloud resource service-key "${BASENAME}-pg" --output json)
PG_HOST=$(echo "${PG_KEY}" | jq -r '.[0].credentials.connection.postgres.hosts[0].hostname')
PG_PORT=$(echo "${PG_KEY}" | jq -r '.[0].credentials.connection.postgres.hosts[0].port')
PG_USER=$(echo "${PG_KEY}" | jq -r '.[0].credentials.connection.postgres.authentication.username')
PG_PASS=$(echo "${PG_KEY}" | jq -r '.[0].credentials.connection.postgres.authentication.password')
echo "  Postgres host:    ${PG_HOST}:${PG_PORT}"
echo "  Postgres user:    ${PG_USER}"

# ============================================================
# Step 8: Retrieve COS HMAC credentials from service key
# ============================================================
echo ""
echo "→ Retrieving COS credentials from service key ${BASENAME}-cos..."
COS_KEY=$(ibmcloud resource service-key "${BASENAME}-cos" --output json)
COS_ACCESS_KEY=$(echo "${COS_KEY}" | jq -r '.[0].credentials.cos_hmac_keys.access_key_id')
COS_SECRET_KEY=$(echo "${COS_KEY}" | jq -r '.[0].credentials.cos_hmac_keys.secret_access_key')
echo "  COS access key:   ${COS_ACCESS_KEY:0:8}..."

# ============================================================
# Step 9: Download TFE license from shared credentials bucket
# ============================================================
echo ""
echo "→ Downloading TFE license from shared bucket..."
ibmcloud cos object-get \
  --bucket "${BASENAME}-student-data" \
  --force \
  --key tfe.hclic \
  tfe.hclic
TFE_LICENSE=$(cat tfe.hclic)
echo "  License downloaded (${#TFE_LICENSE} chars)"

# ============================================================
# Step 10: Derive convention-based values (no API calls needed)
# ============================================================
PG_DB="${USERNAME//-/_}"
COS_BUCKET="${BASENAME}-${USERNAME}-tfe"
COS_ENDPOINT="https://s3.direct.${REGION}.cloud-object-storage.appdomain.cloud"
REDIS_HOST="tfe-redis.${USERNAME}.svc.cluster.local"
REDIS_PORT="6379"
TFE_HOSTNAME="${USERNAME}.${CLUSTER_DOMAIN}"
TFE_ADMIN_HOSTNAME="${USERNAME}-admin.${CLUSTER_DOMAIN}"
INGRESS_TLS_SECRET="tfe-certificates"
TFE_ENCRYPTION_PASSWORD="${USERNAME}"

echo ""
echo "  PG database:      ${PG_DB}"
echo "  COS bucket:       ${COS_BUCKET}"
echo "  Redis:            ${REDIS_HOST}:${REDIS_PORT}"
echo "  TFE hostname:     ${TFE_HOSTNAME}"
echo "  Admin console:    ${TFE_ADMIN_HOSTNAME}"
echo "  Ingress TLS secret: ${INGRESS_TLS_SECRET}"

# ============================================================
# Step 11: Write overrides.yaml
# ============================================================
echo ""
echo "→ Writing overrides.yaml..."

cat > overrides.yaml <<EOF
# TFE Helm Chart Overrides — generated by prepare-helm.sh for ${USERNAME}
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

image:
  repository: ${TFE_IMAGE_REPO}
  name: terraform-enterprise
  tag: "${TFE_IMAGE_TAG}"
  pullPolicy: IfNotPresent

# Pull secret pre-created by Terraform in this namespace (kubernetes_secret_v1
# "hashicorp-registry" in modules/per-user/k8s.tf).
imagePullSecrets:
  - name: hashicorp-registry

replicaCount: 1

strategy:
  type: Recreate

openshift:
  enabled: true

service:
  type: ClusterIP

# Mount the cluster wildcard TLS secret into the TFE pod so TFE serves it
# directly. The router uses passthrough — no cert termination at the edge.
tls:
  certificateSecret: ${INGRESS_TLS_SECRET}

ingress:
  enabled: true
  className: openshift-default
  annotations:
    route.openshift.io/termination: "passthrough"
  hosts:
    - host: ${TFE_HOSTNAME}
      paths:
        - path: ""
          pathType: ImplementationSpecific
          serviceName: "terraform-enterprise"
          portNumber: 443
    - host: ${TFE_ADMIN_HOSTNAME}
      paths:
        - path: ""
          pathType: ImplementationSpecific
          serviceName: "terraform-enterprise"
          portNumber: 8446

agents:
  rbac:
    enabled: false
  namespace:
    enabled: false
    name: ${USERNAME}-agents

initContainers: null

resources:
  requests:
    cpu: "500m"
    memory: "2Gi"
  limits:
    cpu: "2000m"
    memory: "4Gi"

env:
  variables:
    TFE_HOSTNAME: "${TFE_HOSTNAME}"
    TFE_IACT_SUBNETS: "0.0.0.0/0"
    TFE_DATABASE_HOST: "${PG_HOST}:${PG_PORT}"
    TFE_DATABASE_NAME: "${PG_DB}"
    TFE_DATABASE_USER: "${PG_USER}"
    TFE_DATABASE_PARAMETERS: "sslmode=require"
    TFE_DATABASE_EXTRA_SCHEMAS: "ibm_extension"
    TFE_DATABASE_MONITOR_ENABLED: "true"
    TFE_OBJECT_STORAGE_TYPE: "s3"
    TFE_OBJECT_STORAGE_S3_BUCKET: "${COS_BUCKET}"
    TFE_OBJECT_STORAGE_S3_REGION: "${REGION}"
    TFE_OBJECT_STORAGE_S3_ENDPOINT: "${COS_ENDPOINT}"
    TFE_OBJECT_STORAGE_S3_USE_INSTANCE_PROFILE: "false"
    TFE_REDIS_HOST: "${REDIS_HOST}"
    TFE_REDIS_PORT: "${REDIS_PORT}"
    TFE_REDIS_USE_AUTH: "false"
    TFE_REDIS_USE_TLS: "false"
    TFE_CAPACITY_MEMORY: "512"
    TFE_LICENSE_REPORTING_OPT_OUT: "true"
    TFE_TLS_CERT_FILE: "/etc/ssl/private/tfe/tls.crt"
    TFE_TLS_KEY_FILE: "/etc/ssl/private/tfe/tls.key"
    TFE_METRICS_ENABLE: "true"
    TFE_METRICS_HTTP_PORT: "9090"
    TFE_RUN_PIPELINE_KUBERNETES_DEBUG_ENABLED: "true"
  secrets:
    TFE_LICENSE: "${TFE_LICENSE}"
    TFE_ENCRYPTION_PASSWORD: "${TFE_ENCRYPTION_PASSWORD}"
    TFE_DATABASE_PASSWORD: "${PG_PASS}"
    TFE_OBJECT_STORAGE_S3_ACCESS_KEY_ID: "${COS_ACCESS_KEY}"
    TFE_OBJECT_STORAGE_S3_SECRET_ACCESS_KEY: "${COS_SECRET_KEY}"
EOF

echo "  overrides.yaml written."

# ============================================================
# Step 12: Print summary and helm command
# ============================================================
echo ""
echo "============================================================"
echo " Configuration Summary"
echo "============================================================"
echo "  Username:         ${USERNAME}"
echo "  TFE hostname:     https://${TFE_HOSTNAME}"
echo "  Admin console:    https://${TFE_ADMIN_HOSTNAME}"
echo "  Namespace:        ${USERNAME}"
echo "  Postgres:         ${PG_HOST}:${PG_PORT} / db=${PG_DB}"
echo "  COS bucket:       ${COS_BUCKET}"
echo "  Redis:            ${REDIS_HOST}:${REDIS_PORT}"
echo ""
echo "============================================================"
echo " Install TFE:"
echo "============================================================"
echo ""
echo "  helm repo add hashicorp https://helm.releases.hashicorp.com"
echo "  helm repo update"
echo ""
echo "  helm upgrade --install terraform-enterprise hashicorp/terraform-enterprise \\"
echo "    --version ${TFE_IMAGE_TAG} \\"
echo "    --namespace ${USERNAME} \\"
echo "    -f overrides.yaml"
echo ""
echo "After install, TFE will be available at:"
echo "  https://${TFE_HOSTNAME}"
echo ""
echo "Admin console:"
echo "  https://${TFE_ADMIN_HOSTNAME}"
echo ""
echo "Then run the next script to create the initial admin user:"
echo "  bash $(dirname "${BASH_SOURCE[0]}")/030-create-initial-user.sh"
echo ""
