#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Discover OCI resources created by this module and import them into OpenTofu state.

The script discovers resources by the module's display-name convention:
  <name>-vcn
  <name>-igw
  <name>-public-routes
  <name>-public-security-list
  <name>-public-subnet
  <name>
  <name>-cost-alert-budget
  <name>-any-cost-alert

Usage:
  scripts/import-existing-oci.sh [options]

Options:
  --var-file PATH        tfvars file to read. Default: main.tfvars
  --name NAME            Module name prefix. Defaults to var.name, then always-free-arm
  --compartment-id OCID  Compartment OCID. Defaults to var.compartment_id
  --region REGION        OCI region. Defaults to var.region
  --profile PROFILE      OCI CLI profile to use
  --execute              Actually run tofu import. Without this, prints a dry run
  --skip-budget          Do not discover or import budget and alert-rule resources
  --no-init              Do not run tofu init before importing
  --plan                 Run tofu plan after successful imports
  -h, --help             Show this help

Environment:
  TOFU_BIN               OpenTofu binary to use. Default: tofu
  OCI_CLI_PROFILE        OCI CLI profile, if --profile is not set
  TF_VAR_name            Fallback for --name
  TF_VAR_compartment_id  Fallback for --compartment-id
  TF_VAR_region          Fallback for --region

Examples:
  # Discover and print the imports that would run:
  scripts/import-existing-oci.sh --var-file main.tfvars

  # Import discovered resources into local or configured remote state:
  scripts/import-existing-oci.sh --var-file main.tfvars --execute

  # Then inspect drift carefully:
  tofu plan -var-file=main.tfvars
EOF
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

VAR_FILE="main.tfvars"
NAME=""
COMPARTMENT_ID=""
REGION=""
PROFILE="${OCI_CLI_PROFILE:-}"
EXECUTE=0
RUN_INIT=1
RUN_PLAN=0
SKIP_BUDGET=0
TOFU_BIN="${TOFU_BIN:-tofu}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --var-file|-var-file)
      VAR_FILE="${2:?--var-file requires a path}"
      shift 2
      ;;
    --name)
      NAME="${2:?--name requires a value}"
      shift 2
      ;;
    --compartment-id)
      COMPARTMENT_ID="${2:?--compartment-id requires an OCID}"
      shift 2
      ;;
    --region)
      REGION="${2:?--region requires a value}"
      shift 2
      ;;
    --profile)
      PROFILE="${2:?--profile requires a value}"
      shift 2
      ;;
    --execute)
      EXECUTE=1
      shift
      ;;
    --dry-run)
      EXECUTE=0
      shift
      ;;
    --skip-budget)
      SKIP_BUDGET=1
      shift
      ;;
    --no-init)
      RUN_INIT=0
      shift
      ;;
    --plan)
      RUN_PLAN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

cd "$MODULE_DIR"

if [[ "$VAR_FILE" = /* ]]; then
  VAR_FILE_PATH="$VAR_FILE"
else
  VAR_FILE_PATH="$MODULE_DIR/$VAR_FILE"
fi

if [[ ! -f "$VAR_FILE_PATH" ]]; then
  echo "tfvars file not found: $VAR_FILE_PATH" >&2
  exit 1
fi

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: $cmd" >&2
    exit 1
  fi
}

need_cmd oci
need_cmd jq
need_cmd "$TOFU_BIN"

# Minimal tfvars reader for simple assignments such as:
#   region = "us-ashburn-1"
#   compartment_id = "ocid1..."
# It intentionally does not try to parse arbitrary HCL expressions.
tfvar() {
  local key="$1"
  awk -v key="$key" '
    /^[[:space:]]*#/ { next }
    {
      line = $0
      sub(/[[:space:]]+#.*$/, "", line)
      if (line ~ "^[[:space:]]*" key "[[:space:]]*=") {
        sub(/^[^=]*=/, "", line)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        if (line ~ /^".*"$/) {
          sub(/^"/, "", line)
          sub(/"$/, "", line)
        }
        print line
        exit
      }
    }
  ' "$VAR_FILE_PATH"
}

NAME="${NAME:-${TF_VAR_name:-$(tfvar name)}}"
NAME="${NAME:-always-free-arm}"
COMPARTMENT_ID="${COMPARTMENT_ID:-${TF_VAR_compartment_id:-$(tfvar compartment_id)}}"
REGION="${REGION:-${TF_VAR_region:-$(tfvar region)}}"

if [[ -z "$COMPARTMENT_ID" ]]; then
  echo "Could not determine compartment_id. Set it in $VAR_FILE or pass --compartment-id." >&2
  exit 1
fi

if [[ -z "$REGION" ]]; then
  echo "Could not determine region. Set it in $VAR_FILE or pass --region." >&2
  exit 1
fi

OCI_CMD=(oci)
if [[ -n "$PROFILE" ]]; then
  OCI_CMD+=(--profile "$PROFILE")
fi
OCI_CMD+=(--region "$REGION")

print_shell_cmd() {
  local arg
  for arg in "$@"; do
    printf '%q ' "$arg"
  done
  printf '\n'
}

find_one_by_display_name() {
  local label="$1"
  local display_name="$2"
  local required="$3"
  shift 3

  echo "Discovering ${label}: ${display_name}" >&2

  local json
  if ! json="$("${OCI_CMD[@]}" "$@" --output json)"; then
    echo "Failed to list ${label}." >&2
    exit 1
  fi

  local ids=()
  mapfile -t ids < <(
    jq -r --arg display_name "$display_name" '
      .data[]?
      | select(."display-name" == $display_name)
      | select(((."lifecycle-state" // .state // "") != "TERMINATED") and ((."lifecycle-state" // .state // "") != "DELETED"))
      | .id // empty
    ' <<<"$json"
  )

  case "${#ids[@]}" in
    0)
      if [[ "$required" == "required" ]]; then
        echo "No ${label} found with display name ${display_name}." >&2
        exit 1
      fi
      echo "Optional ${label} not found; skipping." >&2
      return 1
      ;;
    1)
      printf '%s\n' "${ids[0]}"
      ;;
    *)
      echo "Multiple ${label} resources found with display name ${display_name}:" >&2
      printf '  %s\n' "${ids[@]}" >&2
      echo "Refusing to guess. Rename duplicates or import manually." >&2
      exit 1
      ;;
  esac
}

declare -a IMPORT_ADDRS=()
declare -a IMPORT_IDS=()

add_import() {
  IMPORT_ADDRS+=("$1")
  IMPORT_IDS+=("$2")
}

VCN_ID="$(find_one_by_display_name "VCN" "${NAME}-vcn" required network vcn list --compartment-id "$COMPARTMENT_ID" --all)"
add_import "oci_core_vcn.this" "$VCN_ID"

VCN_JSON="$("${OCI_CMD[@]}" network vcn get --vcn-id "$VCN_ID" --output json)"
DEFAULT_SECURITY_LIST_ID="$(jq -r '.data."default-security-list-id" // empty' <<<"$VCN_JSON")"
if [[ -z "$DEFAULT_SECURITY_LIST_ID" ]]; then
  echo "Could not determine default security list ID for VCN ${VCN_ID}." >&2
  exit 1
fi
add_import "oci_core_default_security_list.this" "$DEFAULT_SECURITY_LIST_ID"

IGW_ID="$(find_one_by_display_name "internet gateway" "${NAME}-igw" required network internet-gateway list --compartment-id "$COMPARTMENT_ID" --vcn-id "$VCN_ID" --all)"
add_import "oci_core_internet_gateway.this" "$IGW_ID"

ROUTE_TABLE_ID="$(find_one_by_display_name "route table" "${NAME}-public-routes" required network route-table list --compartment-id "$COMPARTMENT_ID" --vcn-id "$VCN_ID" --all)"
add_import "oci_core_route_table.public" "$ROUTE_TABLE_ID"

SECURITY_LIST_ID="$(find_one_by_display_name "security list" "${NAME}-public-security-list" required network security-list list --compartment-id "$COMPARTMENT_ID" --vcn-id "$VCN_ID" --all)"
add_import "oci_core_security_list.public" "$SECURITY_LIST_ID"

SUBNET_ID="$(find_one_by_display_name "subnet" "${NAME}-public-subnet" required network subnet list --compartment-id "$COMPARTMENT_ID" --vcn-id "$VCN_ID" --all)"
add_import "oci_core_subnet.public" "$SUBNET_ID"

INSTANCE_ID="$(find_one_by_display_name "compute instance" "$NAME" required compute instance list --compartment-id "$COMPARTMENT_ID" --all)"
add_import "oci_core_instance.this" "$INSTANCE_ID"

if [[ "$SKIP_BUDGET" -eq 0 ]]; then
  if BUDGET_ID="$(find_one_by_display_name "budget" "${NAME}-cost-alert-budget" optional budgets budget list --compartment-id "$COMPARTMENT_ID" --all)"; then
    add_import "oci_budget_budget.this" "$BUDGET_ID"

    if ALERT_RULE_ID="$(find_one_by_display_name "budget alert rule" "${NAME}-any-cost-alert" optional budgets alert-rule list --budget-id "$BUDGET_ID" --all)"; then
      add_import "oci_budget_alert_rule.any_cost" "budgets/${BUDGET_ID}/alertRules/${ALERT_RULE_ID}"
    fi
  fi
fi

printf '\nDiscovered imports:\n' >&2
for i in "${!IMPORT_ADDRS[@]}"; do
  printf '  %-36s %s\n' "${IMPORT_ADDRS[$i]}" "${IMPORT_IDS[$i]}" >&2
done

if [[ "$EXECUTE" -eq 0 ]]; then
  printf '\nDry run only. Re-run with --execute to import into OpenTofu state.\n\n' >&2
  for i in "${!IMPORT_ADDRS[@]}"; do
    print_shell_cmd "$TOFU_BIN" import "-var-file=$VAR_FILE" "${IMPORT_ADDRS[$i]}" "${IMPORT_IDS[$i]}"
  done
  exit 0
fi

if [[ "$RUN_INIT" -eq 1 ]]; then
  echo "Running $TOFU_BIN init -input=false" >&2
  "$TOFU_BIN" init -input=false
fi

state_has_address() {
  local address="$1"
  "$TOFU_BIN" state list 2>/dev/null | grep -Fxq "$address"
}

for i in "${!IMPORT_ADDRS[@]}"; do
  address="${IMPORT_ADDRS[$i]}"
  import_id="${IMPORT_IDS[$i]}"

  if state_has_address "$address"; then
    echo "Skipping ${address}; it is already present in state." >&2
    continue
  fi

  echo "Importing ${address}" >&2
  "$TOFU_BIN" import "-var-file=$VAR_FILE" "$address" "$import_id"
done

if [[ "$RUN_PLAN" -eq 1 ]]; then
  echo "Running $TOFU_BIN plan -var-file=$VAR_FILE" >&2
  "$TOFU_BIN" plan "-var-file=$VAR_FILE"
else
  printf '\nImports complete. Review drift before applying:\n' >&2
  print_shell_cmd "$TOFU_BIN" plan "-var-file=$VAR_FILE"
fi
