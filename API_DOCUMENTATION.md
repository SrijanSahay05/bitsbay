# Marketplace API Documentation

## Base URL
```
http://localhost:8000/api/
```

## Authentication
All endpoints require JWT authentication. Include the token in the Authorization header:
```
Authorization: Bearer <your_jwt_token>
```

## Endpoints Overview

### 1. List All Listings
**GET** `/listings/`

Returns all listings with pagination (8 items per page).

#### Request
```
GET /api/listings/
GET /api/listings/?page=2
```

#### Response
```json
{
    "total_pages": 4,
    "item_0": {
        "id": "1",
        "name": "John Doe",
        "title": "Programming Book",
        "description": "Great book for beginners",
        "tags": ["programming", "beginner"],
        "negotiable": true,
        "phone": "1234567890",
        "year": "1st yr"
    },
    "item_1": {
        "id": "2",
        "name": "Jane Smith",
        "title": "Math Textbook",
        "description": "Advanced calculus",
        "tags": ["math", "calculus"],
        "negotiable": false,
        "phone": "0987654321",
        "year": "2nd yr"
    }
}
```

#### Query Parameters
- `page` (optional): Page number (default: 1)

---

### 2. Get My Listings
**GET** `/listings/my-listings/`

Returns all listings created by the authenticated user.

#### Request
```
GET /api/listings/my-listings/
GET /api/listings/my-listings/?page=2
```

#### Response
```json
{
    "total_pages": 2,
    "item_0": {
        "id": "5",
        "name": "Your Name",
        "title": "Your Book Title",
        "description": "Your book description",
        "tags": ["your", "tags"],
        "negotiable": true,
        "phone": "your_phone",
        "year": "3rd yr"
    }
}
```

#### Query Parameters
- `page` (optional): Page number (default: 1)

---

### 3. Get Single Listing
**GET** `/listings/{id}/`

Returns details of a specific listing.

#### Request
```
GET /api/listings/1/
```

#### Response
```json
{
    "id": "1",
    "name": "John Doe",
    "title": "Programming Book",
    "description": "Great book for beginners",
    "tags": ["programming", "beginner"],
    "negotiable": true,
    "phone": "1234567890",
    "year": "1st yr"
}
```

---

### 4. Create New Listing
**POST** `/listings/`

Creates a new listing. Requires authentication.

#### Request
```
POST /api/listings/
Content-Type: application/json
Authorization: Bearer <your_jwt_token>

{
    "title": "New Book Title",
    "description": "Book description here",
    "price": 500,
    "tags": "programming, beginner, python",
    "negotiable": true,
    "year": "2nd yr"
}
```

#### Response
```json
{
    "id": "6",
    "name": "Your Name",
    "title": "New Book Title",
    "description": "Book description here",
    "tags": ["programming", "beginner", "python"],
    "negotiable": true,
    "phone": "your_phone",
    "year": "2nd yr"
}
```

#### Request Body Fields
- `title` (required): String, max 200 characters
- `description` (required): Text
- `price` (optional): Integer, price in currency units
- `tags` (optional): String, comma-separated tags
- `negotiable` (optional): Boolean, default false
- `year` (optional): String, e.g., "1st yr", "2nd yr"

---

### 5. Update Listing
**PUT** `/listings/{id}/`

Updates an existing listing. Only the owner can update.

#### Request
```
PUT /api/listings/1/
Content-Type: application/json
Authorization: Bearer <your_jwt_token>

{
    "title": "Updated Book Title",
    "description": "Updated description",
    "price": 600,
    "tags": "programming, advanced, python",
    "negotiable": false,
    "year": "3rd yr"
}
```

#### Response
```json
{
    "id": "1",
    "name": "John Doe",
    "title": "Updated Book Title",
    "description": "Updated description",
    "tags": ["programming", "advanced", "python"],
    "negotiable": false,
    "phone": "1234567890",
    "year": "3rd yr"
}
```

---

### 6. Partial Update Listing
**PATCH** `/listings/{id}/`

Partially updates a listing. Only the owner can update.

#### Request
```
PATCH /api/listings/1/
Content-Type: application/json
Authorization: Bearer <your_jwt_token>

{
    "price": 550,
    "negotiable": true
}
```

#### Response
```json
{
    "id": "1",
    "name": "John Doe",
    "title": "Programming Book",
    "description": "Great book for beginners",
    "tags": ["programming", "beginner"],
    "negotiable": true,
    "phone": "1234567890",
    "year": "1st yr"
}
```

---

### 7. Delete Listing
**DELETE** `/listings/{id}/`

Deletes a listing. Only the owner can delete.

#### Request
```
DELETE /api/listings/1/
Authorization: Bearer <your_jwt_token>
```

#### Response
```
HTTP 204 No Content
```

---

## Error Responses

### 401 Unauthorized
```json
{
    "detail": "Authentication credentials were not provided."
}
```

### 403 Forbidden
```json
{
    "detail": "You do not have permission to perform this action."
}
```

### 404 Not Found
```json
{
    "detail": "Not found."
}
```

### 400 Bad Request
```json
{
    "title": ["This field is required."],
    "description": ["This field is required."]
}
```

---

## Data Models

### Listing Object
```json
{
    "id": "string",
    "name": "string",
    "title": "string",
    "description": "string",
    "tags": ["string"],
    "negotiable": "boolean",
    "phone": "string",
    "year": "string"
}
```

### Field Descriptions
- `id`: Unique identifier for the listing
- `name`: Full name of the seller
- `title`: Title of the book/item
- `description`: Detailed description
- `tags`: Array of tags for categorization
- `negotiable`: Whether the price is negotiable
- `phone`: Seller's phone number
- `year`: Academic year (e.g., "1st yr", "2nd yr")

---

## Pagination

All list endpoints support pagination with 8 items per page. The response includes:
- `total_pages`: Total number of pages available
- Individual items as `item_0`, `item_1`, etc.

To navigate pages, use the `page` query parameter:
```
GET /api/listings/?page=2
```

---

## Authentication

### Getting JWT Token
To get a JWT token, you need to authenticate through the user authentication endpoints (not covered in this documentation).

### Using JWT Token
Include the token in the Authorization header for protected endpoints:
```
Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9...
```

---

## Rate Limiting
Currently, no rate limiting is implemented.

## CORS
CORS is enabled for all origins with credentials support.

## Notes
- All timestamps are in Asia/Kolkata timezone
- Phone numbers are stored as strings
- Tags are stored as comma-separated strings in the database but returned as arrays in the API
- The seller is automatically set to the authenticated user when creating listings 