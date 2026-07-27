resource "null_resource" "empty_r2_on_destroy" {
  depends_on = [cloudflare_r2_bucket.uploads]

  triggers = {
    account_id  = var.account_id
    bucket_name = cloudflare_r2_bucket.uploads.name
    api_token   = var.cloudflare_api_token
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      python3 -c "
import urllib.request, urllib.error, json, sys

account_id  = '${self.triggers.account_id}'
bucket_name = '${self.triggers.bucket_name}'
token       = '${self.triggers.api_token}'
base        = f'https://api.cloudflare.com/client/v4/accounts/{account_id}/r2/buckets/{bucket_name}'
headers     = {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}

def api(method, path='', body=None):
    req = urllib.request.Request(base + path, method=method,
          data=json.dumps(body).encode() if body else None, headers=headers)
    try:
        return json.loads(urllib.request.urlopen(req).read())
    except urllib.error.HTTPError as e:
        return json.loads(e.read())

resp = api('GET', '/objects')
objects = resp.get('result', []) if isinstance(resp.get('result'), list) else []
print(f'Emptying R2 bucket: {bucket_name} ({len(objects)} objects)')
for obj in objects:
    key = obj['key']
    api('DELETE', f'/objects/{urllib.request.quote(key, safe=\"\")}')
    print(f'  deleted: {key}')
print('Done.')
"
    EOT
  }
}

resource "null_resource" "d1_schema" {
  depends_on = [cloudflare_d1_database.products]

  triggers = {
    schema_hash = filemd5("${path.module}/db/schema.sql")
    database_id = cloudflare_d1_database.products.id
  }

  provisioner "local-exec" {
    command = "wrangler d1 execute demo-products --file=${path.module}/db/schema.sql --remote"
    environment = {
      CLOUDFLARE_API_TOKEN  = var.cloudflare_api_token
      CLOUDFLARE_ACCOUNT_ID = var.account_id
    }
  }
}
