# Key Vault Subnet Scripts

Bash scripts that add a new subnet to a key vault's virtual network rules, but only when a reference subnet is already allowed.

## Scripts

| Script | Purpose |
| --- | --- |
| `add-keyvault-subnet.sh` | Processes one key vault (`-g` and `-k`). |
| `add-keyvault-subnet-all.sh` | Runs `add-keyvault-subnet.sh` for every key vault in the current subscription, or in one resource group if `-g` is given. |
| `add-keyvault-subnet-subs.sh` | Runs `add-keyvault-subnet-all.sh` for every subscription listed in a CSV file. |
| `keyvault-subnet-lib.sh` | Shared helper (subnet ID check). Sourced by all scripts, not run directly. Keep it in the same folder as the scripts. |

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (`az`)
- Logged in: `az login`
- The correct subscription selected: `az account set --subscription <name-or-id>`
- The new subnet has the `Microsoft.KeyVault` service endpoint enabled.

## Usage

### Single key vault

```bash
./add-keyvault-subnet.sh \
  -g <resource-group> \
  -k <key-vault> \
  -r <reference-subnet-id> \
  -n <new-subnet-id> \
  [-d]
```

| Option | Description |
| --- | --- |
| `-g` | Resource group of the key vault (required) |
| `-k` | Key vault name (required) |
| `-r` | Full resource ID of the subnet that must already be allowed (required) |
| `-n` | Full resource ID of the subnet to add (required) |
| `-d` | Dry run: report what would happen without changing anything |
| `-h` | Show help |

### All key vaults in the subscription

```bash
./add-keyvault-subnet-all.sh \
  -r <reference-subnet-id> \
  -n <new-subnet-id> \
  [-g <resource-group>] \
  [-d]
```

| Option | Description |
| --- | --- |
| `-r` | Full resource ID of the subnet that must already be allowed (required) |
| `-n` | Full resource ID of the subnet to add (required) |
| `-g` | Optional: only process key vaults in this resource group |
| `-d` | Dry run, passed through to `add-keyvault-subnet.sh` |
| `-h` | Show help |

### Multiple subscriptions from a CSV file

```bash
./add-keyvault-subnet-subs.sh \
  -f <subscriptions.csv> \
  -r <reference-subnet-id> \
  -n <new-subnet-id> \
  [-g <resource-group>] \
  [-d]
```

| Option | Description |
| --- | --- |
| `-f` | CSV file listing the subscriptions to process (required) |
| `-r` | Full resource ID of the subnet that must already be allowed (required) |
| `-n` | Full resource ID of the subnet to add (required) |
| `-g` | Optional: only process key vaults in this resource group, in every subscription |
| `-d` | Dry run, passed through to `add-keyvault-subnet-all.sh` |
| `-h` | Show help |

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
4. Otherwise, adds the new subnet (or only reports it, with `-d`).

Subnet IDs are compared case-insensitively. Only full resource IDs are matched; subnet names are not.

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

It exits with `1` if any key vault failed, and `0` otherwise.

## Errors

- Invalid subnet IDs are rejected before any key vault is changed.
- Azure CLI errors are printed with the step that failed, followed by the raw Azure CLI output. Read the Azure message for the cause.
- `-h` shows help and exits with `0`. Invalid arguments exit with `1`.

## Examples

Dry run across the whole subscription:

```bash
./add-keyvault-subnet-all.sh -r "$REF_SUBNET_ID" -n "$NEW_SUBNET_ID" -d
```

Apply to one resource group:

```bash
./add-keyvault-subnet-all.sh -r "$REF_SUBNET_ID" -n "$NEW_SUBNET_ID" -g my-rg
```

## Notes

- Run a dry run (`-d`) first to confirm the key vaults and subnets that will change.
- Keep `keyvault-subnet-lib.sh` next to the scripts. Copying only the two scripts will fail.
- `add-keyvault-subnet.sh` and `add-keyvault-subnet-all.sh` use the currently selected Azure subscription. `add-keyvault-subnet-subs.sh` switches subscriptions from its CSV file and restores the original one on exit.
- Managed HSMs are not covered; only standard key vaults (`az keyvault`) are processed.
# key-vault-subnet-add-script
