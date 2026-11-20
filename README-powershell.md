# Key Vault Subnet Scripts (PowerShell)

PowerShell scripts that add a new subnet to a key vault's virtual network rules, but only when a reference subnet is already allowed.

These are the PowerShell versions of the Bash scripts described in [readme.md](./readme.md). They behave the same way and use the same exit codes.

## Scripts

| Script | Purpose |
| --- | --- |
| `add-keyvault-subnet.ps1` | Processes one key vault (`-ResourceGroup` and `-KeyVault`). |
| `add-keyvault-subnet-all.ps1` | Runs `add-keyvault-subnet.ps1` for every key vault in the current subscription, or in one resource group if `-ResourceGroup` is given. |
| `add-keyvault-subnet-subs.ps1` | Runs `add-keyvault-subnet-all.ps1` for every subscription listed in a CSV file. |
| `keyvault-subnet-lib.ps1` | Shared helper (subnet ID check). Dot-sourced by all scripts, not run directly. Keep it in the same folder as the scripts. |

## Prerequisites

- [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) (`pwsh`). The scripts were tested on PowerShell 7.4. Windows PowerShell 5.1 has not been tested.
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (`az`)
- Logged in: `az login`
- The correct subscription selected: `az account set --subscription <name-or-id>`
- The new subnet has the `Microsoft.KeyVault` service endpoint enabled.

On Windows, if PowerShell refuses to run the scripts with an execution policy error, allow local scripts for your user:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

## Usage

Run the scripts from this folder, or give the full path to the script. On macOS and Linux, use `pwsh ./script.ps1` or `./script.ps1` if the file is executable. On Windows, use `.\script.ps1`.

Each script has built-in help:

```powershell
Get-Help ./add-keyvault-subnet.ps1 -Full
```

### Single key vault

```powershell
./add-keyvault-subnet.ps1 `
  -ResourceGroup <resource-group> `
  -KeyVault <key-vault> `
  -ReferenceSubnet <reference-subnet-id> `
  -NewSubnet <new-subnet-id> `
  [-DryRun]
```

| Parameter | Description |
| --- | --- |
| `-ResourceGroup` | Resource group of the key vault (required) |
| `-KeyVault` | Key vault name (required) |
| `-ReferenceSubnet` | Full resource ID of the subnet that must already be allowed (required) |
| `-NewSubnet` | Full resource ID of the subnet to add (required) |
| `-DryRun` | Dry run: report what would happen without changing anything |

### All key vaults in the subscription

```powershell
./add-keyvault-subnet-all.ps1 `
  -ReferenceSubnet <reference-subnet-id> `
  -NewSubnet <new-subnet-id> `
  [-ResourceGroup <resource-group>] `
  [-DryRun]
```

| Parameter | Description |
| --- | --- |
| `-ReferenceSubnet` | Full resource ID of the subnet that must already be allowed (required) |
| `-NewSubnet` | Full resource ID of the subnet to add (required) |
| `-ResourceGroup` | Optional: only process key vaults in this resource group |
| `-DryRun` | Dry run, passed through to `add-keyvault-subnet.ps1` |

### Multiple subscriptions from a CSV file

```powershell
./add-keyvault-subnet-subs.ps1 `
  -CsvFile <subscriptions.csv> `
  -ReferenceSubnet <reference-subnet-id> `
  -NewSubnet <new-subnet-id> `
  [-ResourceGroup <resource-group>] `
  [-DryRun]
```

| Parameter | Description |
| --- | --- |
| `-CsvFile` | CSV file listing the subscriptions to process (required) |
| `-ReferenceSubnet` | Full resource ID of the subnet that must already be allowed (required) |
| `-NewSubnet` | Full resource ID of the subnet to add (required) |
| `-ResourceGroup` | Optional: only process key vaults in this resource group, in every subscription |
| `-DryRun` | Dry run, passed through to `add-keyvault-subnet-all.ps1` |

The CSV has one subscription per line, as a name or ID. The `subscription` header line is optional. Blank lines and lines starting with `#` are ignored. Lines with more than one field are rejected before any subscription is changed.

```csv
subscription
my-dev-sub
00000000-0000-0000-0000-000000000000
# comments are ignored
```

The reference and new subnet IDs are the same for every subscription. The script switches to each subscription in turn and restores the original subscription when it exits.

### Subnet ID format

```text
/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Network/virtualNetworks/<vnet-name>/subnets/<subnet-name>
```

## Behavior

For each key vault, the script:

1. Reads the subnets currently allowed by the vault's virtual network rules.
2. If the reference subnet is not allowed, makes no changes.
3. If the new subnet is already allowed, makes no changes.
4. Otherwise, adds the new subnet (or only reports it, with `-DryRun`).

Subnet IDs are compared case-insensitively. Only full resource IDs are matched; subnet names are not.

The scripts only add rules. They never remove or change existing network rules or the vault's default action.

## Output and exit codes

The single-vault script exits with:

| Code | Meaning |
| --- | --- |
| `0` | Subnet added |
| `1` | Error (explained on stderr) |
| `2` | No change made: reference subnet not allowed, or new subnet already allowed |
| `3` | Dry run: subnet would be added |

The batch script continues past failures. At the end it prints a summary:

```text
Summary: 12 key vault(s) processed.
  Added:           2
  Would add (dry): 0
  Unchanged:       9
  Failed:          1
```

It exits with `1` if any key vault failed, and `0` otherwise. The subscriptions script exits with `1` if any subscription had failures.

## Errors

- Invalid subnet IDs are rejected before any key vault is changed.
- Azure CLI errors are printed with the step that failed, followed by the raw Azure CLI output. Read the Azure message for the cause.
- A missing required parameter causes PowerShell to prompt for it in an interactive session. In a non-interactive run, the script fails instead.

## Examples

Dry run across the whole subscription:

```powershell
./add-keyvault-subnet-all.ps1 -ReferenceSubnet $RefSubnetId -NewSubnet $NewSubnetId -DryRun
```

Apply to one resource group:

```powershell
./add-keyvault-subnet-all.ps1 -ReferenceSubnet $RefSubnetId -NewSubnet $NewSubnetId -ResourceGroup my-rg
```

## Notes

- Run a dry run (`-DryRun`) first to confirm the key vaults and subnets that will change.
- Keep `keyvault-subnet-lib.ps1` next to the scripts. Copying only the scripts will fail.
- `add-keyvault-subnet.ps1` and `add-keyvault-subnet-all.ps1` use the currently selected Azure subscription. `add-keyvault-subnet-subs.ps1` switches subscriptions from its CSV file and restores the original one on exit.
- Managed HSMs are not covered; only standard key vaults (`az keyvault`) are processed.
