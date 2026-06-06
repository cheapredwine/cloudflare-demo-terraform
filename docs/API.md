# API Documentation

Complete API reference for the demo platform.

## Base URL
```
https://api.your-domain.com
```

## Authentication

Most endpoints are open for demo purposes. Admin endpoints require basic auth.

### Session-based Auth (Demo)
```bash
# Login
POST /auth/login
{
  "email": "user@example.com", 
  "password": "any-password"
}

# Use session token
Authorization: Bearer <session-id>
```

## Products API

### List Products
```http
GET /products
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

### Get Product
```http
GET /products/{id}
```

### Create Product  
```http
POST /products
Content-Type: application/json

{
  "name": "Product Name",
  "description": "Product description", 
  "price": 29.99,
  "category": "electronics",
  "stock": 100
}
```

### Update Product
```http
PUT /products/{id}
Content-Type: application/json

{
  "price": 24.99,
  "stock": 75
}
```

### Delete Product
```http
DELETE /products/{id}
```

### Seed Sample Data
```http
POST /products/seed
```

## Orders API

### Create Order
```http
POST /orders
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

## File Upload API

### Upload File
```http
POST /upload
Content-Type: multipart/form-data

curl -F "file=@image.jpg" https://api.your-domain.com/upload
```

**Response:**
```json
{
  "filename": "550e8400-e29b-41d4-a716-446655440000-image.jpg",
  "size": 245760,
  "type": "image/jpeg",
  "url": "https://uploads.your-domain.com/550e8400-e29b-41d4-a716-446655440000-image.jpg"
}
```

## Authentication API

### Login
```http
POST /auth/login
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
    "id": "user-550e8400-e29b-41d4-a716-446655440000",
    "email": "user@example.com"
  },
  "expires_at": "2024-06-06T20:51:57Z"
}
```

### Get Current User
```http
GET /auth/me
Authorization: Bearer <session-id>
```

## Error Responses

All endpoints return consistent error formats:

```json
{
  "error": "Error description",
  "message": "Detailed error message",
  "timestamp": "2024-06-05T20:51:57Z"
}
```

**HTTP Status Codes:**
- `200` - Success
- `201` - Created
- `400` - Bad Request
- `401` - Unauthorized  
- `404` - Not Found
- `405` - Method Not Allowed
- `429` - Rate Limited
- `500` - Internal Server Error

## Rate Limits

- **API Endpoints**: 100 requests/minute per IP
- **File Uploads**: 10 uploads/minute per IP
- **Admin Endpoints**: 20 requests/minute per IP

Rate limit headers included in responses:
```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1717624317
```

## Caching

- **Product Lists**: Cached for 10 minutes
- **Individual Products**: Cached for 5 minutes  
- **Static Assets**: Cached for 24 hours

Cache headers:
```
X-Cache: HIT|MISS
Cache-Control: public, max-age=600
```