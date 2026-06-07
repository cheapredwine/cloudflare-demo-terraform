# API Documentation

Complete API reference for the Cloudflare Demo Platform.

## Base URL

```
https://api.jsherron.com
```

All routes are prefixed with `/api/`.

## Authentication

Two independent auth systems exist:

| System | Where | How |
|--------|-------|-----|
| Session auth | `api.jsherron.com` | Login to get a UUID session token, pass as Bearer |
| Admin basic auth | `admin.jsherron.com` | HTTP Basic — `admin` / `demo123` |

### Login
```http
POST /api/auth/login
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "any-password"
}
```

**Response:**
```json
{
  "session_id": "550e8400-e29b-41d4-a716-446655440000",
  "user": {
    "id": "user-uuid",
    "email": "user@example.com"
  },
  "expires_at": "2024-06-06T20:51:57Z"
}
```

Session tokens are UUID strings stored as JSON in KV with a 24-hour TTL. They are not JWTs.

### Get Current User
```http
GET /api/auth/me
Authorization: Bearer <session-id>
```

---

## Products API

Products are stored in D1. List responses are cached in KV for 10 minutes (`X-Products-Cache: HIT/MISS`). Individual product lookups query D1 directly (no cache).

### List Products
```http
GET /api/products
```

**Response:**
```json
{
  "products": [
    {
      "id": 1,
      "name": "Premium Coffee Beans",
      "description": "Single-origin coffee from Colombian highlands",
      "price": 24.99,
      "category": "beverages",
      "stock": 50,
      "created_at": "2024-06-05T10:00:00Z",
      "updated_at": "2024-06-05T10:00:00Z"
    }
  ],
  "count": 1,
  "timestamp": "2024-06-05T20:51:57Z"
}
```

Cache header on response:
```
X-Products-Cache: HIT
```

### Get Product
```http
GET /api/products/{id}
```

### Create Product
```http
POST /api/products
Content-Type: application/json

{
  "name": "Product Name",
  "description": "Product description",
  "price": 29.99,
  "category": "electronics",
  "stock": 100
}
```

Returns `201 Created` with the new product object including its `id`.

### Update Product
```http
PUT /api/products/{id}
Content-Type: application/json

{
  "price": 24.99,
  "stock": 75
}
```

All fields are optional — only provided fields are updated.

### Delete Product
```http
DELETE /api/products/{id}
```

### Seed Sample Data
Inserts 5 sample products (Coffee Beans, Wireless Headphones, Cotton T-Shirt, Water Bottle, Chocolate Box). Clears KV cache after insert.

```http
POST /api/products/seed
```

**Response:**
```json
{
  "message": "Seeded 5 products",
  "timestamp": "2024-06-05T20:51:57Z"
}
```

---

## Orders API

Orders are sent to a Cloudflare Queue for async processing. The queue consumer worker (`demo-order-processor`) writes them to D1 and decrements stock.

### Create Order
```http
POST /api/orders
Content-Type: application/json

{
  "customer_id": "cust_123",
  "items": [
    {
      "product_id": 1,
      "quantity": 2,
      "unit_price": 24.99
    }
  ],
  "total": 49.98
}
```

**Response:**
```json
{
  "order_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "queued",
  "message": "Order received and queued for processing"
}
```

The order is processed asynchronously. Check the admin panel to see completed orders.

---

## File Upload API

Files are stored in R2 bucket `demo-platform-uploads`. The returned URL is a storage reference — there is no public CDN serving uploads in this demo.

### Upload File
```http
POST /api/upload
Content-Type: multipart/form-data
```

```bash
curl -X POST https://api.jsherron.com/api/upload \
  -F "file=@image.jpg"
```

**Response:**
```json
{
  "filename": "550e8400-e29b-41d4-a716-446655440000-image.jpg",
  "size": 245760,
  "type": "image/jpeg",
  "url": "https://uploads.jsherron.com/550e8400-e29b-41d4-a716-446655440000-image.jpg"
}
```

---

## Error Responses

All errors return JSON with an `error` field:

```json
{
  "error": "Not found"
}
```

Internal server errors also include a `message` field with the exception text.

**HTTP Status Codes:**
- `200` — Success
- `201` — Created
- `400` — Bad Request (missing required fields, invalid content type)
- `401` — Unauthorized (invalid or missing session token)
- `404` — Not Found
- `405` — Method Not Allowed
- `500` — Internal Server Error

There is no rate limiting implemented in this demo.

---

## Caching

| Scope | Store | TTL |
|-------|-------|-----|
| Product list (`GET /api/products`) | KV (`demo-cache`) | 10 minutes |
| Edge cache for `/api/products*` | Cloudflare Cache Rules | 5 minutes |

Cache is invalidated automatically on any product create, update, or delete.

Cache status is returned via the `X-Products-Cache` header (`HIT` or `MISS`).
