# NextLean Scan - Webhook JSON Format

## Overview
This document describes the complete JSON format for project submissions sent to the `submit-project` Edge Function.

## Endpoint
```
POST https://wnyrnpeabhxdqvcpofmb.supabase.co/functions/v1/submit-project
```

## Headers
```
Authorization: Bearer [SUPABASE_ANON_KEY]
Content-Type: application/json
```

## Complete Request Body

```json
{
  "showroom_id": "uuid-of-showroom",
  "customer": {
    "first_name": "John",
    "last_name": "Doe",
    "email": "john.doe@example.com",
    "phone": "(555) 123-4567"
  },
  "project": {
    "name": "Kitchen Remodel",
    "notes": "Customer wants modern finishes"
  },
  "measurements": {
    "room_name": "Main Room",
    "room_type": "kitchen",
    "roomplan_data": {
      "walls": 4,
      "doors": 2,
      "windows": 3,
      "floors": 1,
      "openings": 0
    },
    "total_linear_ft": 48.5,
    "total_sq_ft": 144.0,
    "wall_count": 4,
    "window_count": 3,
    "door_count": 2,
    "measurements": {
      "room": {
        "min_x": -16.4,
        "max_x": 16.4,
        "min_z": -13.1,
        "max_z": 13.1,
        "ceiling_height_ft": 8.5
      },
      "walls": [
        {
          "id": "wall_1",
          "position": {
            "x": 0.0,
            "z": -13.1
          },
          "start": {
            "x": -16.4,
            "z": -13.1
          },
          "end": {
            "x": 16.4,
            "z": -13.1
          },
          "width_ft": 12.5,
          "height_ft": 8.5,
          "thickness_ft": 0.5,
          "linear_ft": 12.5
        },
        {
          "id": "wall_2",
          "position": {
            "x": 16.4,
            "z": 0.0
          },
          "start": {
            "x": 16.4,
            "z": -13.1
          },
          "end": {
            "x": 16.4,
            "z": 13.1
          },
          "width_ft": 10.0,
          "height_ft": 8.5,
          "thickness_ft": 0.5,
          "linear_ft": 10.0
        }
      ],
      "doors": [
        {
          "id": "door_1",
          "position": {
            "x": 6.0,
            "z": -13.1
          },
          "width_ft": 3.0,
          "height_ft": 6.67,
          "width_inches": "3' 0\"",
          "height_inches": "6' 8\""
        }
      ],
      "windows": [
        {
          "id": "window_1",
          "position": {
            "x": -8.0,
            "z": -13.1
          },
          "width_ft": 4.0,
          "height_ft": 3.5,
          "width_inches": "4' 0\"",
          "height_inches": "3' 6\"",
          "area_sqft": 14.0
        }
      ],
      "cabinets": {
        "upper": [
          {
            "id": "upper_1",
            "type": "upper_cabinet",
            "position": {
              "x": -10.0,
              "z": 12.5,
              "y": 5.5
            },
            "width_ft": 3.0,
            "height_ft": 2.5,
            "depth_ft": 1.0,
            "width_inches": "3' 0\"",
            "height_inches": "2' 6\"",
            "depth_inches": "1' 0\""
          }
        ],
        "lower": [
          {
            "id": "lower_1",
            "type": "lower_cabinet",
            "position": {
              "x": -10.0,
              "z": 12.8,
              "y": 1.5
            },
            "width_ft": 3.0,
            "height_ft": 3.0,
            "depth_ft": 2.0,
            "width_inches": "3' 0\"",
            "height_inches": "3' 0\"",
            "depth_inches": "2' 0\""
          }
        ]
      },
      "appliances": [
        {
          "id": "appliance_1",
          "type": "refrigerator",
          "position": {
            "x": 14.0,
            "z": 12.5,
            "y": 0.0
          },
          "width_ft": 3.0,
          "height_ft": 6.0,
          "depth_ft": 2.5,
          "width_inches": "3' 0\"",
          "height_inches": "6' 0\"",
          "depth_inches": "2' 6\""
        }
      ]
    },
    "usdz_file_url": "https://example.com/scans/room-123.usdz",
    "preview_image_url": "https://example.com/scans/room-123-preview.png"
  },
  "selections": [
    {
      "category_id": "uuid-of-category",
      "product_id": "uuid-of-product",
      "quantity": 1,
      "customer_notes": "Prefer white finish"
    }
  ],
  "device_info": {
    "model": "iPhone 14 Pro",
    "ios_version": "17.2",
    "app_version": "1.0"
  }
}
```

## Response (Success)

```json
{
  "success": true,
  "project_id": "uuid-of-created-project",
  "reference_number": "ABC123",
  "showroom_name": "Demo Showroom"
}
```

## Response (Error)

```json
{
  "error": "Error message description"
}
```

## Measurement Data Structure Explained

### Room Bounds
Contains the overall room dimensions:
- `min_x`, `max_x`: Room width boundaries in feet
- `min_z`, `max_z`: Room length boundaries in feet
- `ceiling_height_ft`: Height from floor to ceiling

### Walls
Each wall contains:
- `id`: Unique identifier (wall_1, wall_2, etc.)
- `position`: Center point of wall in 2D space
- `start`: Starting point coordinates
- `end`: Ending point coordinates
- `width_ft`: Wall length in decimal feet
- `height_ft`: Wall height in decimal feet
- `thickness_ft`: Wall thickness
- `linear_ft`: Linear footage (same as width_ft for pricing)

### Doors
Each door contains:
- `id`: Unique identifier
- `position`: Location on wall
- `width_ft`: Door width in decimal feet
- `height_ft`: Door height in decimal feet
- `width_inches`: Formatted as feet and inches (e.g., "3' 0\"")
- `height_inches`: Formatted as feet and inches (e.g., "6' 8\"")

### Windows
Each window contains:
- `id`: Unique identifier
- `position`: Location on wall
- `width_ft`: Window width in decimal feet
- `height_ft`: Window height in decimal feet
- `width_inches`: Formatted dimension
- `height_inches`: Formatted dimension
- `area_sqft`: Total window area (width × height)

### Cabinets
Separated into upper and lower cabinets:
- `id`: Unique identifier
- `type`: "upper_cabinet" or "lower_cabinet"
- `position`: 3D coordinates (x, z, y)
  - `x`, `z`: Horizontal position
  - `y`: Height from floor (used to categorize upper vs lower)
- `width_ft`, `height_ft`, `depth_ft`: Dimensions in feet
- `width_inches`, `height_inches`, `depth_inches`: Formatted dimensions

### Appliances
Detected appliances (refrigerator, stove, oven, etc.):
- `id`: Unique identifier
- `type`: Appliance category
- `position`: 3D coordinates
- Dimensions in both feet and formatted inches

## Coordinate System

The measurement data uses a right-handed coordinate system:
- **X-axis**: Left to right (negative to positive)
- **Y-axis**: Floor to ceiling (height)
- **Z-axis**: Front to back

All positions are in feet relative to the room center.

## Usage Notes

1. **All measurements are in feet** unless otherwise specified
2. **Coordinate origin** is typically the center of the scanned room
3. **Cabinet categorization** is based on Y-position (height from floor):
   - Upper cabinets: `y > 4 feet`
   - Lower cabinets: `y <= 4 feet`
4. **Optional fields**: Some measurements may be absent if not detected by RoomPlan
5. **Precision**: Measurements are accurate to ~95% with LiDAR scanning

## Testing

You can test the webhook using curl:

```bash
curl -X POST https://wnyrnpeabhxdqvcpofmb.supabase.co/functions/v1/submit-project \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d @sample-submission.json
```

## Database Storage

The detailed measurements are stored in:
- **Table**: `project_measurements`
- **Column**: `measurements` (JSONB)
- **Indexing**: Can query nested fields using PostgreSQL JSON operators

Example query:
```sql
SELECT
  id,
  measurements->'walls' as walls,
  measurements->'cabinets'->'upper' as upper_cabinets
FROM project_measurements
WHERE project_id = 'some-uuid';
```
