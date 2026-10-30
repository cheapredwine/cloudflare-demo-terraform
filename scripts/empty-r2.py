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
import urllib.request
import urllib.parse

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
    try:
        return json.loads(urllib.request.urlopen(req).read())
    except urllib.error.HTTPError as e:
        try:
            return json.loads(e.read())
        except Exception:
            return {}


def main():
    resp = api("GET", "/objects")
    objects = resp.get("result", []) if isinstance(resp.get("result"), list) else []
    print(f"Emptying R2 bucket: {bucket_name} ({len(objects)} objects)")
    failed = False
    for obj in objects:
        key = obj["key"]
        out = api("DELETE", f"/objects/{urllib.parse.quote(key, safe='')}")
        if out.get("success") is False:
            failed = True
            print(f"  FAILED: {key}", file=sys.stderr)
        else:
            print(f"  deleted: {key}")
    if failed:
        sys.exit(1)
    print("Done.")


if __name__ == "__main__":
    main()
