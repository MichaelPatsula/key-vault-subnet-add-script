# Shared helper functions for add-keyvault-subnet.ps1, add-keyvault-subnet-all.ps1 and
# add-keyvault-subnet-subs.ps1.
# Dot-sourced by these scripts; do not run directly.

# Check that a value is a full subnet resource ID (case-insensitive).
function Test-SubnetId([string]$Id) {
    return $Id -match '^/subscriptions/[^/]+/resourcegroups/[^/]+/providers/microsoft\.network/virtualnetworks/[^/]+/subnets/[^/]+$'
}
