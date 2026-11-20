<#
.SYNOPSIS
    Adds a subnet to a key vault's virtual network rules, but only when a reference subnet is already allowed by those rules.

.DESCRIPTION
    Requires the Azure CLI (az), logged in with `az login`.
    The new subnet must have the Microsoft.KeyVault service endpoint enabled.

    Exit codes:
      0  subnet added
      1  error (explained on stderr)
      2  no change made (reference subnet not allowed, or new subnet already allowed)
      3  dry run: subnet would be added

.EXAMPLE
    ./add-keyvault-subnet.ps1 -ResourceGroup my-rg -KeyVault my-vault `
        -ReferenceSubnet <reference-subnet-id> -NewSubnet <new-subnet-id> -DryRun
#>
param(
    [Parameter(Mandatory = $true)][string]$ResourceGroup,
    [Parameter(Mandatory = $true)][string]$KeyVault,
    [Parameter(Mandatory = $true)][string]$ReferenceSubnet,
    [Parameter(Mandatory = $true)][string]$NewSubnet,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Shared helper functions (Test-SubnetId).
. (Join-Path $PSScriptRoot 'keyvault-subnet-lib.ps1')

# Make sure the Azure CLI is installed.
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    [Console]::Error.WriteLine('Error: Azure CLI (az) is not installed.')
    exit 1
}

# Make sure there is an active Azure login.
$null = & az account show 2>$null
if ($LASTEXITCODE -ne 0) {
    [Console]::Error.WriteLine("Error: not logged in to Azure. Run 'az login' first.")
    exit 1
}

# Check the subnet IDs before any vault is read or changed, so a typo fails early.
if (-not (Test-SubnetId $ReferenceSubnet)) {
    [Console]::Error.WriteLine("Error: -ReferenceSubnet is not a valid subnet resource ID: $ReferenceSubnet")
    exit 1
}

if (-not (Test-SubnetId $NewSubnet)) {
    [Console]::Error.WriteLine("Error: -NewSubnet is not a valid subnet resource ID: $NewSubnet")
    exit 1
}

Write-Output "Reading network rules for key vault '$KeyVault' in '$ResourceGroup'..."

# Azure CLI errors go to a temp file so they can be shown if the call fails.
$errFile = [System.IO.Path]::GetTempFileName()
try {
    # Fetch the IDs of all subnets currently allowed by the vault's virtual network rules, one per line.
    $existing = & az keyvault network-rule list `
        --name $KeyVault `
        --resource-group $ResourceGroup `
        --query "virtualNetworkRules[].id" `
        -o tsv 2>$errFile
    if ($LASTEXITCODE -ne 0) {
        [Console]::Error.WriteLine("Error: could not read network rules for '$KeyVault' in '$ResourceGroup'. Azure CLI output:")
        Get-Content $errFile | ForEach-Object { [Console]::Error.WriteLine($_) }
        exit 1
    }

    # Azure resource IDs are case-insensitive, so compare with -eq (PowerShell string comparison is case-insensitive by default).
    $existingIds = @($existing | Where-Object { $_ -and $_.Trim() -ne '' } | ForEach-Object { $_.Trim() })

    # REF_FOUND: the reference subnet must already be in the vault's rules, otherwise nothing changes.
    # NEW_FOUND: if the new subnet is already in the rules, it is already allowed and nothing is added.
    $refFound = $existingIds -contains $ReferenceSubnet
    $newFound = $existingIds -contains $NewSubnet

    if (-not $refFound) {
        Write-Output "Reference subnet is not allowed on '$KeyVault'. No changes made."
        exit 2
    }

    Write-Output 'Reference subnet is allowed.'

    if ($newFound) {
        Write-Output "New subnet is already allowed on '$KeyVault'. No changes made."
        exit 2
    }

    # In dry-run mode, stop before making any change.
    if ($DryRun) {
        Write-Output "[dry run] Would add subnet: $NewSubnet"
        exit 3
    }

    # Add the new subnet to the key vault's network rules.
    Write-Output "Adding subnet: $NewSubnet"
    # Suppress the CLI's JSON output; errors are captured so they can be reported.
    $addOutput = & az keyvault network-rule add `
        --name $KeyVault `
        --resource-group $ResourceGroup `
        --subnet $NewSubnet `
        -o none 2>&1
    if ($LASTEXITCODE -ne 0) {
        [Console]::Error.WriteLine("Error: could not add subnet to '$KeyVault' in '$ResourceGroup'. Azure CLI output:")
        $addOutput | ForEach-Object { [Console]::Error.WriteLine($_) }
        exit 1
    }

    Write-Output "Done. Subnet added to '$KeyVault'."
    exit 0
}
finally {
    Remove-Item -Path $errFile -Force -ErrorAction SilentlyContinue
}
