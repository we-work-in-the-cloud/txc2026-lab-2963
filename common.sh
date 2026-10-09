#!/usr/bin/env bash
# common.sh — Shared helpers for TFE lab scripts
#
# Source this file; do not execute it directly:
#   source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ============================================================
# resolve_username [arg]
#
# Returns the lab username, either from the positional argument
# or auto-detected from `ibmcloud target`.  Exits 1 on failure.
# Sets the global USERNAME variable.
# ============================================================
resolve_username() {
  USERNAME="${1:-}"

  if [[ -z "${USERNAME}" ]]; then
    USERNAME=$(ibmcloud target -o json 2>/dev/null \
      | jq -r '.user.user_email // empty' \
      | sed 's/@.*//')
    if [[ -n "${USERNAME}" ]]; then
      echo "→ Detected username from IBM Cloud account: ${USERNAME}"
    else
      echo "ERROR: username argument is required (could not auto-detect from ibmcloud target)."
      echo "Usage: bash $(basename "${BASH_SOURCE[1]}") [username]"
      echo "       e.g. bash $(basename "${BASH_SOURCE[1]}") tfelab-01"
      exit 1
    fi
  fi

  if ! echo "${USERNAME}" | grep -qE '^tfelab-[0-9]{2}$'; then
    echo "ERROR: Username '${USERNAME}' does not match expected pattern tfelab-NN."
    exit 1
  fi
}

# ============================================================
# discover_infra_rg
#
# Finds the *-infra resource group in the current account.
# Sets globals: INFRA_RG, BASENAME.
# ============================================================
discover_infra_rg() {
  echo "→ Discovering lab basename from resource groups..."
  INFRA_RG=$(ibmcloud resource groups --output json \
    | jq -r 'if type=="array" then .[].name else .resources[].name end | select(test("-infra$"))' \
    | head -n 1)

  if [[ -z "${INFRA_RG}" ]]; then
    echo "ERROR: Could not find an *-infra resource group. Are you logged in to the right account?"
    exit 1
  fi

  BASENAME="${INFRA_RG%-infra}"
  echo "  Basename:         ${BASENAME}"
}

# ============================================================
# discover_cluster [region]
#
# Targets the infra resource group, then finds the VPC-gen2
# ROKS cluster and its ingress domain.
# Sets globals: CLUSTER_ID, CLUSTER_DOMAIN, CLUSTER_TLS_SECRET.
# ============================================================
discover_cluster() {
  local region="${1:-us-south}"
  echo "→ Targeting resource group ${INFRA_RG} and looking up ROKS cluster..."
  ibmcloud target -g "${INFRA_RG}" -r "${region}" > /dev/null

  CLUSTER_ID=$(ibmcloud oc clusters --provider vpc-gen2 --output json \
    | jq -r '.[0].id // empty')

  if [[ -z "${CLUSTER_ID}" ]]; then
    echo "ERROR: No OCP cluster found in resource group ${INFRA_RG}."
    exit 1
  fi
  echo "  Cluster ID:       ${CLUSTER_ID}"

  echo "→ Retrieving cluster ingress domain and TLS secret..."
  local cluster_info
  cluster_info=$(ibmcloud oc cluster get --cluster "${CLUSTER_ID}" --output json)
  CLUSTER_DOMAIN=$(echo "${cluster_info}" | jq -r '.ingress.hostname')
  CLUSTER_TLS_SECRET=$(echo "${cluster_info}" | jq -r '.ingress.secretName')
  echo "  Cluster domain:   ${CLUSTER_DOMAIN}"
  echo "  Ingress TLS secret: ${CLUSTER_TLS_SECRET}"
}
