# OCI Always Free ARM VM OpenTofu module

This OpenTofu module provisions an Oracle Cloud Infrastructure Always Free ARM VM using the current A1 limits documented for Always Free tenancies:

- Shape: `VM.Standard.A1.Flex`
- OCPUs: `2`
- Memory: `12 GB`
- Boot volume: `200 GB`
- No attached block volumes
- Latest matching Oracle Linux image for the selected major version, defaulting to Oracle Linux 9
- Oracle Cloud Agent management, monitoring, and common plugins disabled
- Tailscale installed and joined via cloud-init using Tailscale's official install script
- Optional cloud-init-created sudo default user, enabled by default
- No public SSH ingress rule
- UDP `41641` opened for Tailscale direct WireGuard connections
- Monthly budget alert to `example@gmail.com` by default when actual cost reaches `$0.01`

The module also creates one small public VCN, subnet, internet gateway, route table, and security list for Tailscale connectivity. The budget alert is a guardrail only; it does not prevent charges.

> OCI Always Free compute and block volume resources must be created in the tenancy home region. Availability can also be capacity constrained by region and availability domain, so OpenTofu may fail with an OCI capacity error even though the configuration is within Always Free limits.

## Usage

Copy the example variables file and replace the placeholders:

```sh
cp main.tfvars.example main.tfvars
```

At minimum, set these values in `main.tfvars`:

```hcl
region             = "us-ashburn-1"
compartment_id     = "ocid1.compartment.oc1..replace_me"
ssh_public_key     = "ssh-ed25519 AAAA... your-key"
tailscale_auth_key = "tskey-auth-..."
default_user       = "admin"

budget_alert_email = "example@gmail.com"
```

Then run:

```sh
tofu init
tofu plan -var-file=main.tfvars
tofu apply -var-file=main.tfvars
```

## OCI authentication

The OCI provider can use your standard OCI CLI config from `~/.oci/config`, environment variables, or instance/resource principals. This module only sets the provider `region`; it does not hardcode credentials.

## Important variables

| Variable | Default | Description |
| --- | --- | --- |
| `region` | required | OCI region to deploy into. For Always Free compute and block volume resources, this must be the tenancy home region. |
| `compartment_id` | required | Compartment OCID for all resources. |
| `ssh_public_key` | required | Public key installed for the `opc` user. No public SSH ingress is opened; this is still useful for console/emergency access. |
| `tailscale_auth_key` | required | Auth key used by cloud-init to run `tailscale up`. Prefer an ephemeral, pre-approved, reusable key scoped with tags. Stored in OpenTofu state. |
| `tailscale_hostname` | `null` | Hostname registered in Tailscale. Defaults to `name`. |
| `tailscale_enable_ssh` | `true` | Adds `--ssh` to `tailscale up` so you can use Tailscale SSH. |
| `tailscale_udp_port` | `41641` | Public UDP port opened for Tailscale direct connections. |
| `create_admin_user` | `true` | Creates a non-root sudo-capable user via cloud-init. |
| `default_user` | `admin` | Username for the sudo-capable cloud-init user. |
| `availability_domain` | `null` | Uses the first AD if omitted. Set this if your region has capacity in a specific AD. |
| `a1_ocpus` | `2` | A1 OCPUs for the instance. Validation caps this at `2` for Always Free tenancies. |
| `a1_memory_in_gbs` | `12` | A1 memory for the instance. Validation caps this at `12` GB for Always Free tenancies. |
| `oracle_linux_version` | `9` | Latest matching Oracle Linux image is selected. |
| `boot_volume_size_in_gbs` | `200` | Maximum Always Free combined boot/block volume storage used as this VM's boot disk. |
| `budget_alert_email` | `example@gmail.com` | Email recipient for the budget alert. |
| `budget_alert_threshold` | `0.01` | OCI budgets require a positive threshold, so this approximates “any cost.” |

## Tailscale notes

Cloud-init installs Tailscale with the official install script:

```yaml
runcmd:
  - ['sh', '-c', 'curl -fsSL https://tailscale.com/install.sh | sh']
  - ['sh', '-c', 'tailscale up --authkey=... --hostname=... --ssh']
```

Create the auth key in the Tailscale admin console. Because cloud-init data is part of the OCI instance metadata and OpenTofu state, treat `tailscale_auth_key` as sensitive and prefer a short-lived or ephemeral key.

## Default user notes

By default, cloud-init creates a non-root `admin` user, controlled by `default_user`, with:

- membership in `wheel`
- passwordless `sudo`
- password login locked
- the same SSH public key as `ssh_public_key`

This is safer than enabling direct root login. Oracle Linux images also include the default `opc` user, so set `create_admin_user = false` if you prefer to use only `opc`.

## Optional SeaweedFS remote state

This module defaults to local OpenTofu state. If you want self-hosted S3-compatible remote state, see:

- `backend-seaweedfs.tf.example`
- `seaweedfs/docker-compose.yml`
- `seaweedfs/README.md`

The optional backend example uses SeaweedFS S3 plus OpenTofu state/plan encryption with PBKDF2 + AES-GCM.

## Import existing resources

If the OCI resources already exist and you need to build state from scratch, use the import helper:

```sh
scripts/import-existing-oci.sh --var-file main.tfvars
scripts/import-existing-oci.sh --var-file main.tfvars --execute
```

The first command is a dry run. The second command discovers resources by the module's display-name convention and runs `tofu import` for each discovered resource. After importing, always review drift before applying:

```sh
tofu plan -var-file=main.tfvars
```

## Notes on Always Free limits

Reviewed Oracle documentation:

- Oracle's **Always Free Resources** page currently lists `VM.Standard.A1.Flex` for Always Free tenancies as 1,500 OCPU-hours and 9,000 GB-hours per month, equivalent to `2` OCPUs and `12 GB` memory. This module defaults to and validates against those stricter Always Free tenancy values.
- Oracle's public price list may describe a larger monthly free A1 allowance for broader account types. This module intentionally follows the stricter Always Free Resources page so an Always-Free-only tenancy remains inside the documented limits.
- This module consumes the full stricter A1 pool for an Always-Free-only tenancy. Do not run other A1 VMs, A1 bare metal instances, or A1-backed container instances in the same monthly free allowance unless you reduce `a1_ocpus` and `a1_memory_in_gbs` here.
- Always Free block volume storage is `200 GB` total for boot volumes and block volumes combined in the home region, plus five total volume backups. This module creates one boot volume, creates no attached block volumes, and creates no backups. Because the default boot volume is `200 GB`, reduce `boot_volume_size_in_gbs` if other boot or block volumes need to stay within the same free storage pool.
- Free Tier tenancies can have up to `2` VCNs. This module creates `1` VCN with one subnet, route table, internet gateway, and security list.
- OCI includes `10 TB` per month of outbound data transfer. Terraform cannot cap network egress, so workloads on the VM still need to stay below that usage.
- The module does not create load balancers, NAT gateways, reserved public IPs, object storage, databases, volume backups, or any paid compute shapes.
