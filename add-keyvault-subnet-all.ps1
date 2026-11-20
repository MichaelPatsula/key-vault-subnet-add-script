<#
.SYNOPSIS
    Runs add-keyvault-subnet.ps1 against every key vault in the current subscription, or only those in one resource group.

.DESCRIPTION
    Requires the Azure CLI (az), logged in with `az login`.
    The current subscription is used (change it with `az account set`).

.EXAMPLE
    ./add-keyvault-subnet-all.ps1 -ReferenceSubnet <ref-id> -NewSubnet <new-id> [-ResourceGroup my-rg] [-DryRun]
#>
param(
    [string]$ResourceGroup = '',
    [Parameter(Mandatory = $true)][string]$ReferenceSubnet,
    [Parameter(Mandatory = $true)][string]$NewSubnet,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$singleScript = Join-Path $PSScriptRoot 'add-keyvault-subnet.ps1'

# Shared helper functions (Test-SubnetId).
. (Join-Path $PSScriptRoot 'keyvault-subnet-lib.ps1')

# Check the subnet IDs first, so a typo fails before any vault is changed.
if (-not (Test-SubnetId $ReferenceSubnet)) {
    [Console]::Error.WriteLine("Error: -ReferenceSubnet is not a valid subnet resource ID: $ReferenceSubnet")
    exit 1
}

if (-not (Test-SubnetId $NewSubnet)) {
    [Console]::Error.WriteLine("Error: -NewSubnet is not a valid subnet resource ID: $NewSubnet")
    exit 1
}

if (-not (Test-Path $singleScript)) {
    [Console]::Error.WriteLine("Error: $singleScript not found.")
    exit 1
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    [Console]::Error.WriteLine('Error: Azure CLI (az) is not installed.')
    exit 1
}

$null = & az account show 2>$null
if ($LASTEXITCODE -ne 0) {
    [Console]::Error.WriteLine("Error: not logged in to Azure. Run 'az login' first.")
    exit 1
}

# List every key vault as "name<TAB>resourceGroup".
$listArgs = @('keyvault', 'list', '--query', '[].[name, resourceGroup]', '-o', 'tsv')
if ($ResourceGroup -ne '') {
    $listArgs += @('--resource-group', $ResourceGroup)
}

$errFile = [System.IO.Path]::GetTempFileName()
try {
    $vaults = & az @listArgs 2>$errFile
    if ($LASTEXITCODE -ne 0) {
        [Console]::Error.WriteLine('Error: could not list key vaults. Azure CLI output:')
        Get-Content $errFile | ForEach-Object { [Console]::Error.WriteLine($_) }
        exit 1
    }

    # Show any warnings from a successful call.
    Get-Content $errFile | ForEach-Object { [Console]::Error.WriteLine($_) }
}
finally {
    Remove-Item -Path $errFile -Force -ErrorAction SilentlyContinue
}

$total = 0
$added = 0
$wouldAdd = 0
$skipped = 0
$failed = 0

# A failure on one vault does not stop the others; it is counted and reported at the end.
foreach ($line in @($vaults)) {
    if (-not $line -or $line.Trim() -eq '') { continue }

    $parts = $line -split "`t"
    $name = $parts[0].Trim()
    $rg = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '' }

    $total++
    Write-Output "==> $name (resource group: $rg)"

    $childArgs = @{
        ResourceGroup    = $rg
        KeyVault         = $name
        ReferenceSubnet  = $ReferenceSubnet
        NewSubnet        = $NewSubnet
    }
    if ($DryRun) {
        $childArgs['DryRun'] = $true
    }

    # The single-vault script prints its own explanation on stderr before it exits.
    & $singleScript @childArgs
    $rc = $LASTEXITCODE

    switch ($rc) {
        0 { $added++ }
        2 { $skipped++ }
        3 { $wouldAdd++ }
        default {
            if ($rc -eq 1) {
                [Console]::Error.WriteLine("    FAILED: $name (see error above)")
            } else {
                [Console]::Error.WriteLine("    FAILED: $name (process ended unexpectedly, exit code $rc)")
            }
            $failed++
        }
    }
    Write-Output ''
}

Write-Output "Summary: $total key vault(s) processed."
Write-Output "  Added:           $added"
Write-Output "  Would add (dry): $wouldAdd"
Write-Output "  Unchanged:       $skipped"
Write-Output "  Failed:          $failed"

# Exit non-zero if any vault failed, so the result can be checked by other tools.
if ($failed -gt 0) { exit 1 }
exit 0
