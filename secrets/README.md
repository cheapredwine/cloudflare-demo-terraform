# secrets/

Real secrets live here. Everything in this folder is gitignored except this
README and the `*.example` stubs.

| File | Becomes | Used by |
|---|---|---|
| `cloudflare_api_token` | `CLOUDFLARE_API_TOKEN` | Terraform provider, wrangler (D1 schema), R2 cleanup |
| `admin_password` | `TF_VAR_admin_password` | admin panel Worker secret (12+ characters) |

Copy each `.example` file without the suffix, put the real value on one line,
and `chmod 600` it. The scripts under `scripts/` load these through
`scripts/lib/env.sh` (or `env.ps1`) only when the variable isn't already set
in your shell. Running plain `terraform` yourself? Export the variables first:

```bash
export CLOUDFLARE_API_TOKEN=$(cat secrets/cloudflare_api_token)
export TF_VAR_admin_password=$(cat secrets/admin_password)
```
