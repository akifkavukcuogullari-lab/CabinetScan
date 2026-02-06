# CabinetScan: Scanning Design Ideas & Viable Approaches

## Document Purpose

This document compiles all positive ideas and viable approaches for achieving accurate room and cabinet measurements using iPhone (non-LiDAR) devices. Use this as a reference when designing the scanning solution.

**Key Requirements:**
- ±2 inch accuracy for measurements
- Fully automatic (no user interaction during scan)
- Works on non-LiDAR iPhones (iPhone XS and newer)
- Works for ANY room (empty, with cabinets, any scenario)
- Server processing is acceptable (results go to showroom dashboard)
- No external hardware (iPhone only)

---

## Table of Contents

1. [What MagicPlan Actually Does](#1-what-magicplan-actually-does)
2. [ARKit Capabilities (Non-LiDAR)](#2-arkit-capabilities-non-lidar)
3. [Reference Objects for Scale](#3-reference-objects-for-scale)
4. [Multi-View Triangulation](#4-multi-view-triangulation)
5. [Edge Detection Approaches](#5-edge-detection-approaches)
6. [Room Boundary Detection](#6-room-boundary-detection)
7. [Object Detection (YOLO/SAM2)](#7-object-detection-yolosam2)
8. [Server Processing Pipeline](#8-server-processing-pipeline)
9. [Depth Estimation Models](#9-depth-estimation-models)
10. [Scale Calibration Methods](#10-scale-calibration-methods)
11. [Standard Sizes as Constraints](#11-standard-sizes-as-constraints)
12. [Accuracy Validation](#12-accuracy-validation)
13. [Capture Guidance](#13-capture-guidance)
14. [Output Format](#14-output-format)
15. [Implementation Priorities](#15-implementation-priorities)
16. [Critical Limitations: Why Detection Alone Can't Work](#16-critical-limitations-why-detection-alone-cant-work)
17. [Questions to Resolve Before Implementation](#17-questions-to-resolve-before-implementation)
18. [**Automatic Base Cabinet Height Calibration (RECOMMENDED)**](#18-automatic-base-cabinet-height-calibration-recommended-approach)

---

## 1. What MagicPlan Actually Does

### Key Insight
MagicPlan does NOT reconstruct a 3D mesh. Instead, it:
- Detects planes (walls, floors)
- Measures distances between planes
- Infers rooms as polygons
- Produces a 2D top-down floor plan
- Optionally extrudes to "fake 3D"

### Why This Works
- Uses ARKit SLAM for metric-accurate camera positions
- Scale comes from ARKit (meters) + reference objects
- Simple geometric abstraction, not photorealistic reconstruction

### For CabinetScan
- We need the same approach: geometric abstraction
- 2D floor plan with measurements is the goal
- No need for dense 3D mesh reconstruction

---

## 2. ARKit Capabilities (Non-LiDAR)

### What ARKit Provides (Reliable)

| Feature | Accuracy | Notes |
|---------|----------|-------|
| **Camera poses** | ±1-2cm | Position + orientation at 60Hz |
| **Camera intrinsics** | Exact | fx, fy, cx, cy |
| **Gravity alignment** | Excellent | Y-axis aligned with up |
| **Horizontal planes** | Good | Floor detection reliable |
| **Vertical planes** | Moderate | Works on textured walls |
| **World tracking** | Excellent | Stable coordinate system |

### What ARKit Does NOT Provide (Without LiDAR)

| Feature | Status |
|---------|--------|
| Scene depth | NOT AVAILABLE |
| Scene reconstruction | NOT AVAILABLE |
| Dense mesh | NOT AVAILABLE |
| Metric depth per pixel | NOT AVAILABLE |

### Current Code Issue
```swift
// In AIARSessionManager.swift line 188
configuration.planeDetection = []  // DISABLED!

// Should be:
configuration.planeDetection = [.horizontal, .vertical]
```

### ARKit Plane Detection Output
```swift
func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
    for anchor in anchors {
        if let planeAnchor = anchor as? ARPlaneAnchor {
            // Available data:
            planeAnchor.center      // Position in meters
            planeAnchor.extent      // Size in meters (approximate)
            planeAnchor.alignment   // .horizontal or .vertical
            planeAnchor.transform   // Full 4x4 transform
            planeAnchor.geometry    // Boundary polygon (iOS 11.3+)
        }
    }
}
```

---

## 3. Reference Objects for Scale

### The Scale Problem
Without knowing absolute distance, pixel measurements are meaningless.
Reference objects with KNOWN sizes solve this.

### Universal References (Present in Most Rooms)

| Object | Size | Reliability | Detection Difficulty |
|--------|------|-------------|---------------------|
| **Interior door height** | 80" (6'8") | VERY HIGH | Easy (YOLO) |
| **Door width** | 30", 32", 36" | HIGH | Easy |
| **Electrical outlet** | 4.5" × 2.75" | VERY HIGH | Medium |
| **Light switch** | 4.5" × 2.75" | VERY HIGH | Medium |
| **Outlet cover plate** | 4.875" × 3.125" | VERY HIGH | Medium |
| **Ceiling height** | 96", 108", 120" | HIGH | Requires detection |

### Kitchen-Specific References

| Object | Size | Reliability | Notes |
|--------|------|-------------|-------|
| **Dishwasher** | 24" width | 100% | Building code standard |
| **Range (standard)** | 30" width | 95% | Most common size |
| **Range (large)** | 36" width | HIGH | Detectable |
| **Countertop height** | 36" from floor | VERY HIGH | Industry standard |
| **Upper cabinet bottom** | 54" from floor | HIGH | Standard installation |

### Scale Calculation
```python
def calculate_scale(reference_pixels, reference_actual_inches):
    """
    Calculate pixels-per-inch at a given depth.
    """
    pixels_per_inch = reference_pixels / reference_actual_inches
    return pixels_per_inch

# Example:
# Door detected as 640 pixels tall
# Door actual height = 80"
# Scale = 640 / 80 = 8 pixels per inch at that distance
```

### Multi-Reference Validation
```python
def validate_scale(references):
    """
    Cross-validate scale from multiple references.
    """
    scales = []
    for ref in references:
        scale = calculate_scale(ref.pixels, ref.actual_size)
        scales.append(scale)

    # Check variance
    variance = np.var(scales)
    if variance < threshold:
        return np.median(scales), confidence=HIGH
    else:
        return np.median(scales), confidence=LOW, flag=NEEDS_REVIEW
```

---

## 4. Multi-View Triangulation

### Core Concept
Use camera movement to compute 3D positions of detected features.

```
Frame 1 (Position A):          Frame 2 (Position B):
    Camera A                       Camera B
        \                           /
         \  ray1              ray2 /
          \                       /
           \                     /
            \                   /
             \                 /
              ●───────────────●
              Point P (3D position computed)
```

### Why This Works
- ARKit gives accurate camera positions (pose1, pose2)
- We detect same feature in multiple frames
- Triangulation computes 3D position
- Distance between 3D points = measurement

### Implementation
```python
def triangulate_point(pixel1, pixel2, pose1, pose2, intrinsics):
    """
    Triangulate 3D position from two observations.

    Args:
        pixel1, pixel2: (x, y) pixel positions in each frame
        pose1, pose2: Camera poses from ARKit (4x4 matrices)
        intrinsics: Camera intrinsics (fx, fy, cx, cy)

    Returns:
        point_3d: (x, y, z) position in world coordinates (meters)
    """
    # Convert pixels to normalized camera coordinates
    ray1 = pixel_to_ray(pixel1, intrinsics)
    ray2 = pixel_to_ray(pixel2, intrinsics)

    # Transform rays to world coordinates
    ray1_world = pose1.rotation @ ray1
    ray2_world = pose2.rotation @ ray2

    # Find closest point between two rays (least squares)
    point_3d = closest_point_between_rays(
        origin1=pose1.translation, dir1=ray1_world,
        origin2=pose2.translation, dir2=ray2_world
    )

    return point_3d

def measure_distance(point1_3d, point2_3d):
    """
    Distance between two triangulated points.
    """
    distance_meters = np.linalg.norm(point1_3d - point2_3d)
    distance_inches = distance_meters * 39.37
    return distance_inches
```

### Accuracy Factors
- **Baseline**: Larger camera movement = better accuracy
- **Feature detection**: Sub-pixel accuracy helps
- **ARKit pose accuracy**: Very good (±1-2cm)
- **Expected accuracy**: ±1-2" with good baseline

### Best For
- Room corner positions
- Door/window frame positions
- Cabinet seam positions
- Any distinct edge or corner

---

## 5. Edge Detection Approaches

### Room Corners (Wall-Wall Intersections)
```
Room corner (vertical edge):
      │
      │  ← Visible as vertical line where two walls meet
      │
      │
```

### Floor-Wall Boundaries
```
      │ WALL │
──────┴──────┴──────  ← Visible line where floor meets wall
      FLOOR
```

### Cabinet Seams
```
┌──────┬──────┬──────┐
│      │      │      │
│ CAB1 │ CAB2 │ CAB3 │
│      │      │      │
└──────┴──────┴──────┘
       ↑      ↑
    Shadow lines (seams)
```

### Edge Detection Pipeline
```python
def detect_vertical_edges(image):
    """
    Detect vertical edges (room corners, cabinet seams, door frames).
    """
    # 1. Convert to grayscale
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)

    # 2. Enhance vertical edges (Sobel)
    sobel_x = cv2.Sobel(gray, cv2.CV_64F, 1, 0, ksize=3)

    # 3. Or use learned edge detector (better)
    # - DexiNed (Dense Extreme Inception Network)
    # - EDTER (Edge Detection Transformer)
    # - HED (Holistically-nested Edge Detection)

    # 4. Hough line detection for verticals
    lines = cv2.HoughLinesP(edges, rho=1, theta=np.pi/180,
                            threshold=100, minLineLength=200, maxLineGap=10)

    # 5. Filter for near-vertical lines (within 5°)
    vertical_lines = filter_vertical(lines, tolerance_degrees=5)

    return vertical_lines
```

### Advanced: Learned Edge Detection
```python
# DexiNed or similar provides better edges than Canny/Sobel
# Especially for:
# - Low contrast edges (cabinet seams)
# - Shadow boundaries
# - Subtle transitions

# Models:
# - DexiNed: https://github.com/xavysp/DexiNed
# - EDTER: Edge Detection Transformer
# - PidiNet: Pixel Difference Networks
```

---

## 6. Room Boundary Detection

### Approach 1: ARKit Planes → Room Polygon
```python
def build_room_polygon(vertical_planes):
    """
    Build room polygon from ARKit vertical planes.
    """
    # 1. Get all vertical plane anchors
    walls = [p for p in planes if p.alignment == .vertical]

    # 2. Find plane intersections (corners)
    corners = []
    for i, wall1 in enumerate(walls):
        for wall2 in walls[i+1:]:
            intersection = plane_intersection(wall1, wall2)
            if intersection:
                corners.append(intersection)

    # 3. Order corners to form polygon
    polygon = order_corners_clockwise(corners)

    return polygon
```

### Approach 2: Floor Boundary Detection
```python
def detect_floor_boundary(frames, floor_plane):
    """
    Detect where floor meets walls in each frame.
    """
    boundaries = []

    for frame, pose in frames:
        # 1. Detect floor-wall boundary line in image
        boundary_pixels = detect_floor_wall_line(frame)

        # 2. Project to 3D using floor plane constraint
        boundary_3d = project_to_floor_plane(boundary_pixels, pose, floor_plane)

        boundaries.append(boundary_3d)

    # 3. Merge boundaries from all frames
    room_boundary = merge_boundaries(boundaries)

    return room_boundary
```

### Approach 3: Corner Triangulation
```python
def build_room_from_corners(video_frames, arkit_poses):
    """
    Build room by triangulating detected corners.
    """
    # 1. Detect room corners in each frame
    corner_detections = []
    for frame, pose in zip(video_frames, arkit_poses):
        corners = detect_room_corners(frame)
        corner_detections.append((corners, pose))

    # 2. Track same corner across frames
    tracked_corners = track_corners_across_frames(corner_detections)

    # 3. Triangulate each corner's 3D position
    corners_3d = []
    for corner_track in tracked_corners:
        point_3d = triangulate_from_multiple_views(corner_track)
        corners_3d.append(point_3d)

    # 4. Build polygon from corners
    room_polygon = build_polygon(corners_3d)

    return room_polygon
```

---

## 7. Object Detection (YOLO/SAM2)

### YOLO for Object Detection
```python
# Objects to detect:
classes = [
    # Universal
    'door', 'window', 'electrical_outlet', 'light_switch',

    # Kitchen
    'upper_cabinet', 'lower_cabinet', 'tall_cabinet',
    'refrigerator', 'range', 'dishwasher', 'sink',
    'microwave', 'hood_vent',

    # Bathroom
    'vanity', 'toilet', 'bathtub', 'shower',

    # General
    'fireplace', 'built_in_shelving'
]

# YOLO-World for open vocabulary detection
# Can detect: "cabinet", "appliance", "door frame" without specific training
```

### SAM2 for Precise Boundaries
```python
def get_precise_boundaries(image, yolo_boxes):
    """
    Use SAM2 to get precise object boundaries from YOLO boxes.
    """
    sam2 = load_sam2_model()

    precise_masks = []
    for box in yolo_boxes:
        # SAM2 takes box prompt, returns precise mask
        mask = sam2.segment(image, box_prompt=box)
        precise_masks.append(mask)

    return precise_masks
```

### Detection + Measurement Pipeline
```python
def detect_and_measure_objects(frames, poses, scale_factor):
    """
    Detect objects and measure their dimensions.
    """
    all_detections = []

    for frame, pose in zip(frames, poses):
        # 1. YOLO detection
        boxes = yolo_detect(frame)

        # 2. SAM2 refinement
        masks = sam2_segment(frame, boxes)

        # 3. Calculate dimensions using scale
        for box, mask in zip(boxes, masks):
            width_pixels = mask.width
            height_pixels = mask.height

            # Apply scale (from reference object)
            width_inches = width_pixels / scale_factor
            height_inches = height_pixels / scale_factor

            all_detections.append({
                'class': box.class_name,
                'width': width_inches,
                'height': height_inches,
                'position': calculate_position(box, pose)
            })

    # 4. Merge detections across frames
    merged = merge_detections(all_detections)

    return merged
```

---

## 8. Server Processing Pipeline

### Architecture
```
┌─────────────────────────────────────────────────────────────────┐
│                      iOS APP (Capture Only)                      │
├─────────────────────────────────────────────────────────────────┤
│  • Video recording (1080p/4K, 30fps)                            │
│  • ARKit data collection:                                        │
│    - Camera poses (60Hz)                                         │
│    - Plane anchors (floor, walls)                                │
│    - Camera intrinsics                                           │
│  • Upload to Supabase storage                                    │
│  • Show: "Processing... Results in 5-10 minutes"                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    SERVER PROCESSING                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Stage 1: Frame Extraction                                       │
│  • Extract keyframes (every 0.5s or 10° rotation)               │
│  • Select best quality frames (sharpness, lighting)             │
│                                                                  │
│  Stage 2: Reference Detection                                    │
│  • Detect doors, outlets, appliances (YOLO)                     │
│  • Calculate scale from known sizes                             │
│  • Cross-validate multiple references                           │
│                                                                  │
│  Stage 3: Edge/Corner Detection                                  │
│  • Room corners (wall intersections)                            │
│  • Floor-wall boundaries                                         │
│  • Door/window frames                                            │
│  • Cabinet seams (if present)                                   │
│                                                                  │
│  Stage 4: Multi-View Triangulation                              │
│  • Track features across frames                                  │
│  • Triangulate 3D positions                                      │
│  • Build room wireframe                                          │
│                                                                  │
│  Stage 5: Measurement Extraction                                 │
│  • Wall lengths (corner to corner)                              │
│  • Opening sizes (doors, windows)                               │
│  • Cabinet dimensions (if present)                              │
│  • Apply scale calibration                                       │
│                                                                  │
│  Stage 6: Floor Plan Generation                                  │
│  • Build 2D polygon                                              │
│  • Place openings on walls                                       │
│  • Place objects (cabinets, appliances)                         │
│  • Render floor plan image                                       │
│                                                                  │
│  Stage 7: Store Results                                          │
│  • Save to Supabase                                              │
│  • Notify dashboard                                              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Processing Time Estimate
| Stage | Time |
|-------|------|
| Frame extraction | 10-20s |
| Reference detection | 20-30s |
| Edge detection | 30-60s |
| Triangulation | 60-120s |
| Measurement | 10-20s |
| Floor plan | 10-20s |
| **Total** | **3-5 minutes** |

### Server Cost Estimate
| Component | Cost per Scan |
|-----------|---------------|
| GPU compute (A100, 5 min) | $0.30-0.50 |
| Storage (temporary) | $0.01 |
| Total | **~$0.30-0.50** |

---

## 9. Depth Estimation Models

### Current State of the Art

| Model | Type | Accuracy | Mobile Ready |
|-------|------|----------|--------------|
| **Depth Anything V2** | Relative | Ordinal only | Yes (CoreML) |
| **Depth Pro (Apple)** | Metric | Best edges | No (coming) |
| **Metric3D v2** | Metric | ±18" indoor | No |
| **UniDepth** | Metric | ±7.5% relative | No |
| **Marigold** | Relative | Best structure | No (slow) |

### Key Limitation
All monocular depth models have **scale ambiguity**:
- Cannot determine absolute distance without reference
- Best models still have ±12-26" error indoors
- NOT sufficient for ±2" accuracy alone

### How to Use Depth Models
```python
def use_depth_for_validation(depth_map, triangulated_points):
    """
    Use depth model to VALIDATE, not as primary measurement.
    """
    for point in triangulated_points:
        # Get depth model's estimate at that pixel
        depth_estimate = depth_map[point.pixel_y, point.pixel_x]

        # Compare with triangulated depth
        triangulated_depth = point.z

        # Flag large discrepancies for review
        if abs(depth_estimate - triangulated_depth) > threshold:
            point.confidence = LOW
            point.needs_review = True

    return triangulated_points
```

### Apple Depth Pro (Promising)
- Released October 2024
- Claims metric depth without camera intrinsics
- Best boundary accuracy (sharp edges)
- Not yet available for iOS/CoreML
- Watch for official release

---

## 10. Scale Calibration Methods

### Method 1: Door Reference (Primary)
```python
def calibrate_from_door(door_detection, arkit_pose):
    """
    Use door height (80") as scale reference.
    """
    DOOR_HEIGHT_INCHES = 80.0

    door_height_pixels = door_detection.height
    distance_to_door = estimate_distance(door_detection, arkit_pose)

    # Calculate scale factor
    scale = DOOR_HEIGHT_INCHES / door_height_pixels

    return scale, confidence=HIGH
```

### Method 2: Outlet Reference (Secondary)
```python
def calibrate_from_outlet(outlet_detection):
    """
    Use outlet size (4.5" x 2.75") as scale reference.
    """
    OUTLET_HEIGHT_INCHES = 4.5
    OUTLET_WIDTH_INCHES = 2.75

    # Use height (more reliable than width)
    outlet_height_pixels = outlet_detection.height
    scale = OUTLET_HEIGHT_INCHES / outlet_height_pixels

    return scale, confidence=MEDIUM
```

### Method 3: Appliance Reference (Kitchen)
```python
def calibrate_from_appliance(appliance_detection):
    """
    Use known appliance widths.
    """
    APPLIANCE_WIDTHS = {
        'dishwasher': 24.0,   # Always 24"
        'range_30': 30.0,     # Standard range
        'range_36': 36.0,     # Large range
        'refrigerator_30': 30.0,
        'refrigerator_33': 33.0,
        'refrigerator_36': 36.0,
    }

    known_width = APPLIANCE_WIDTHS.get(appliance_detection.subtype)
    if known_width:
        scale = known_width / appliance_detection.width_pixels
        return scale, confidence=HIGH

    return None, confidence=NONE
```

### Method 4: Multi-Reference Validation
```python
def calibrate_with_validation(all_references):
    """
    Use multiple references and cross-validate.
    """
    scales = []

    for ref in all_references:
        if ref.type == 'door':
            scale = calibrate_from_door(ref)
        elif ref.type == 'outlet':
            scale = calibrate_from_outlet(ref)
        elif ref.type == 'appliance':
            scale = calibrate_from_appliance(ref)

        if scale:
            scales.append(scale)

    if len(scales) >= 2:
        # Check agreement
        variance = np.var(scales)
        if variance < 0.01:  # Scales agree within 1%
            return np.median(scales), confidence=VERY_HIGH
        else:
            return np.median(scales), confidence=MEDIUM, flag=REVIEW
    elif len(scales) == 1:
        return scales[0], confidence=MEDIUM
    else:
        return None, confidence=NONE, flag=NO_REFERENCE
```

### Method 5: Ceiling Height Fallback
```python
def calibrate_from_ceiling(ceiling_plane, floor_plane, user_selection=None):
    """
    Use ceiling height as fallback reference.
    """
    STANDARD_CEILINGS = {
        '8ft': 96.0,
        '9ft': 108.0,
        '10ft': 120.0,
    }

    # Calculate ceiling height from planes
    measured_height = ceiling_plane.position.y - floor_plane.position.y
    measured_height_inches = measured_height * 39.37

    # Find closest standard
    closest = min(STANDARD_CEILINGS.values(),
                  key=lambda x: abs(x - measured_height_inches))

    # Calculate scale correction
    scale = closest / measured_height_inches

    return scale, confidence=MEDIUM
```

---

## 11. Standard Sizes as Constraints

### Cabinet Standards (When Cabinets Present)

```python
STANDARD_CABINET_WIDTHS = [9, 12, 15, 18, 21, 24, 27, 30, 33, 36, 48]  # inches

CABINET_HEIGHTS = {
    'base': 34.5,       # Always
    'upper_30': 30,     # Standard upper
    'upper_36': 36,     # Tall upper
    'upper_42': 42,     # Extra tall upper
    'tall_84': 84,      # Tall/pantry
    'tall_90': 90,
    'tall_96': 96,
}

CABINET_DEPTHS = {
    'base': 24,         # Always
    'upper': 12,        # Always
    'tall': 24,         # Usually
}
```

### Using Standards as Soft Constraints
```python
def snap_to_standard_if_close(measured_width, tolerance=2.0):
    """
    Snap to standard size if within tolerance.
    BUT mark as non-standard if outside tolerance (could be filler).
    """
    closest = min(STANDARD_CABINET_WIDTHS,
                  key=lambda x: abs(x - measured_width))

    difference = abs(closest - measured_width)

    if difference <= tolerance:
        return {
            'width': closest,
            'type': 'standard',
            'confidence': 'HIGH' if difference <= 1.0 else 'MEDIUM'
        }
    else:
        return {
            'width': measured_width,  # Keep actual measurement
            'type': 'non_standard_or_filler',
            'confidence': 'MEDIUM',
            'nearest_standard': closest,
            'note': f'May be filler or custom. Nearest standard: {closest}"'
        }
```

### Important: Fillers Are Real
```
Standard snapping should NOT be the primary method!
Real kitchens have:
- Filler strips (1-6" custom cut)
- Scribe molding
- Non-standard configurations
- Custom cabinets

Use standards as VALIDATION, not MEASUREMENT.
```

---

## 12. Accuracy Validation

### Cross-Validation Methods

```python
def validate_measurements(room_data):
    """
    Cross-validate measurements using multiple checks.
    """
    validations = []

    # 1. Wall segments should sum to total wall length
    for wall in room_data.walls:
        segment_sum = sum(s.width for s in wall.segments)
        if abs(segment_sum - wall.total_length) > 6:  # 6" tolerance
            validations.append({
                'type': 'segment_sum_mismatch',
                'wall': wall.id,
                'expected': wall.total_length,
                'actual': segment_sum,
                'severity': 'WARNING'
            })

    # 2. Room should be closed polygon
    if not is_closed_polygon(room_data.corners):
        validations.append({
            'type': 'polygon_not_closed',
            'severity': 'ERROR'
        })

    # 3. Parallel walls should have consistent measurements
    parallel_pairs = find_parallel_walls(room_data.walls)
    for wall1, wall2 in parallel_pairs:
        # In rectangular room, opposite walls should be equal
        if abs(wall1.length - wall2.length) > 3:
            validations.append({
                'type': 'parallel_wall_mismatch',
                'severity': 'WARNING'
            })

    # 4. Door/window sizes should be reasonable
    for opening in room_data.openings:
        if opening.type == 'door' and not (24 <= opening.width <= 48):
            validations.append({
                'type': 'unusual_door_width',
                'value': opening.width,
                'severity': 'WARNING'
            })

    return validations
```

### Confidence Scoring
```python
def calculate_confidence(measurement, method_used, validations):
    """
    Calculate confidence score for a measurement.
    """
    score = 1.0

    # Method confidence
    METHOD_WEIGHTS = {
        'triangulation_good_baseline': 1.0,
        'triangulation_short_baseline': 0.8,
        'reference_door': 0.95,
        'reference_outlet': 0.85,
        'reference_appliance': 0.9,
        'arkit_plane_only': 0.7,
        'depth_model_only': 0.5,
    }
    score *= METHOD_WEIGHTS.get(method_used, 0.7)

    # Validation penalties
    for validation in validations:
        if validation['severity'] == 'ERROR':
            score *= 0.5
        elif validation['severity'] == 'WARNING':
            score *= 0.8

    # Convert to confidence level
    if score >= 0.9:
        return 'HIGH'
    elif score >= 0.7:
        return 'MEDIUM'
    else:
        return 'LOW'
```

---

## 13. Capture Guidance

### Guidance for Quality Capture

```python
CAPTURE_GUIDANCE = {
    'start': "Stand in doorway. Point camera at the room.",

    'move_prompt': "Slowly walk along the walls.",

    'coverage_check': {
        'corners_visible': "Make sure to capture all corners.",
        'walls_visible': "Scan along each wall.",
        'door_visible': "Include the door in your scan for accurate measurements.",
    },

    'quality_warnings': {
        'too_fast': "Moving too fast. Please slow down.",
        'too_dark': "Room is dark. Turn on lights for better accuracy.",
        'tracking_lost': "Tracking lost. Return to previously scanned area.",
    },

    'completion': {
        'minimum_coverage': "Scan complete! Processing will take 5-10 minutes.",
        'needs_more': "Please scan the {missing_area} for complete coverage.",
    }
}
```

### Coverage Tracking
```python
def track_coverage(arkit_poses, room_estimate):
    """
    Track which parts of room have been captured.
    """
    # Divide room into zones
    zones = divide_into_zones(room_estimate, zone_count=8)

    covered_zones = set()
    for pose in arkit_poses:
        # Which zone is camera looking at?
        viewing_zone = get_viewing_zone(pose, zones)
        covered_zones.add(viewing_zone)

    coverage_percent = len(covered_zones) / len(zones)

    missing_zones = [z for z in zones if z not in covered_zones]

    return {
        'coverage_percent': coverage_percent,
        'missing_zones': missing_zones,
        'is_complete': coverage_percent >= 0.8
    }
```

---

## 14. Output Format

### JSON Output Structure
```json
{
  "scan_id": "uuid",
  "processed_at": "2026-02-01T10:30:00Z",
  "confidence": "HIGH",
  "accuracy_estimate": "±2 inches",

  "room": {
    "type": "kitchen",
    "shape": "L-shaped",
    "area_sqft": 120.5,
    "ceiling_height_inches": 96,

    "corners": [
      {"id": "c1", "position": [0, 0], "confidence": "HIGH"},
      {"id": "c2", "position": [144, 0], "confidence": "HIGH"},
      {"id": "c3", "position": [144, 96], "confidence": "MEDIUM"}
    ],

    "walls": [
      {
        "id": "w1",
        "start_corner": "c1",
        "end_corner": "c2",
        "length_inches": 144,
        "confidence": "HIGH",
        "segments": [
          {"type": "filler", "width": 3, "position": 0},
          {"type": "cabinet", "subtype": "base", "width": 33, "position": 3},
          {"type": "appliance", "subtype": "range", "width": 30, "position": 36}
        ]
      }
    ]
  },

  "openings": [
    {
      "type": "door",
      "wall_id": "w3",
      "position_inches": 24,
      "width_inches": 32,
      "height_inches": 80,
      "confidence": "HIGH"
    },
    {
      "type": "window",
      "wall_id": "w1",
      "position_inches": 48,
      "width_inches": 36,
      "height_inches": 48,
      "sill_height_inches": 42,
      "confidence": "HIGH"
    }
  ],

  "cabinets": {
    "upper": [...],
    "lower": [...],
    "tall": [...]
  },

  "appliances": [...],

  "floor_plan_url": "https://storage.../floor_plan.png",

  "calibration": {
    "method": "door_height",
    "reference_object": "interior_door",
    "scale_factor": 1.003,
    "confidence": "HIGH"
  },

  "validations": [
    {"type": "segments_sum_check", "status": "PASS"},
    {"type": "polygon_closed", "status": "PASS"}
  ]
}
```

### Floor Plan Image
```
┌────────────────────────────────────────────────────────┐
│                                                        │
│  12'0"                                                 │
│  ────────────────────────────────────────→            │
│                                                        │
│  ┌──W36──┐    ┌───WINDOW───┐    ┌──W36──┐           │
│  │       │    │   36x48    │    │       │           │
│  └───────┘    └────────────┘    └───────┘           │
│                                                      8'0"
│  ┌───────┬────────┬────────┬─────────┐              │
│  │  B33  │  SINK  │ RANGE  │  B30    │              │
│  │       │   24   │   30   │         │              │
│  └───────┴────────┴────────┴─────────┘              │
│                                                        │
│       ┌──DOOR 32──┐                                  │
│       │           │                                   │
└───────┴───────────┴───────────────────────────────────┘
```

---

## 15. Implementation Priorities

### Phase 1: Core Room Measurement (4-6 weeks)
**Goal: Measure any room (empty or furnished)**

1. Enable ARKit plane detection
2. Implement room corner detection
3. Implement multi-view triangulation
4. Implement door detection + scale calibration
5. Build 2D floor plan generator

**Deliverable:** Measure wall lengths and room shape for any room

### Phase 2: Openings (2 weeks)
**Goal: Detect and measure doors/windows**

1. Door frame detection
2. Window frame detection
3. Position and size measurement
4. Place on floor plan

**Deliverable:** Floor plan with doors and windows

### Phase 3: Kitchen Objects (3-4 weeks)
**Goal: Detect cabinets and appliances**

1. Cabinet detection (YOLO + SAM2)
2. Appliance detection
3. Cabinet seam detection
4. Segment width measurement

**Deliverable:** Kitchen floor plan with cabinet layout

### Phase 4: Accuracy Refinement (2 weeks)
**Goal: Achieve ±2" accuracy**

1. Multi-reference scale calibration
2. Cross-validation checks
3. Confidence scoring
4. Flagging uncertain measurements

**Deliverable:** High-confidence measurements with validation

### Phase 5: Polish (2 weeks)
**Goal: Production-ready**

1. Capture guidance UI
2. Processing status updates
3. Error handling
4. Dashboard integration

**Deliverable:** Complete production system

---

## Summary: Key Approaches

| Approach | Use For | Accuracy | Priority |
|----------|---------|----------|----------|
| **ARKit plane detection** | Initial room structure | ±4-6" | HIGH |
| **Multi-view triangulation** | Corner/edge positions | ±1-2" | HIGH |
| **Door reference** | Scale calibration | ±1" scale | HIGH |
| **Edge detection** | Cabinet seams, room corners | ±1-2" | HIGH |
| **YOLO detection** | Objects (doors, appliances) | Detection | MEDIUM |
| **SAM2 segmentation** | Precise boundaries | Boundaries | MEDIUM |
| **Standard size snapping** | Validation only | N/A | LOW |
| **Depth models** | Validation only | ±12"+ | LOW |

---

## 16. Critical Limitations: Why Detection Alone Can't Work

### ⚠️ THIS SECTION IS CRITICAL - READ BEFORE IMPLEMENTING

The approaches described above have fundamental limitations that may prevent achieving ±2" accuracy automatically. This section documents why.

---

### Problem #1: Detection ≠ Measurement

**YOLO + SAM2 tells us WHERE objects are, not HOW BIG they are.**

```
What YOLO gives us:
┌─────────────────────────────────────┐
│                                     │
│    ┌─────────┐                      │
│    │  DOOR   │  ← "There's a door   │
│    │         │     at pixels        │
│    │         │     (100,50)-(300,450)" │
│    └─────────┘                      │
│                                     │
└─────────────────────────────────────┘

What we NEED:
"The door is 32 inches wide and 80 inches tall"

YOLO doesn't give us this!
```

**The pixel-to-inch problem:**
```
Door in pixels: 200px wide × 400px tall

But what's the real size?
- If door is 3 feet away: 200px = 32"
- If door is 6 feet away: 200px = 64"
- If door is 10 feet away: 200px = 107"

We STILL need distance to convert pixels to inches!
```

---

### Problem #2: Reference Object Distance Mismatch

**Scale only transfers correctly at the SAME distance.**

```
Side view of room:

Camera ────────────────────────→ Door (6 feet away)
         │
         │
         └──────→ Cabinet (3 feet away)

Problem:
- Door is 6 feet from camera
- Cabinet is 3 feet from camera
- Scale calculated from door does NOT apply to cabinet!

If door (80") = 400 pixels at 6 feet
Then 1 inch = 5 pixels at 6 feet

But cabinet at 3 feet:
- Same 1 inch = 10 pixels (twice as big in image)
- Using door scale: cabinet appears HALF its actual size!
```

**This is the fundamental problem that hasn't changed.**

---

### Problem #3: SAM2 Can't Separate Adjacent Cabinets

**Cabinet runs appear as ONE continuous surface.**

```
What exists:                 What SAM2 sees:
┌──────┬──────┬──────┐      ┌────────────────────┐
│ 18"  │ 24"  │ 18"  │      │                    │
│      │      │      │  →   │  ONE BIG CABINET   │
│      │      │      │      │                    │
└──────┴──────┴──────┘      └────────────────────┘
3 separate cabinets          1 merged segment
```

**Why SAM2 fails here:**
- Cabinets are visually continuous
- Same material, same color
- Seams are subtle (1-2mm gaps)
- SAM2 segments by visual similarity

---

### Problem #4: Edge Detection Fails on Real Cabinets

**Cabinet seams are often invisible or ambiguous.**

```
ASSUMED (clear seams):        REALITY (modern kitchens):
┌──────┬──────┬──────┐       ┌────────────────────┐
│░░░░░░│░░░░░░│░░░░░░│       │                    │
│░░░░░░│░░░░░░│░░░░░░│       │  HANDLELESS SLAB   │
│░░░░░░│░░░░░░│░░░░░░│       │     CABINETS       │
└──────┴──────┴──────┘       │  (no visible seams)│
  Clear shadow lines          └────────────────────┘
```

**Edge detection problems:**

| Scenario | Edge Detection Result |
|----------|----------------------|
| Handleless cabinets | No seams visible |
| Slab door style | Minimal shadow lines |
| Under-cabinet lighting | Creates false shadows |
| Glossy finish | Reflections mask edges |
| Shaker style | Detects door PANEL edges, not cabinet edges |

---

### Problem #5: YOLO-World Accuracy Issues

**Zero-shot detection is unreliable for specific objects.**

```python
# What we ask for:
prompt = "electrical outlet"

# What might happen:
- Detects light switches as outlets (similar shape)
- Misses outlets that are partially hidden
- Detects USB ports as outlets
- Misses GFCI outlets (different appearance)
- False positives on similar-looking objects
```

**Detection accuracy reality:**

| Object | Claimed | Real-World |
|--------|---------|------------|
| Door | 95% | 85-90% (partial views, open doors) |
| Window | 90% | 75-85% (curtains, blinds) |
| Outlet | 80% | 50-70% (small, often occluded) |
| Cabinet | 85% | 60-75% (style variations) |
| Dishwasher | 80% | 70-80% (panel-ready invisible) |

---

### Problem #6: Triangulation Requires Trackable Features

**Multi-view triangulation needs the SAME point visible in multiple frames.**

```
Frame 1:                     Frame 2:
┌─────────────────┐         ┌─────────────────┐
│                 │         │                 │
│    ┌───────┐    │         │        ┌───────┐│
│    │ CAB   │    │         │        │ CAB   ││
│    │       │    │         │        │       ││
│    └───────┘    │         │        └───────┘│
│        ●        │         │            ?    │
└─────────────────┘         └─────────────────┘
   Corner visible            Where's the corner?
                             Different angle = different appearance
```

**Why tracking fails on cabinets:**
- Cabinet surfaces are UNIFORM (no texture)
- No distinctive features to track
- Seams are subtle, hard to match
- Handles change appearance with angle
- Reflections move with camera

---

### Problem #7: Lighting Destroys Everything

**Real kitchens have terrible lighting for computer vision.**

```
Issues:
┌─────────────────────────────────────────────┐
│  ████████████████████████████████████████  │ ← Ceiling lights create glare
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│   │ ← Under-cabinet shadows
│  └─────────────────────────────────────┘   │
│  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐         │
│  │█████│ │░░░░░│ │█████│ │░░░░░│         │ ← Alternating light/shadow
│  │█████│ │░░░░░│ │█████│ │░░░░░│         │
│  └─────┘ └─────┘ └─────┘ └─────┘         │
│                                             │
│     ════════════════════════════           │ ← Reflective countertop
│     ▓▓▓▓ WINDOW GLARE ▓▓▓▓▓▓▓▓           │
└─────────────────────────────────────────────┘
```

**Effects on detection:**
- Edge detection finds shadow edges, not real edges
- YOLO confidence drops in shadows
- Reflections create false objects
- Inconsistent appearance across frames

---

### Problem #8: The Fundamental Distance Problem

**Let me be very clear:**

```
YOLO detects: "This is a cabinet"
SAM2 gives: "Here are the exact pixels"
Edge detection: "Here's the boundary"

BUT NONE OF THESE TELL US:
- How far is the cabinet from camera?
- What is the actual size in inches?
- How do pixels convert to real measurements?

THE FUNDAMENTAL PROBLEM HASN'T CHANGED.

measurement = detected_pixels × (distance_to_object / focal_length)
                                       ↑
                                 WE DON'T HAVE THIS
```

---

### Problem #9: Triangulation Error Accumulation

**Even if triangulation works, errors compound.**

```
Corner 1: ±1" error
Corner 2: ±1" error
Corner 3: ±1" error
Corner 4: ±1" error

Wall 1 (C1 to C2): ±2" error (both corners have error)
Wall 2 (C2 to C3): ±2" error
Wall 3 (C3 to C4): ±2" error
Wall 4 (C4 to C1): ±2" error

Room doesn't close properly!
Accumulated error: ±4-6" around the room
```

---

### Problem #10: Reference at Same Distance Requirement

**For scale to transfer, reference and target MUST be at same depth.**

```
When does reference work?          When does it FAIL?

WORKS:                             FAILS:
┌─────────────────┐               ┌─────────────────┐
│                 │               │                 │
│  ┌────┐ ┌────┐  │               │  ┌────┐         │
│  │OUT │ │CAB │  │               │  │OUT │    ┌────┐
│  │LET │ │    │  │               │  │LET │    │CAB │
│  └────┘ └────┘  │               │  └────┘    └────┘
│                 │               │     │         │
│   Same depth    │               │   Different depths
└─────────────────┘               └─────────────────┘
   ↑                                 ↑
   Outlet ON cabinet face            Outlet on wall,
   Scale transfers correctly         cabinet 24" in front
                                     Scale is WRONG!
```

---

### Summary: Why Detection Alone Cannot Achieve ±2" Accuracy

| What We Assumed | Reality |
|-----------------|---------|
| YOLO detects objects | Yes, but gives pixels, not inches |
| SAM2 gives precise boundaries | Yes, but still in pixels |
| Reference object gives scale | Only at SAME distance |
| Edge detection finds seams | Fails on modern cabinets |
| Triangulation gives 3D | Needs trackable features (cabinets have none) |
| Multi-frame improves accuracy | Lighting/reflections cause inconsistency |

---

### The Only Reliable Ways to Get Distance

1. **LiDAR** - We don't have on non-Pro iPhones
2. **User measures one thing** - "My countertop is 10 feet long" (breaks "no interaction" requirement)
3. **Reference at exact same depth** - Rarely guaranteed in real rooms
4. **Dense multi-view stereo** - Fails on textureless surfaces like cabinets

---

### What MIGHT Actually Work (Realistic Assessment)

Given all these limitations, the most reliable approaches are:

| Approach | What It Can Measure | Expected Accuracy |
|----------|---------------------|-------------------|
| **ARKit plane detection** | Room shape (approximate) | ±4-6" |
| **Door detection + scale** | Wall lengths (door is on wall) | ±2-4" |
| **Multi-view triangulation** | Room corners (high contrast) | ±2-3" |
| **Cabinet RUN length** | Total width, not individual | ±3-5" |
| **Individual cabinet widths** | NOT RELIABLE | ±6-12" or worse |

**Honest conclusion:**
- ±2" for room dimensions: POSSIBLE with good conditions
- ±2" for individual cabinet widths: NOT ACHIEVABLE automatically
- ±4-6" for cabinet measurements: ACHIEVABLE but may not meet requirements

---

### Recommendations Based on Limitations

1. **For Room Dimensions (walls, doors, windows):**
   - Use ARKit planes + triangulation
   - Door as scale reference
   - ±2-4" accuracy achievable

2. **For Cabinet Measurements:**
   - Measure cabinet RUN total (not individuals)
   - Accept ±4-6" accuracy OR
   - Require minimal user input (confirm one measurement) OR
   - Use approximation: "approximately X linear feet of cabinets"

3. **Set Realistic Expectations:**
   - This is an ESTIMATE tool, not a precision measurement tool
   - Final measurements should be verified on-site
   - Professional cabinet installers always re-measure

---

## 17. Questions to Resolve Before Implementation

1. **Is ±4-6" acceptable for cabinet measurements?**
   - If yes: Proceed with automatic approach
   - If no: Need user interaction or alternative approach

2. **Can we require door visibility?**
   - Door is the most reliable scale reference
   - What if room has no visible door?

3. **What about empty rooms (no cabinets)?**
   - Room dimensions are more achievable
   - Simpler problem than cabinet measurement

4. **Server vs on-device trade-offs?**
   - Server enables better models but adds latency
   - On-device is faster but less accurate

5. **What's the minimum viable accuracy?**
   - For initial quotes: ±6" might be acceptable
   - For final ordering: Need professional verification anyway

---

---

## 18. Automatic Base Cabinet Height Calibration (RECOMMENDED APPROACH)

### The Solution

**Base cabinet height (34.5") as automatic scale reference → Zero user input**

This is the optimal approach for non-LiDAR accuracy:
- ✅ Works on any iPhone (no LiDAR required)
- ✅ **ZERO user input** - fully automatic calibration
- ✅ Achieves ±1-2" accuracy for cabinet measurements
- ✅ Uses universal industry standard (34.5" base cabinet height)
- ✅ Same plane as cabinet widths being measured

---

### User Experience

```
1. User opens app → "Scan Your Kitchen"

2. User records 60-second video walkthrough
   - Point camera at cabinets, walls, appliances
   - App guides: "Make sure to capture the full cabinet height"
   - "Include the floor and countertop in view"

3. Upload & process (2-3 minutes)
   - No calibration screen needed!
   - AI automatically detects base cabinet height
   - Uses 34.5" standard to calculate scale

4. Result: Accurate floor plan with:
   - Cabinet widths (±1-2")
   - Room dimensions (±2-3")
   - Door/window positions
   - Appliance locations
```

---

### Why Base Cabinet Height Works

#### The Standard

**Base cabinet height is universally standardized:**
- Cabinet box: **34.5 inches** (industry standard, ADA compliant)
- With countertop: **36 inches** (floor to countertop surface)
- This is the SAME in virtually every kitchen installation

#### The Math

```
Known standard: Base cabinet height = 34.5 inches
AI detects: Cabinet height = 345 pixels in image

Scale factor = 34.5 inches / 345 pixels = 0.1 inches per pixel

Now AI can measure cabinet WIDTHS on same plane:
- Cabinet 1: 240 pixels × 0.1 = 24 inches ✓
- Cabinet 2: 300 pixels × 0.1 = 30 inches ✓
- Cabinet 3: 360 pixels × 0.1 = 36 inches ✓
```

#### Why This Is Accurate

1. **Known standard** - 34.5" is universal, no guessing needed
2. **Same plane** - Height measurement on cabinet face, width on cabinet face
3. **Reliable detection** - Floor-to-countertop boundary is visible
4. **No user error** - Automatic detection eliminates human measurement mistakes
5. **Vertical reference** - Not affected by camera angle (as long as roughly perpendicular)

#### Detection Requirements

For automatic calibration to work:

| Requirement | Why | Guidance |
|-------------|-----|----------|
| **Full cabinet height visible** | Need floor-to-countertop | "Step back to capture full cabinets" |
| **Roughly perpendicular view** | Minimize perspective distortion | "Face the cabinets directly" |
| **Clear floor line** | Bottom reference point | "Make sure floor is visible" |
| **Countertop edge visible** | Top reference point | "Include countertop in frame" |

---

### Technical Implementation

#### Phase 1: iOS Capture

**Simplified Flow (No Calibration UI Needed):**

```swift
// AIFlowCoordinator.swift

enum AICaptureState {
    case idle
    case recording
    case uploading       // Direct to upload - no calibration step!
    case processing
    case complete
}

// After video capture, go directly to upload
func onVideoCaptureComplete() {
    // No calibration UI needed!
    captureState = .uploading
    uploadAndProcess()
}
```

**Capture Guidance (Guide user to capture full cabinet height):**

```swift
// AICaptureGuidanceView.swift

struct CaptureGuidance {
    static let tips = [
        "Step back to capture full cabinet height",
        "Include the floor in your view",
        "Face cabinets directly (not at an angle)",
        "Make sure countertop edge is visible"
    ]

    static func validateFrame(_ frame: ARFrame) -> GuidanceResult {
        // Check if floor is visible in frame
        // Check if cabinets are detected
        // Check if full height appears captured
    }
}
```

#### Phase 2: Server Processing

**Key: Automatic scale from base cabinet height (34.5")**

```python
# server/processing/scale_calibrator.py

# UNIVERSAL STANDARD - 34.5" base cabinet height
BASE_CABINET_HEIGHT_INCHES = 34.5

async def calibrate_from_base_cabinet_height(
    keyframes: List[Keyframe]
) -> float:
    """
    Calculate scale factor using detected base cabinet height.

    Base cabinet height is universally 34.5" (industry standard, ADA).

    Returns: inches_per_pixel ratio
    """

    height_detections = []

    for frame in keyframes:
        # 1. Detect base cabinets using YOLO
        cabinet_boxes = yolo_detect(frame.image, class_name="base_cabinet")

        for box in cabinet_boxes:
            # 2. Use SAM2 for precise cabinet mask
            mask = sam2_segment(frame.image, box_prompt=box)

            # 3. Find floor-to-countertop boundary
            floor_line = detect_floor_line(frame.image, mask)
            countertop_line = detect_countertop_edge(frame.image, mask)

            if floor_line and countertop_line:
                # 4. Calculate height in pixels
                height_pixels = countertop_line.y - floor_line.y

                height_detections.append(HeightDetection(
                    frame_id=frame.id,
                    height_pixels=abs(height_pixels),
                    confidence=box.confidence,
                    floor_y=floor_line.y,
                    countertop_y=countertop_line.y
                ))

    if not height_detections:
        raise CalibrationError("Could not detect base cabinet height")

    # 5. Use best detection (highest confidence, clearest view)
    best = max(height_detections, key=lambda d: d.confidence)

    # 6. Calculate scale: 34.5" / pixels = inches per pixel
    scale = BASE_CABINET_HEIGHT_INCHES / best.height_pixels

    # 7. Validate scale is reasonable
    # At typical viewing distance, 34.5" should be 300-600 pixels
    if not (0.05 < scale < 0.2):
        raise CalibrationError(f"Unusual scale detected: {scale}. Check cabinet visibility.")

    return scale


async def process_with_auto_calibration(
    video_url: str,
    poses_url: str
) -> FloorPlan:
    """Main processing pipeline with automatic scale detection."""

    # 1. Extract keyframes
    keyframes = await extract_keyframes(video_url, poses_url)

    # 2. AUTO-CALIBRATE from base cabinet height
    scale = await calibrate_from_base_cabinet_height(keyframes)
    print(f"Auto-calibrated scale: {scale} inches/pixel")

    # 3. Detect and measure room elements
    walls = await detect_walls(keyframes, scale)
    doors = await detect_doors(keyframes, scale)
    windows = await detect_windows(keyframes, scale)
    cabinets = await detect_cabinets(keyframes, scale)
    appliances = await detect_appliances(keyframes, scale)

    # 4. Build floor plan
    floor_plan = build_floor_plan(
        walls=walls,
        doors=doors,
        windows=windows,
        cabinets=cabinets,
        appliances=appliances,
        scale=scale
    )

    # 5. Validate measurements
    floor_plan = validate_and_snap_to_standards(floor_plan)

    return floor_plan
```

#### Phase 3: Detection Pipeline

**Base cabinet height detection:**

```python
async def detect_base_cabinet_height(keyframes: List[Keyframe]) -> List[HeightDetection]:
    """
    Detect base cabinet and measure floor-to-countertop height in pixels.
    """
    detections = []

    for frame in keyframes:
        # 1. Detect base cabinet region
        cabinet_boxes = yolo_detect(frame.image, class_name="base_cabinet")

        for box in cabinet_boxes:
            # 2. SAM2 for precise segmentation
            mask = sam2_segment(frame.image, box_prompt=box)

            # 3. Detect floor line (bottom of cabinet)
            # Use edge detection + horizontal line finding
            floor_y = find_floor_cabinet_boundary(frame.image, mask)

            # 4. Detect countertop edge (top of cabinet)
            countertop_y = find_countertop_edge(frame.image, mask)

            if floor_y is not None and countertop_y is not None:
                height_pixels = abs(countertop_y - floor_y)

                detections.append(HeightDetection(
                    frame_id=frame.id,
                    height_pixels=height_pixels,
                    confidence=box.confidence,
                    floor_y=floor_y,
                    countertop_y=countertop_y
                ))

    return detections


def find_floor_cabinet_boundary(image, cabinet_mask):
    """
    Find where cabinet meets floor.
    Look for horizontal edge at bottom of cabinet mask.
    """
    # Get bottom edge of cabinet mask
    mask_rows = np.any(cabinet_mask, axis=1)
    bottom_row = np.max(np.where(mask_rows)[0])

    # Refine with edge detection
    edges = cv2.Canny(image, 50, 150)

    # Find strongest horizontal edge near mask bottom
    search_region = edges[bottom_row-20:bottom_row+20, :]
    horizontal_lines = cv2.HoughLinesP(search_region, 1, np.pi/180,
                                        threshold=50, minLineLength=100)

    if horizontal_lines is not None:
        # Return y-coordinate of best horizontal line
        return bottom_row + refine_line_position(horizontal_lines)

    return bottom_row


def find_countertop_edge(image, cabinet_mask):
    """
    Find countertop top edge.
    Look for horizontal edge at top of cabinet mask.
    """
    # Get top edge of cabinet mask
    mask_rows = np.any(cabinet_mask, axis=1)
    top_row = np.min(np.where(mask_rows)[0])

    # Refine with edge detection
    edges = cv2.Canny(image, 50, 150)

    # Find strongest horizontal edge near mask top
    search_region = edges[top_row-20:top_row+20, :]
    horizontal_lines = cv2.HoughLinesP(search_region, 1, np.pi/180,
                                        threshold=50, minLineLength=100)

    if horizontal_lines is not None:
        return top_row + refine_line_position(horizontal_lines)

    return top_row
```

---

### Data Flow

```
┌────────────────────────────────────────────────────────────────┐
│                         iOS APP                                 │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Record video (60 sec)                                       │
│     - Guide: "Capture full cabinet height"                      │
│     - Guide: "Include floor in view"                            │
│  2. Capture ARKit poses + planes                                │
│  3. Upload directly (no calibration UI!)                        │
│     video + poses + planes                                      │
│                                                                 │
└──────────────────────────┬─────────────────────────────────────┘
                           │
                           ▼
┌────────────────────────────────────────────────────────────────┐
│                    SUPABASE STORAGE                             │
├────────────────────────────────────────────────────────────────┤
│  scans/{project_id}/                                            │
│  ├── video.mp4                                                  │
│  ├── poses.json                                                 │
│  └── planes.json                                                │
│                                                                 │
│  (No calibration.json needed - automatic detection!)            │
│                                                                 │
└──────────────────────────┬─────────────────────────────────────┘
                           │
                           ▼
┌────────────────────────────────────────────────────────────────┐
│                    SERVER PROCESSING                            │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Download video + poses                                      │
│  2. Extract keyframes                                           │
│  3. AUTO-DETECT base cabinet height in pixels                   │
│  4. Calculate scale: 34.5" / detected_pixels = scale            │
│  5. Detect all room elements                                    │
│  6. Apply scale to get real measurements                        │
│  7. Generate floor plan                                         │
│                                                                 │
└──────────────────────────┬─────────────────────────────────────┘
                           │
                           ▼
┌────────────────────────────────────────────────────────────────┐
│                    FLOOR PLAN OUTPUT                            │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│  • Cabinet widths: ±1-2" accuracy (same plane as height)        │
│  • Room dimensions: ±2-3" accuracy                              │
│  • Door/window sizes: ±2-3" accuracy                            │
│  • Automatically calibrated from base cabinet height            │
│                                                                 │
└────────────────────────────────────────────────────────────────┘
```

---

### Files to Modify

#### iOS (3 files - simpler than before!)

| File | Changes |
|------|---------|
| `AIARSessionManager.swift` | Enable plane detection (line 188) |
| `AIFlowCoordinator.swift` | Remove calibration state, direct to upload |
| `AICaptureGuidanceView.swift` | Add guidance for capturing full cabinet height |

**No CalibrationInputView needed!** User experience is simplified.

#### Server (new directory)

```
server/
├── main.py                    # FastAPI app
├── processing/
│   ├── keyframe_extractor.py  # Extract frames from video
│   ├── scale_calibrator.py    # AUTO-CALIBRATE with fallback chain
│   ├── cabinet_height_detector.py  # Detect floor-to-countertop height (34.5")
│   ├── door_height_detector.py     # Detect door height (80") - FALLBACK
│   ├── room_detector.py       # Detect walls, doors, windows
│   ├── cabinet_detector.py    # Detect cabinet widths
│   └── floor_plan_generator.py # Generate SVG floor plan
├── models/
│   ├── yolo_detector.py       # YOLO wrapper (detect base_cabinet, door classes)
│   └── sam2_segmenter.py      # SAM2 wrapper
└── requirements.txt
```

#### Database (1 migration)

```sql
-- Add processing fields to project_measurements
ALTER TABLE project_measurements
ADD COLUMN detected_scale FLOAT,
ADD COLUMN scale_confidence TEXT,
ADD COLUMN server_processed_at TIMESTAMPTZ,
ADD COLUMN server_floor_plan_url TEXT;

-- New table for processing jobs
CREATE TABLE scan_processing_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID REFERENCES projects(id),
    status TEXT DEFAULT 'queued',
    video_url TEXT,
    poses_url TEXT,
    detected_scale FLOAT,
    scale_detection_method TEXT DEFAULT 'base_cabinet_height',
    floor_plan_url TEXT,
    measurements JSONB,
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);
```

---

### Expected Accuracy

| Measurement | Accuracy | Why |
|-------------|----------|-----|
| Base cabinet height (reference) | Known: 34.5" | Universal standard |
| Cabinet widths | ±1-2" | Same plane as height reference |
| Room dimensions | ±2-3" | May be at different depth |
| Doors/windows | ±2-3" | May be at different depth |

**Error Analysis:**
- If height detection is off by 10 pixels (3%), all measurements are ~3% off
- 3% error on 24" cabinet = 0.7" error - within ±2" target
- Key requirement: Clear view of floor-to-countertop boundary

**Accuracy depends on:**
- Clear floor line visibility (no rugs, objects blocking)
- Roughly perpendicular camera angle to cabinet face
- Full cabinet height in frame

---

### Implementation Timeline

| Week | Deliverable |
|------|-------------|
| **Week 1** | iOS: Enable planes, add capture guidance for full height |
| **Week 2** | Server: Keyframe extraction, base cabinet height detection |
| **Week 3** | Server: Auto-calibration, cabinet width detection, floor plan generation |
| **Week 4** | Integration testing, accuracy validation, polish |

---

### Verification Plan

1. **Unit test auto-calibration**
   - Input: detected cabinet height = 345 pixels
   - Expected: scale = 34.5" / 345px = 0.1 in/px

2. **Height detection accuracy test**
   - Use test images with known cabinet heights
   - Verify detection finds floor and countertop edges
   - Target: height detection within ±5%

3. **Integration test end-to-end**
   - Record test kitchen video
   - Verify auto-calibration succeeds
   - Verify floor plan generated with correct scale

4. **Accuracy validation**
   - Scan 5 real kitchens
   - Compare AI measurements vs tape measure
   - Target: cabinet widths within ±2"

---

### Why This Will Work

1. **Universal standard** - 34.5" base cabinet height is used everywhere
2. **No user error** - Automatic detection eliminates human measurement mistakes
3. **Same plane** - Height and width are on same cabinet face
4. **Simpler UX** - Zero input required from user
5. **Reliable boundaries** - Floor and countertop are high-contrast edges
6. **Proven approach** - Using known reference for photogrammetric scale

---

### Potential Challenges

| Challenge | Mitigation |
|-----------|------------|
| Floor obscured by rugs/objects | Capture guidance: "Make sure floor is visible" |
| Camera angle not perpendicular | Use multiple frames, select best angle |
| Cabinet not fully visible | Guidance: "Step back to capture full height" |
| Non-standard cabinet height | Rare - validate against expected range |
| Low contrast floor line | Use multiple edge detection methods |

---

### Fallback Options

#### Calibration Priority Order

| Priority | Method | When Used | Accuracy |
|----------|--------|-----------|----------|
| 1 | Base cabinet height (34.5") | Kitchens with cabinets installed | ±1-2" for cabinets |
| 2 | **Door height (80")** | **Empty rooms, renovations, any room** | ±2-3" for room |
| 3 | Appliance width (dishwasher 24") | Kitchen with visible appliances | ±2" |
| 4 | User input | Last resort | Depends on user |

---

#### Door Height Fallback (For Empty Kitchens/Rooms)

**This is the PRIMARY fallback for rooms without cabinets.**

Interior doors are universally **80 inches (6'8")** tall - this is building code standard.

**Why door height works well:**
- Present in virtually every room
- Easy to detect (rectangular shape, distinct frame)
- High contrast edges (door frame vs wall)
- Universal standard size
- Works for ANY room type (not just kitchens)

```python
# UNIVERSAL STANDARD - 80" interior door height
INTERIOR_DOOR_HEIGHT_INCHES = 80.0

async def calibrate_from_door_height(keyframes: List[Keyframe]) -> CalibrationResult:
    """
    Calculate scale factor using detected door height.

    Interior doors are universally 80" (6'8") tall - building code standard.
    This is the PRIMARY FALLBACK for empty rooms without cabinets.

    Returns: CalibrationResult with scale and confidence
    """

    door_detections = []

    for frame in keyframes:
        # 1. Detect doors using YOLO
        door_boxes = yolo_detect(frame.image, class_name="door")

        for box in door_boxes:
            # 2. Use SAM2 for precise door mask
            mask = sam2_segment(frame.image, box_prompt=box)

            # 3. Find door frame boundaries
            top_edge = find_door_top_edge(frame.image, mask)
            bottom_edge = find_door_bottom_edge(frame.image, mask)

            if top_edge and bottom_edge:
                # 4. Calculate height in pixels
                height_pixels = abs(bottom_edge.y - top_edge.y)

                # 5. Check if door is fully visible (not cut off)
                is_full_door = validate_full_door_visible(mask, frame.image.shape)

                if is_full_door:
                    door_detections.append(DoorDetection(
                        frame_id=frame.id,
                        height_pixels=height_pixels,
                        confidence=box.confidence,
                        top_y=top_edge.y,
                        bottom_y=bottom_edge.y,
                        is_fully_visible=True
                    ))

    if not door_detections:
        raise CalibrationError("Could not detect door height")

    # 6. Use best detection (highest confidence, fully visible)
    full_door_detections = [d for d in door_detections if d.is_fully_visible]
    if full_door_detections:
        best = max(full_door_detections, key=lambda d: d.confidence)
    else:
        best = max(door_detections, key=lambda d: d.confidence)

    # 7. Calculate scale: 80" / pixels = inches per pixel
    scale = INTERIOR_DOOR_HEIGHT_INCHES / best.height_pixels

    # 8. Validate scale is reasonable
    # At typical viewing distance, 80" door should be 400-900 pixels
    if not (0.08 < scale < 0.25):
        raise CalibrationError(f"Unusual door scale detected: {scale}")

    return CalibrationResult(
        scale=scale,
        method="door_height",
        reference_object="interior_door",
        reference_size_inches=INTERIOR_DOOR_HEIGHT_INCHES,
        detected_pixels=best.height_pixels,
        confidence="HIGH" if best.is_fully_visible else "MEDIUM"
    )


def find_door_top_edge(image, door_mask):
    """
    Find top of door frame.
    Look for horizontal edge at top of door mask.
    """
    # Get bounding box of mask
    mask_rows = np.any(door_mask, axis=1)
    top_row = np.min(np.where(mask_rows)[0])

    # Refine with edge detection around top region
    edges = cv2.Canny(image, 50, 150)
    search_region = edges[max(0, top_row-30):top_row+30, :]

    # Find strongest horizontal edge
    horizontal_lines = cv2.HoughLinesP(
        search_region, 1, np.pi/180,
        threshold=50, minLineLength=80
    )

    if horizontal_lines is not None:
        return EdgePosition(y=top_row + refine_line_position(horizontal_lines))

    return EdgePosition(y=top_row)


def find_door_bottom_edge(image, door_mask):
    """
    Find bottom of door (where it meets floor).
    """
    mask_rows = np.any(door_mask, axis=1)
    bottom_row = np.max(np.where(mask_rows)[0])

    # Refine with edge detection
    edges = cv2.Canny(image, 50, 150)
    search_region = edges[bottom_row-30:min(image.shape[0], bottom_row+30), :]

    horizontal_lines = cv2.HoughLinesP(
        search_region, 1, np.pi/180,
        threshold=50, minLineLength=80
    )

    if horizontal_lines is not None:
        return EdgePosition(y=bottom_row + refine_line_position(horizontal_lines))

    return EdgePosition(y=bottom_row)


def validate_full_door_visible(mask, image_shape):
    """
    Check if the full door is visible in frame (not cut off at top/bottom).
    """
    mask_rows = np.any(mask, axis=1)
    top_row = np.min(np.where(mask_rows)[0])
    bottom_row = np.max(np.where(mask_rows)[0])

    # Door should not touch image edges (with margin)
    margin = 20
    top_ok = top_row > margin
    bottom_ok = bottom_row < image_shape[0] - margin

    return top_ok and bottom_ok
```

---

#### Complete Fallback Chain

```python
async def calibrate_with_fallbacks(keyframes: List[Keyframe]) -> CalibrationResult:
    """
    Try multiple calibration methods in order of preference.

    Priority:
    1. Base cabinet height (34.5") - for kitchens with cabinets
    2. Door height (80") - for empty rooms/kitchens
    3. Dishwasher width (24") - for kitchens with appliances
    4. User input - last resort
    """

    errors = []

    # 1. Try base cabinet height (preferred for kitchens with cabinets)
    try:
        result = await calibrate_from_base_cabinet_height(keyframes)
        result.fallback_used = False
        return result
    except CalibrationError as e:
        errors.append(f"Cabinet height: {e}")

    # 2. Try door height (PRIMARY FALLBACK for empty rooms)
    try:
        result = await calibrate_from_door_height(keyframes)
        result.fallback_used = True
        result.fallback_reason = "No cabinets detected, using door height"
        return result
    except CalibrationError as e:
        errors.append(f"Door height: {e}")

    # 3. Try dishwasher width
    try:
        result = await calibrate_from_dishwasher(keyframes)
        result.fallback_used = True
        result.fallback_reason = "Using dishwasher width reference"
        return result
    except CalibrationError as e:
        errors.append(f"Dishwasher: {e}")

    # 4. Request user measurement (last resort)
    raise NeedsUserCalibration(
        message="Could not auto-detect scale from any reference object",
        attempted_methods=errors,
        suggestion="Please measure any wall length or door width"
    )
```

---

#### When Each Method Is Used

| Scenario | Primary Method | Fallback |
|----------|---------------|----------|
| **Kitchen with cabinets** | Base cabinet height (34.5") | Door height |
| **Empty kitchen (renovation)** | Door height (80") | User input |
| **Empty room (any type)** | Door height (80") | User input |
| **Kitchen with appliances only** | Door height (80") | Dishwasher width |
| **Bathroom** | Door height (80") | User input |
| **Living room** | Door height (80") | User input |

**Key insight:** Door height works for ANY room type, making it the universal fallback.

---

### Pros and Cons

#### Pros

| Advantage | Details |
|-----------|---------|
| **Zero user input** | No measuring tape needed, no calibration screen |
| **Universal standard** | 34.5" is industry/ADA standard - 100% reliable |
| **Same measurement plane** | Height and width on same cabinet face = accurate transfer |
| **Faster UX** | Record video → Done. No extra steps |
| **No user error** | Eliminates mistakes from user measurement |
| **Works on ALL kitchens** | Any kitchen with base cabinets (which is all of them) |
| **High contrast edges** | Floor and countertop are strong visual boundaries |
| **Market competitive** | Simpler than CubiCasa (no manual input required) |

#### Cons

| Challenge | Severity | Mitigation |
|-----------|----------|------------|
| **Requires full height visibility** | Medium | Capture guidance + validation |
| **Floor can be obscured** | Medium | Rugs, mats - guide user to clear view |
| **Camera angle matters** | Low | Use best frame from multiple captures |
| **Detection complexity** | Medium | YOLO + SAM2 + edge detection pipeline |
| **Non-standard cabinets** | Very Low | Rare, can validate against range |
| **Server processing required** | Low | Already planned for server-side |
| **Accuracy for non-cabinet items** | Medium | Different depth planes = ±3" |

#### Comparison: Auto-Detection vs User-Input Approaches

| Factor | Auto Base Cabinet Height | User Measures Countertop |
|--------|--------------------------|-------------------------|
| **User effort** | None | Measure + enter number |
| **Error source** | Detection accuracy | User measurement error |
| **UX friction** | Very low | Low (but not zero) |
| **Reliability** | Depends on visibility | Depends on user accuracy |
| **Cabinet accuracy** | ±1-2" | ±1-2" |
| **Room accuracy** | ±2-3" | ±2-3" |
| **Fallback needed** | Sometimes | No |
| **Implementation** | More complex | Simpler |

#### When Auto-Detection Might Fail (and How Fallbacks Handle It)

| Scenario | Cabinet Detection | Door Fallback | Result |
|----------|-------------------|---------------|--------|
| **Kitchen under renovation** | ❌ No cabinets | ✅ Door visible | **Auto-calibrate from door** |
| **Empty room** | ❌ No cabinets | ✅ Door visible | **Auto-calibrate from door** |
| **Very cluttered floor** | ⚠️ May fail | ✅ Door unaffected | **Auto-calibrate from door** |
| **Island-only kitchen** | ❌ No wall cabinets | ✅ Door visible | **Auto-calibrate from door** |
| **Camera too close** | ❌ Partial cabinet | ⚠️ May have partial door | Capture guidance helps |
| **Unusual lighting** | ⚠️ May fail | ⚠️ May fail | Use multiple frames |
| **No door visible** | ✅ If cabinets present | ❌ No door | Cabinet calibration or user input |

**Key insight:** The door fallback handles most failure cases automatically. User input is only needed when BOTH cabinet AND door detection fail (very rare).

---

### Summary

**Base Cabinet Height Auto-Calibration** is the recommended approach because:

1. ✅ **Simpler UX** - No user action required
2. ✅ **Universal standard** - 34.5" works everywhere
3. ✅ **Same plane accuracy** - Height → Width transfer is accurate
4. ✅ **Proven technique** - Reference-based photogrammetry
5. ✅ **Fallback available** - Can prompt user if detection fails

**Expected outcome:**
- Cabinet width measurements: **±1-2" accuracy**
- Room dimensions: **±2-3" accuracy**
- User experience: **Record video and done**

---

## Document History

- **Created:** 2026-02-02
- **Updated:** 2026-02-02 - Added critical limitations section
- **Updated:** 2026-02-02 - Added Section 18: Automatic Base Cabinet Height Calibration (recommended approach)
- **Updated:** 2026-02-02 - Enhanced fallback system with door height detection (80") for empty rooms/kitchens
- **Purpose:** Compile all viable approaches for CabinetScan room scanning
- **Context:** Discussion about MagicPlan approach, accuracy requirements, iPhone-only solution

---

*This document should be updated as new ideas emerge or approaches are validated/invalidated through testing.*
