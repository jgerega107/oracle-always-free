# SeaweedFS S3 backend for OpenTofu state

This directory contains a simple single-container SeaweedFS setup that exposes an S3-compatible API for OpenTofu remote state.

It uses `ghcr.io/seaweedfs/seaweedfs:latest` from GitHub Container Registry.

Use this only from a trusted/private network such as Tailscale. Do not expose SeaweedFS S3 directly to the public internet.

## Start SeaweedFS

Create the S3 auth config:

```sh
cp s3.json.example s3.json
```

Edit `s3.json` and replace `replace-with-a-long-random-secret` with a long random secret.

Start SeaweedFS:

```sh
docker compose up -d
```

The S3 endpoint will be:

```text
http://127.0.0.1:8333
```

If running on another host, use that host's Tailscale DNS name or IP in `backend.tf`, for example:

```text
http://seaweedfs-host.your-tailnet.ts.net:8333
```

## Create the state bucket

Using AWS CLI:

```sh
export AWS_ACCESS_KEY_ID="tofu-state"
export AWS_SECRET_ACCESS_KEY="replace-with-the-secret-from-s3-json"

aws --endpoint-url http://127.0.0.1:8333 s3 mb s3://tofu-state
```

## Enable the backend in OpenTofu

From the module root:

```sh
cp backend-seaweedfs.tf.example backend.tf
```

Set backend credentials:

```sh
export AWS_ACCESS_KEY_ID="tofu-state"
export AWS_SECRET_ACCESS_KEY="replace-with-the-secret-from-s3-json"
```

Set the OpenTofu state encryption passphrase. Keep this backed up; encrypted state cannot be recovered without it.

```sh
export TF_VAR_state_encryption_passphrase="replace-with-a-long-passphrase-at-least-16-chars"
```

Migrate existing local state, or initialize a new remote state:

```sh
tofu init -migrate-state
```

Run a plan:

```sh
tofu plan -var-file=main.tfvars
```

## After the first successful encrypted migration

`backend-seaweedfs.tf.example` includes an `unencrypted` fallback so OpenTofu can read existing unencrypted local state during the first migration.

After a successful migration/apply, edit `backend.tf`:

1. Remove both `fallback` blocks.
2. Optionally remove `method "unencrypted" "migration" {}`.
3. Uncomment `enforced = true` in `state` and `plan`.
4. Run `tofu init` and `tofu plan` again.

## Locking

The example enables OpenTofu S3-native lockfiles:

```hcl
use_lockfile = true
```

If your SeaweedFS version rejects the required conditional object writes, remove that line and avoid running `tofu apply` concurrently from multiple machines.

## Backups

SeaweedFS stores data in the Docker volume `seaweedfs-data`. Back this up, or periodically snapshot/export the bucket contents. OpenTofu encryption protects confidentiality, not data loss.
