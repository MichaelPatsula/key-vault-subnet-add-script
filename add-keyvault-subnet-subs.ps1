<#
.SYNOPSIS
    Runs add-keyvault-subnet-all.ps1 for every subscription listed in a CSV file.

.DESCRIPTION
    CSV format: one subscription per line, name or ID. A header line "subscription" is optional.
    Blank lines and lines starting with # are ignored.

        subscription
        my-dev-sub
        00000000-0000-0000-0000-000000000000

    Requires the Azure CLI (az), logged in with `az login`.
    The original subscription is restored when the script exits.

.EXAMPLE
    ./add-keyvault-subnet-subs.ps1 -CsvFile subscriptions.csv -ReferenceSubnet <ref-id> -NewSubnet <new-id> [-ResourceGroup my-rg] [-DryRun]
#>
param(
    [Parameter(Mandatory = $true)][string]$CsvFile,
    [Parameter(Mandatory = $true)][string]$ReferenceSubnet,
    [Parameter(Mandatory = $true)][string]$NewSubnet,
    [string]$ResourceGroup = '',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$allScript = Join-Path $PSScriptRoot 'add-keyvault-subnet-all.ps1'

# Shared helper functions (Test-SubnetId).
. (Join-Path $PSScriptRoot 'keyvault-subnet-lib.ps1')

if (-not (Test-Path $CsvFile -PathType Leaf)) {
    [Console]::Error.WriteLine("Error: subscriptions file not found: $CsvFile")
    exit 1
}

# Check the subnet IDs first, so a typo fails before any subscription is changed.
if (-not (Test-SubnetId $ReferenceSubnet)) {
    [Console]::Error.WriteLine("Error: -ReferenceSubnet is not a valid subnet resource ID: $ReferenceSubnet")
    exit 1
}

if (-not (Test-SubnetId $NewSubnet)) {
    [Console]::Error.WriteLine("Error: -NewSubnet is not a valid subnet resource ID: $NewSubnet")
    exit 1
}

if (-not (Test-Path $allScript)) {
    [Console]::Error.WriteLine("Error: $allScript not found.")
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

# Read the whole CSV before changing anything, so a bad row fails early.
$subs = @()
$badRows = 0
$lineNo = 0
$headerChecked = $false

foreach ($raw in Get-Content $CsvFile) {
    $lineNo++

    # Strip comments and surrounding whitespace.
    $line = ($raw -replace '#.*$', '').Trim()
    if ($line -eq '') { continue }

    # Skip the optional header on the first non-blank line.
    if (-not $headerChecked) {
        $headerChecked = $true
        if ($line -eq 'subscription') { continue }
    }

    # One subscription per row, so a comma means the row has the wrong shape.
    if ($line -like '*,*') {
        [Console]::Error.WriteLine("Error: line $lineNo has more than one field: $line")
        $badRows++
    } else {
        $subs += $line
    }
}

if ($badRows -gt 0) {
    [Console]::Error.WriteLine("Error: $badRows invalid line(s) in $CsvFile. No changes made.")
    exit 1
}

if ($subs.Count -eq 0) {
    [Console]::Error.WriteLine("Error: no subscriptions found in $CsvFile.")
    exit 1
}

# Remember the current subscription and restore it when the script exits.
$origSub = & az account show --query id -o tsv

$total = 0
$failed = 0

try {
    # A failure in one subscription does not stop the others; it is counted and reported at the end.
    foreach ($sub in $subs) {
        $total++
        Write-Output "##### Subscription $total of $($subs.Count): $sub"

        & az account set --subscription $sub
        if ($LASTEXITCODE -ne 0) {
            [Console]::Error.WriteLine("Error: cannot select subscription '$sub'.")
            $failed++
            Write-Output ''
            continue
        }

        $childArgs = @{
            ReferenceSubnet = $ReferenceSubnet
            NewSubnet       = $NewSubnet
        }
        if ($ResourceGroup -ne '') {
            $childArgs['ResourceGroup'] = $ResourceGroup
        }
        if ($DryRun) {
            $childArgs['DryRun'] = $true
        }

        & $allScript @childArgs
        if ($LASTEXITCODE -ne 0) {
            [Console]::Error.WriteLine("    Subscription '$sub' had failures.")
            $failed++
        }
        Write-Output ''
    }
}
finally {
    if ($origSub) {
        & az account set --subscription $origSub *> $null
    }
}

Write-Output "Summary: $total subscription(s) processed."
Write-Output "  With failures: $failed"

# Exit non-zero if any subscription had failures, so the result can be checked by other tools.
if ($failed -gt 0) { exit 1 }
exit 0
