# shellcheck shell=bash
#
# Shared helpers for add-keyvault-subnet.sh, add-keyvault-subnet-all.sh and
# add-keyvault-subnet-subs.sh.
# Sourced by these scripts; do not run directly.

# Check that a value is a full subnet resource ID (case-insensitive).
is_subnet_id() {
  local lower
  lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  [[ $lower =~ ^/subscriptions/[^/]+/resourcegroups/[^/]+/providers/microsoft\.network/virtualnetworks/[^/]+/subnets/[^/]+$ ]]
}
