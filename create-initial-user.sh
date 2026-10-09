#!/usr/bin/env bash
# create-initial-user.sh — Create the initial admin user in a student's TFE instance
#
# Usage: bash /path/to/scripts/create-initial-user.sh [username]
#   e.g. bash ~/scripts/create-initial-user.sh tfelab-01
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

# ============================================================
# Discover TFE hostname from the cluster (same logic as prepare-helm.sh)
# ============================================================
REGION=us-south
discover_infra_rg
echo ""
discover_cluster "${REGION}"

TFE_HOSTNAME="${USERNAME}.${CLUSTER_DOMAIN}"

# ============================================================
# Retrieve IACT token and create initial admin user
# ============================================================
IACT_TOKEN=$(oc exec -n "${USERNAME}" deploy/terraform-enterprise -- tfectl admin token)

echo "IACT token retrieved."

TFE_PASSWORD="!${USERNAME}!"

CREATE_USER_RESPONSE=$(
  curl --silent --fail \
    --header "Content-Type: application/json" \
    --data "{\"username\": \"${USERNAME}\", \"email\": \"${USERNAME}@example.com\", \"password\": \"${TFE_PASSWORD}\"}" \
    "https://${TFE_HOSTNAME}/admin/initial-admin-user?token=${IACT_TOKEN}"
)

USER_TOKEN=$(echo "${CREATE_USER_RESPONSE}" | jq -r '.token')
TOKEN_FILE="${USERNAME}.user.token"
echo "${USER_TOKEN}" > "${TOKEN_FILE}"

# pre-create the .terraform
mkdir -p $HOME/.terraform.d

echo "{
  \"credentials\": {
    \"${TFE_HOSTNAME}\": {
      \"token\": \"${USER_TOKEN}\"
    }
  }" > $HOME/.terraform.d/credentials.tfrc.json

echo ""
echo "============================================================"
echo " Initial admin user created"
echo "============================================================"
echo "  Username:  ${USERNAME}"
echo "  Password:  ${TFE_PASSWORD}"
echo "  TFE URL:   https://${TFE_HOSTNAME}"
echo "  Token:     ${USER_TOKEN}"
echo "             (saved to ${TOKEN_FILE})"
echo "============================================================"
echo ""
