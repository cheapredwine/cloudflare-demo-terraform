#!/usr/bin/env python3
"""Empty an R2 bucket via the Cloudflare API (for destroy-time cleanup).

Env vars: CF_ACCOUNT_ID, CF_BUCKET, CLOUDFLARE_API_TOKEN.
Used by migrations.tf terraform_data.r2_cleanup's destroy-time provisioner,
because the Cloudflare API refuses to delete non-empty R2 buckets.
"""

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

account_id = os.environ["CF_ACCOUNT_ID"]
bucket_name = os.environ["CF_BUCKET"]
token = os.environ["CLOUDFLARE_API_TOKEN"]
base = f"https://api.cloudflare.com/client/v4/accounts/{account_id}/r2/buckets/{bucket_name}"
headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}


def api(method, path="", body=None):
    req = urllib.request.Request(
        base + path,
        method=method,
        data=json.dumps(body).encode() if body else None,
        headers=headers,
    )
    # A timeout or network error returns {}, which main() treats as a failure
    # (exit 1), so a hung request can't stall `terraform destroy` forever.
    try:
        return json.loads(urllib.request.urlopen(req, timeout=30).read())
    except urllib.error.HTTPError as e:
        try:
            return json.loads(e.read())
        except (ValueError, OSError):
            return {}
    except (urllib.error.URLError, TimeoutError, ValueError):
        return {}


def main():
    # Listing returns one page at a time. Delete that page, then list again
    # from the start until the bucket is empty; a failed list or delete
    # exits nonzero so Terraform stops before trying to delete the bucket.
    total = 0
    while True:
        resp = api("GET", "/objects?per_page=1000")
        if resp.get("success") is not True:
            print(
                f"FAILED to list objects in {bucket_name}: {resp.get('errors')}",
                file=sys.stderr,
            )
            sys.exit(1)
        objects = resp.get("result") or []
        if not objects:
            break
        for obj in objects:
            key = obj["key"]
            out = api("DELETE", f"/objects/{urllib.parse.quote(key, safe='')}")
            if out.get("success") is not True:
                print(f"FAILED to delete {key}: {out.get('errors')}", file=sys.stderr)
                sys.exit(1)
            total += 1
    print(f"Emptied R2 bucket {bucket_name} ({total} objects deleted)")


if __name__ == "__main__":
    main()
