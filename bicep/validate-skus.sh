#!/bin/bash
set -e
echo "Validating VM SKUs in region: ${LOCATION}"
echo "Environment variables set:"
echo "LOCATION: ${LOCATION}"
echo "SCHEDULER_SKU: ${SCHEDULER_SKU}"
echo "LOGIN_SKU: ${LOGIN_SKU}"
echo "HTC_SKU: ${HTC_SKU}"
echo "HPC_SKU: ${HPC_SKU}"
echo "GPU_SKU: ${GPU_SKU}"

# Build dynamic query filter based on SKUs that need validation
query_filter=""
filter_conditions=""

# Add each SKU to the filter if it's defined
if [[ -n "$HTC_SKU" ]]; then
  if [[ -n "$filter_conditions" ]]; then
    filter_conditions="$filter_conditions || name=='$HTC_SKU'"
  else
    filter_conditions="name=='$HTC_SKU'"
  fi
fi

if [[ -n "$HPC_SKU" ]]; then
  if [[ -n "$filter_conditions" ]]; then
    filter_conditions="$filter_conditions || name=='$HPC_SKU'"
  else
    filter_conditions="name=='$HPC_SKU'"
  fi
fi

if [[ -n "$GPU_SKU" ]]; then
  if [[ -n "$filter_conditions" ]]; then
    filter_conditions="$filter_conditions || name=='$GPU_SKU'"
  else
    filter_conditions="name=='$GPU_SKU'"
  fi
fi

if [[ -n "$SCHEDULER_SKU" ]]; then
  if [[ -n "$filter_conditions" ]]; then
    filter_conditions="$filter_conditions || name=='$SCHEDULER_SKU'"
  else
    filter_conditions="name=='$SCHEDULER_SKU'"
  fi
fi

if [[ -n "$LOGIN_SKU" ]]; then
  if [[ -n "$filter_conditions" ]]; then
    filter_conditions="$filter_conditions || name=='$LOGIN_SKU'"
  else
    filter_conditions="name=='$LOGIN_SKU'"
  fi
fi

if [[ -z "$filter_conditions" ]]; then
  echo "[DEBUG] No specific SKUs defined yet; loading all SKUs." >&2
  query_filter="value[?locationInfo!=null]"
else
  query_filter="value[?$filter_conditions]"
  echo "[DEBUG] Loading SKUs with filter: $filter_conditions" >&2
fi

# Get subscription ID
subscription_id=$(az account show --query id -o tsv)
if [[ -z "$subscription_id" ]]; then
  echo "[ERROR] Could not get subscription ID" >&2
  exit 1
fi

# Query Azure REST API for SKUs
echo "[DEBUG] Calling Azure REST API for SKUs..." >&2
api_url="/subscriptions/$subscription_id/providers/Microsoft.Compute/skus?api-version=2021-07-01&\$filter=location eq '$LOCATION'"

if ! raw=$(az rest --method get --url "$api_url" --query "$query_filter" -o json 2>&1); then
  echo "[ERROR] az rest call to list SKUs failed: $raw" >&2
  exit 1
fi

# Parse results and validate each required SKU
if ! skus_found=$(echo "$raw" | jq -r '.[].name' 2>/dev/null | sort | uniq); then
  echo "[ERROR] Failed to parse SKU results with jq" >&2
  echo "[DEBUG] Raw response: $raw" >&2
  exit 1
fi

echo "[DEBUG] Available SKUs found:" >&2
echo "$skus_found" | sed 's/^/  /' >&2

# Validate each required SKU
validate_sku() {
  local sku_name="$1"
  local sku_type="$2"
  echo "Validating $sku_type SKU: $sku_name"
  
  if echo "$skus_found" | grep -q "^$sku_name$"; then
    echo "✓ $sku_type SKU '$sku_name' is available"
    return 0
  else
    echo "ERROR: VM SKU '$sku_name' for $sku_type nodes is not available in region '${LOCATION}'" >&2
    return 1
  fi
}

# Validate all SKUs
validate_sku "${SCHEDULER_SKU}" "scheduler" || exit 1
validate_sku "${LOGIN_SKU}" "login" || exit 1
validate_sku "${HTC_SKU}" "HTC" || exit 1
validate_sku "${HPC_SKU}" "HPC" || exit 1
validate_sku "${GPU_SKU}" "GPU" || exit 1

echo "All VM SKUs validated successfully"