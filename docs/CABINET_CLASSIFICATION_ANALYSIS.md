# Cabinet Classification Improvement Plan

## Executive Summary

The current RoomPlan post-processing logic has several fundamental issues that cause incorrect cabinet classification. This plan outlines industry standards, identifies bugs, and proposes a robust detection system.

---

## Part 1: Industry Standard Cabinet Dimensions

### Base Cabinets (Lower)
| Attribute | Standard Value |
|-----------|---------------|
| Height | 34.5" (without countertop) |
| Height with countertop | 36" |
| Depth | 24" (standard), 27" (for large cooktops) |
| Width | 12", 15", 18", 21", 24", 30", 33", 36", 48" |
| Toe kick | 4.5" |

### Upper/Wall Cabinets
| Attribute | Standard Value |
|-----------|---------------|
| Height | 12", 15", 18", 30", 36", 42" |
| Depth | 12" (standard), 24" (above fridge) |
| Width | 9" - 36" |
| Distance from countertop | 15" - 20" (backsplash area) |
| Height from floor | 54" (bottom of cabinet) |

### Tall/Pantry Cabinets
| Attribute | Standard Value |
|-----------|---------------|
| Height | 84", 90", or 96" |
| Depth | 12" (canned goods) or 24" (full depth) |
| Width | 12", 18", 24", 30", 36" |
| Note | Floor to near-ceiling, single unit |

### Wall Oven Cabinets
| Attribute | Standard Value |
|-----------|---------------|
| Height | 84" - 96" |
| Width | 30", 33" (most common) |
| Depth | 24" |
| Oven cutout (single) | 27.25" - 28" |
| Oven cutout (double) | 50.25" - 51.875" |
| Note | Contains BUILT-IN OVEN only, NOT a stove/cooktop |

### Cooktop Base Cabinet (Under Stove)
| Attribute | Standard Value |
|-----------|---------------|
| Height | 34.5" |
| Width | 30" or 36" |
| Depth | 24" |
| Features | 2-3 drawers for pots/pans storage |
| Note | Has cutout on top for cooktop, storage drawers below |

### Range Hood
| Attribute | Standard Value |
|-----------|---------------|
| Height from cooktop | 24" - 30" (gas), 20" - 24" (electric) |
| Width | 30" - 48" (matches cooktop width) |
| Depth | 18" - 24" (shallower than cabinets) |
| Height | 4" - 18" (under-cabinet), 24" - 29" (wall mount) |

### Corner Cabinets
| Type | Width | Notes |
|------|-------|-------|
| Lazy Susan | 33" - 36" | Rotating shelves |
| Blind Corner | 36" - 42" | Pull-out mechanism |
| Diagonal | 24" deep | Angled door |

---

## Part 2: RoomPlan API Limitations

### Available Object Categories (16 total)
```
storage, refrigerator, stove, oven, dishwasher,
washerDryer, sink, bathtub, toilet, fireplace,
table, sofa, chair, bed, television, stairs
```

### What RoomPlan CANNOT Detect
- **Range hoods** (no category exists)
- **Cabinet types** (all detected as generic "storage")
- **Cooktop vs Stove vs Oven distinctions**:
  - `stove` = Freestanding range (cooktop + oven combo)
  - `oven` = Built-in wall oven
  - No separate "cooktop" category

### Detection Accuracy (per Apple)
- Refrigerator, stove, oven, sink: > 93% precision/recall
- Storage: Lower accuracy, all cabinets lumped together

---

## Part 3: Current Code Issues

### Issue 1: Stove Treated as Wall Oven (CRITICAL)
**Location:** Lines 1056-1064
```swift
case .stove:
    // Stoves at elevated positions might be wall ovens (RoomPlan sometimes misclassifies)
    if heightFromFloor > wallOvenMinHeight {
        wallOvenInfos.append(ovenInfo)  // WRONG!
    }
```

**Problem:**
- A **stove** is a freestanding range with cooktop on top + oven below
- A **wall oven** is a built-in oven in a tall cabinet (NO cooktop)
- These are completely different appliances
- An elevated stove is likely a **range hood** misdetected, not a wall oven

**Impact:** Kitchen with range + range hood gets classified as having wall oven cabinet

### Issue 2: Storage Under Stove Not Detected
**Location:** Lines 1056-1064

**Problem:**
- When a stove/cooktop is detected, the code only tracks its position for "small cabinet above" detection
- It does NOT look for storage/drawers BELOW the stove
- Cooktop base cabinets have 2-3 drawers underneath for pots/pans

**Expected:** Detect `cooktop_base_cabinet` with storage drawers

### Issue 3: Range Hood Misclassified as Wall Oven
**Location:** Lines 1048-1055, 1207-1295

**Problem:**
- RoomPlan has no "range hood" category
- Range hoods are box-shaped, above stove, at elevated height
- Current logic sees "elevated oven-like object above stove" → wall oven cabinet
- Range hoods are 18-24" deep, wall ovens are 24-27" deep

**Missing Check:** Depth validation to distinguish range hood from wall oven

### Issue 4: No Depth Validation for Any Classification
**Current logic uses:**
- Height above floor ✓
- X/Z alignment ✓
- Width (defined but NOT used) ✗
- **Depth (never checked)** ✗

**Problem:** Depth is critical for distinguishing:
- Range hood (18-24" deep) vs Wall oven (24"+ deep)
- Standard cabinet (24" deep) vs Shallow cabinet (12" deep)
- Upper cabinet (12" deep) vs Upper above fridge (24" deep)

### Issue 5: Width Thresholds Defined But Not Used
**Location:** Lines 1203-1205
```swift
let maxPantryWidth: Float = 0.76  // 30 inches - defined
let minWallOvenWidth: Float = 0.71  // 28 inches - defined but NEVER USED!
```

### Issue 6: Small Upper Cabinet Logic Never Called
**Location:** Lines 1178-1180, 1118-1133
```swift
let smallUpperCabinetMaxHeight: Float = 0.5  // 18 inches - defined
func isAboveApplianceOrSink() -> (Bool, String?)  // defined but NEVER CALLED
```

---

## Part 4: Proposed Classification System

### New Detection Phases (in order)

```
PHASE 0: RANGE HOOD EXCLUSION (NEW)
├── Above stove (X/Z aligned)
├── Height from floor >= 54" (above countertop level)
├── Depth <= 24" (shallow)
├── No storage cabinet directly below
└── → EXCLUDE from cabinet count (it's ventilation, not storage)

PHASE 1: WALL OVEN CABINET (FIXED)
├── Contains .oven object (NOT .stove!)
├── Oven height from floor >= 24" (not floor-level)
├── Has cabinet section ABOVE oven
├── Width >= 28" (minWallOvenWidth)
├── Depth >= 24" (full depth cabinet)
└── → wall_oven_cabinet

PHASE 2: COOKTOP BASE CABINET (NEW)
├── .stove detected at floor level (height < 24")
├── Storage object directly below OR aligned with stove
├── Width 30-36" (matches cooktop)
└── → cooktop_base_cabinet (with drawer storage)

PHASE 3: PANTRY CABINET (unchanged)
├── Upper + Lower vertically aligned
├── Gap < 6"
├── Total height >= 80"
├── Width <= 30"
├── No oven between sections
└── → pantry_cabinet

PHASE 4: UPPER CABINET
├── Height from floor > 39" (1.0m)
├── Not matched to wall_oven, pantry, or range_hood
├── Sub-classification:
│   ├── Height <= 18" AND above appliance → small_upper_cabinet
│   ├── Depth >= 24" AND above fridge → fridge_upper_cabinet
│   └── Standard → upper_cabinet
└── → upper_cabinet (with sub-type)

PHASE 5: LOWER CABINET
├── Height from floor <= 39" (1.0m)
├── Not matched to other categories
├── Sub-classification:
│   ├── Width 33-42" AND in corner → corner_cabinet
│   ├── Adjacent to sink → sink_base_cabinet
│   └── Standard → lower_cabinet (base_cabinet)
└── → lower_cabinet (with sub-type)
```

### Key Distinguishing Rules

| Object Above Stove | Depth | Has Cabinet Below | Classification |
|-------------------|-------|-------------------|----------------|
| Box shape | < 24" | No | **Range Hood** (exclude) |
| Box shape | >= 24" | Yes (upper cabinet) | **Wall Oven Cabinet** |
| No object | - | - | Standard stove area |

| Stove Type | Height from Floor | Has Storage Below | Classification |
|------------|------------------|-------------------|----------------|
| .stove | < 6" (floor level) | Yes | **Cooktop Base Cabinet** |
| .stove | < 6" (floor level) | No | Freestanding Range |
| .oven | >= 24" | Has cabinet above | **Wall Oven** |

---

## Part 5: Implementation Plan

### Step 1: Add New Data Structures
```swift
struct ApplianceInfo {
    let object: CapturedRoom.Object
    let category: CapturedRoom.Object.Category
    let position: SIMD4<Float>
    let dimensions: SIMD3<Float>
    let heightAboveFloor: Float
    let depthMeters: Float  // NEW: track depth
}

var rangeHoods: [ApplianceInfo] = []  // NEW: track excluded range hoods
var cooktopBaseCabinets: [[String: Any]] = []  // NEW: cabinets under cooktop
```

### Step 2: Fix Stove vs Oven Logic
```swift
case .stove:
    let info = ApplianceInfo(...)
    if heightFromFloor < 0.15 {  // Floor level (< 6")
        // This is a freestanding range or cooktop
        floorStoves.append(info)
        // Look for storage BELOW
    } else if heightFromFloor > 1.4 {  // > 54" - likely range hood
        possibleRangeHoods.append(info)
    }

case .oven:
    let info = ApplianceInfo(...)
    if heightFromFloor > wallOvenMinHeight {
        // True wall oven
        wallOvenInfos.append(info)
    }
```

### Step 3: Add Range Hood Detection Phase
```swift
// PHASE 0: Range Hood Exclusion
for stoveInfo in possibleRangeHoods {
    let depthInches = stoveInfo.dimensions.z * 39.37
    let isShallow = depthInches <= 24
    let isAboveStove = floorStoves.contains {
        areHorizontallyAligned($0.position, stoveInfo.position)
    }
    let hasNoCabinetBelow = !lowerStorageObjects.contains {
        areHorizontallyAligned($0.position, stoveInfo.position) &&
        $0.position.y < stoveInfo.position.y
    }

    if isShallow && isAboveStove && hasNoCabinetBelow {
        rangeHoods.append(stoveInfo)  // Exclude from cabinet count
        excludedPositions.insert(stoveInfo.position)
    }
}
```

### Step 4: Add Cooktop Base Cabinet Detection
```swift
// PHASE 2: Cooktop Base Cabinet
for stoveInfo in floorStoves {
    // Find storage directly below/aligned with stove
    for (idx, lowerInfo) in lowerStorageObjects.enumerated() {
        if areHorizontallyAligned(stoveInfo.position, lowerInfo.position) {
            var cabinetData = createBaseObjectData(for: lowerInfo.object)
            cabinetData["id"] = "cooktop_base_\(cooktopBaseIndex)"
            cabinetData["type"] = "cooktop_base_cabinet"
            cabinetData["has_cooktop_above"] = true
            cooktopBaseCabinets.append(cabinetData)
            matchedLowerIndices.insert(idx)
            cooktopBaseIndex += 1
        }
    }
}
```

### Step 5: Add Width/Depth Validation to Wall Oven
```swift
// In wall oven detection, add:
let cabinetDepthInches = topCabinet.info.dimensions.z * 39.37
let cabinetWidthInches = topCabinet.info.dimensions.x * 39.37

guard cabinetWidthInches >= 28 else {  // minWallOvenWidth
    print("[ScanAnalysis] Cabinet too narrow for wall oven: \(cabinetWidthInches)in")
    continue
}
guard cabinetDepthInches >= 22 else {  // Range hoods are shallower
    print("[ScanAnalysis] Object too shallow - likely range hood: \(cabinetDepthInches)in")
    continue
}
```

### Step 6: Update Output Structure
```swift
measurements["cabinets"] = [
    "upper": upperCabinets,
    "lower": lowerCabinets,
    "wall_oven": wallOvenCabinets,
    "pantry": pantryCabinets,
    "cooktop_base": cooktopBaseCabinets,  // NEW
    "corner": cornerCabinets  // NEW (future)
]
measurements["excluded"] = [
    "range_hoods": rangeHoods.count  // NEW: track what we excluded
]
```

---

## Part 6: Verification Plan

### Test Cases

1. **Kitchen with range + range hood** (like your photo)
   - Expected: Range hood excluded, stove as appliance, lower cabinets detected
   - Should NOT create wall_oven_cabinet

2. **Kitchen with wall oven**
   - Expected: wall_oven_cabinet with correct dimensions
   - Oven should be .oven category (not .stove)

3. **Kitchen with cooktop + drawers below**
   - Expected: cooktop_base_cabinet detected
   - Stove appliance + storage drawers below

4. **Kitchen with freestanding range (no drawers)**
   - Expected: Just stove appliance, no cooktop_base_cabinet

### Logging Improvements
```swift
print("[Classification] Range hood detected and excluded: \(rangeHoods.count)")
print("[Classification] Wall oven cabinets: \(wallOvenCabinets.count)")
print("[Classification] Cooktop base cabinets: \(cooktopBaseCabinets.count)")
```

---

## Files to Modify

1. **`ScanningView.swift`** (lines 970-1530)
   - Add range hood detection phase
   - Fix stove vs oven logic
   - Add cooktop base cabinet detection
   - Add depth/width validation
   - Update output structure

2. **`submit-project/index.ts`** (Edge Function)
   - Handle new cabinet types in webhook
   - Update summary counts

3. **Dashboard display** (optional)
   - Show cooktop_base_cabinet in floor plan
   - Show excluded range hoods count

---

## Part 7: Market Leader Strategies

### How Magicplan Handles Detection
- Uses Apple RoomPlan API for object detection (same as us)
- **AI-powered corner detection** - detects corners even when obstructed
- **Wall Mode** - uses LiDAR to detect walls, windows, doors, outlets separately
- Partnership with 2020 Design for kitchen-specific layouts
- **Key insight:** They recommend "double-checking critical dimensions—like for cabinetry or built-ins"

### How Professional Cabinet Software Works
- **CabinetCRUNCHER** - Manual entry, supports: Base, Built-In, Free-Standing, Wall cabinets
- **RoomSketcher** - Users manually select and resize cabinets, appliances, fixtures
- **2020 Design** - AI suggests layouts based on room dimensions and appliance placement
- **Custom Cabinet Estimator** - Estimates take 20-30 minutes per $10,000 of cabinetry

### Key Takeaway from Market Leaders
Most professional software does NOT rely on automatic detection for quotes:
- They use **manual placement** with AI suggestions
- They **double-check** LiDAR measurements
- They categorize cabinets by **user selection**, not auto-detection

**Our Advantage:** We can use post-processing heuristics to auto-classify, but must be conservative and flag uncertain classifications.

---

## Part 8: Complete Cabinet Type Taxonomy

### Base Cabinet Types (Lower - Floor Level)
| Type | Code | Width | Depth | Height | Key Identifier |
|------|------|-------|-------|--------|----------------|
| Standard Base | B## | 9"-48" | 24" | 34.5" | Default floor cabinet |
| Sink Base | SB## | 30"-42" | 24" | 34.5" | False drawer front, open back for plumbing, adjacent to sink |
| Cooktop Base | CB## | 30"-36" | 24" | 34.5" | Drawers below, cooktop/stove above (no oven below) |
| Corner Lazy Susan | LS## | 33"-36" | 33"-36" | 34.5" | In corner, square footprint |
| Blind Corner | BC## | 36"-42" | 24" | 34.5" | In corner, rectangular, one side against wall |
| Dishwasher Adjacent | DA## | 24" | 24" | 34.5" | Next to dishwasher opening |
| Range Base | RB## | 30" | 24" | 34.5" | Under freestanding range (usually just filler) |

### Upper/Wall Cabinet Types
| Type | Code | Width | Depth | Height | Key Identifier |
|------|------|-------|-------|--------|----------------|
| Standard Upper | W## | 9"-36" | 12" | 30"-42" | Default wall cabinet |
| Upper Above Fridge | WF## | 30"-36" | 24" | 12"-18" | Deep (24"), short, above refrigerator |
| Upper Above Range | WR## | 30" | 12" | 12"-18" | Short, above stove (for microwave or small storage) |
| Upper Above Sink | WS## | varies | 12" | varies | Typically NOT present (workspace) |
| Glass Door Upper | WG## | varies | 12" | varies | Display cabinet |
| Blind Corner Upper | BCW## | 24"-36" | 12" | 30"-42" | In corner, one side against wall |

### Tall Cabinet Types
| Type | Code | Width | Depth | Height | Key Identifier |
|------|------|-------|-------|--------|----------------|
| Pantry | P## | 12"-30" | 12"-24" | 84"-96" | Narrow, full height, NO oven |
| Wall Oven Cabinet | WO## | 30"-33" | 24" | 84"-96" | Wide, full height, WITH built-in oven |
| Utility Cabinet | U## | 18"-36" | 24" | 84"-96" | Broom closet, storage |
| Refrigerator Enclosure | RE## | varies | 24" | 84"-96" | Surrounds refrigerator |

### Specialty Items (NOT Cabinets)
| Type | Notes |
|------|-------|
| Range Hood | Ventilation, NOT storage - EXCLUDE from cabinet count |
| Filler Strip | 3"-6" wide, fills gaps - NOT a cabinet |
| End Panel | Decorative cover for exposed cabinet side |
| Toe Kick | 4.5" board at floor level |
| Crown Molding | Decorative trim at top |

---

## Part 9: Edge Cases & Confusion Scenarios

### Edge Case 1: Freestanding Range vs Cooktop + Wall Oven
| Scenario | RoomPlan Detection | Correct Classification |
|----------|-------------------|------------------------|
| Freestanding Range | `.stove` at floor | Appliance only, NO wall_oven_cabinet |
| Cooktop + Separate Wall Oven | `.stove` + `.oven` at different heights | cooktop_base_cabinet + wall_oven_cabinet |
| Range with Hood | `.stove` floor + `.stove/.oven` elevated | Appliance + Range Hood (exclude) |

**Rule:** If `.stove` is at floor level AND there's no `.oven` below it → it's a freestanding range OR cooktop with cabinet drawers below

### Edge Case 2: Island vs Peninsula vs L-Shape
| Type | Accessibility | Wall Attachment | Detection Method |
|------|--------------|-----------------|------------------|
| Island | 4 sides open | None | Cabinets NOT touching any wall |
| Peninsula | 3 sides open | One end attached | Cabinets touching wall on ONE side |
| L-Shape | 2 sides open | Corner attached | Cabinets in corner configuration |

**Detection:** Check cabinet position relative to detected walls
- If cabinet center is > 36" from ALL walls → likely **Island**
- If cabinet touches wall on one axis only → likely **Peninsula**

### Edge Case 3: Sink Base vs Standard Base
| Feature | Sink Base | Standard Base |
|---------|-----------|---------------|
| Top drawer | False front (non-functional) | Real drawer |
| Interior | Open (for plumbing) | Shelf |
| Adjacent to | Sink detected | No sink |
| Back panel | Open/cutout | Solid |

**Detection:** If `lowerCabinet.position` is X/Z aligned with `sink.position` → **sink_base_cabinet**

### Edge Case 4: Range Hood vs Wall Oven (CRITICAL)
| Feature | Range Hood | Wall Oven Cabinet |
|---------|------------|-------------------|
| Category | Misdetected as `.oven` or `.stove` | `.oven` |
| Height from floor | 54"-60" (above counter) | 24"-84" (spans multiple heights) |
| Depth | 18"-24" (shallow) | 24"+ (full depth) |
| Has cabinet below | NO (just stove) | YES (storage section) |
| Has cabinet above | Maybe small one | YES (upper section) |
| Width | Matches cooktop (30"-48") | 30"-33" standard |

**Detection Rule:**
```
IF elevated object above stove:
    IF depth < 22" → Range Hood (exclude)
    IF depth >= 22" AND has_cabinet_below AND has_cabinet_above → Wall Oven Cabinet
```

### Edge Case 5: Upper Above Fridge vs Standard Upper
| Feature | Above Fridge | Standard Upper |
|---------|--------------|----------------|
| Depth | 24" (deep) | 12" (shallow) |
| Height | 12"-18" (short) | 30"-42" (tall) |
| Position | Above refrigerator | Above counter |

**Detection:** If `upperCabinet.depth >= 20"` AND `upperCabinet.height <= 20"` AND aligned with `refrigerator` → **fridge_upper_cabinet**

### Edge Case 6: Pantry vs Wall Oven Cabinet
| Feature | Pantry | Wall Oven Cabinet |
|---------|--------|-------------------|
| Width | 12"-30" (narrow) | 30"-33" (wide) |
| Contains oven | NO | YES |
| Interior | Shelves | Oven cutout + shelves |

**Detection:** If `tallCabinet.width < 28"` AND no `.oven` aligned → **pantry**

### Edge Case 7: Cooktop Base Cabinet (User's Finding)
**User Rule:** "If there is no oven under stove, it means it is cabinet"

| Scenario | Detection |
|----------|-----------|
| `.stove` at floor level + `.oven` NOT below | → **cooktop_base_cabinet** (has drawers) |
| `.stove` at floor level + `.oven` below | → Freestanding range (no separate cabinet) |
| `.stove` at floor level + no oven detected at all | → **cooktop_base_cabinet** (assume drawers exist) |

---

## Part 10: Revised Detection Algorithm

```
PHASE 0: CATEGORIZE ALL OBJECTS
├── Separate floor-level appliances from elevated objects
├── Track: floorStoves[], elevatedObjects[], wallOvens[]
└── Track: refrigerators[], sinks[], dishwashers[]

PHASE 1: RANGE HOOD EXCLUSION
├── FOR each elevatedObject above a floorStove:
│   ├── IF depth < 22" → Range Hood (EXCLUDE)
│   ├── IF height from floor > 50" AND depth < 24" → Range Hood (EXCLUDE)
│   └── Track excluded positions
└── Result: excludedRangeHoods[]

PHASE 2: WALL OVEN CABINET DETECTION
├── FOR each .oven (NOT .stove!) at elevated position:
│   ├── REQUIRE: Cabinet ABOVE oven (aligned X/Z)
│   ├── REQUIRE: Width >= 28"
│   ├── REQUIRE: Depth >= 22"
│   ├── OPTIONAL: Cabinet BELOW oven
│   └── → wall_oven_cabinet
└── Mark matched cabinets

PHASE 3: COOKTOP BASE CABINET DETECTION (NEW)
├── FOR each .stove at floor level:
│   ├── Check if .oven exists directly below (same X/Z, lower Y)
│   ├── IF no oven below:
│   │   ├── Look for storage aligned with stove
│   │   ├── IF storage found → cooktop_base_cabinet (detected)
│   │   └── IF no storage found → cooktop_base_cabinet (inferred)
│   └── IF oven below → Freestanding range (no cabinet)
└── Mark matched cabinets

PHASE 4: SINK BASE CABINET DETECTION (NEW)
├── FOR each sink detected:
│   ├── Find lower cabinet aligned with sink (X/Z)
│   └── → sink_base_cabinet
└── Mark matched cabinets

PHASE 5: FRIDGE UPPER CABINET DETECTION (NEW)
├── FOR each refrigerator detected:
│   ├── Find upper cabinet aligned with fridge (X/Z)
│   ├── REQUIRE: depth >= 20" AND height <= 20"
│   └── → fridge_upper_cabinet
└── Mark matched cabinets

PHASE 6: PANTRY CABINET DETECTION
├── FOR each upper+lower pair (vertically aligned):
│   ├── REQUIRE: Gap < 6"
│   ├── REQUIRE: Total height >= 80"
│   ├── REQUIRE: Width <= 30"
│   ├── REQUIRE: No oven between
│   └── → pantry_cabinet
└── Mark matched cabinets

PHASE 7: ISLAND DETECTION (NEW)
├── FOR remaining lower cabinets:
│   ├── Check distance to all walls
│   ├── IF min_distance_to_wall > 36" → island_cabinet
│   └── Group adjacent island cabinets
└── Mark matched cabinets

PHASE 8: REMAINING UPPER CABINETS
├── FOR each unmatched upper storage:
│   └── → upper_cabinet
└── Done

PHASE 9: REMAINING LOWER CABINETS
├── FOR each unmatched lower storage:
│   ├── Check if in corner (near wall intersection)
│   ├── IF corner AND width > 33" → corner_cabinet
│   └── ELSE → lower_cabinet (base_cabinet)
└── Done
```

---

## Part 11: Output Schema Update

```json
{
  "cabinets": {
    "upper": [...],
    "lower": [...],
    "wall_oven": [...],
    "pantry": [...],
    "cooktop_base": [...],
    "sink_base": [...],
    "fridge_upper": [...],
    "corner": [...],
    "island": [...]
  },
  "appliances": {
    "stoves": [...],
    "ovens": [...],
    "refrigerators": [...],
    "dishwashers": [...]
  },
  "sinks": [...],
  "excluded": {
    "range_hoods": [...],
    "reason": "Not storage - ventilation equipment"
  },
  "summary": {
    "upper_cabinet_count": 5,
    "lower_cabinet_count": 8,
    "wall_oven_cabinet_count": 0,
    "pantry_cabinet_count": 1,
    "cooktop_base_cabinet_count": 1,
    "sink_base_cabinet_count": 1,
    "fridge_upper_cabinet_count": 1,
    "corner_cabinet_count": 2,
    "island_cabinet_count": 4,
    "range_hood_excluded_count": 1,
    "total_cabinet_count": 23
  },
  "confidence": {
    "high": ["upper", "lower", "sink_base"],
    "medium": ["wall_oven", "pantry", "cooktop_base"],
    "inferred": ["cooktop_base (no storage detected)"]
  }
}
```

---

## Part 12: Files to Modify

### Primary Changes
1. **`ScanningView.swift`** (lines 970-1530)
   - Restructure detection phases as outlined
   - Add depth validation throughout
   - Add new cabinet type detection
   - Remove stove → wall oven misclassification
   - Add confidence tracking

### Secondary Changes
2. **`submit-project/index.ts`** (Edge Function)
   - Handle all new cabinet types in webhook payload
   - Update summary counts
   - Add confidence field

3. **Dashboard (optional)**
   - Display new cabinet types in floor plan
   - Show excluded items with explanation
   - Display confidence indicators

---

## Sources

- [Standard Kitchen Cabinet Dimensions](https://cabinetselect.com/standard-kitchen-cabinet-sizes/)
- [Kitchen Cabinet Sizes Guide](https://kitchencabinetkings.com/guides/kitchen-cabinet-sizes)
- [Range Hood Installation Heights](https://www.kitchenaid.com/pinch-of-help/major-appliances/range-hood-height-above-stove.html)
- [Cooktop Base Cabinet Options](https://www.deancabinetry.com/custom-kitchen-cabinets/cooktop-base-cabinet/)
- [Apple RoomPlan Documentation](https://developer.apple.com/documentation/roomplan/)
- [RoomPlan Object Categories](https://developer.apple.com/documentation/roomplan/capturedroom/object/category-swift.enum/)
- [Magicplan LiDAR Scanning](https://help.magicplan.app/auto-scan-your-floor-plan)
- [Cabinet Abbreviation Codes](https://www.rtacabinetstore.com/blog/cracking-kitchen-cabinet-code/)
- [Kitchen Island vs Peninsula](https://www.deslaurier.com/en-ca/learning-centre/kitchen-island-vs.-peninsula-whats-right-for-your-kitchen/)
- [Sink Base Cabinet Specifics](https://cabinetselect.com/standard-kitchen-cabinet-sizes/)
- [Filler and End Panels](https://flatpackkitchens.co.uk/page/help/kitchen-cabinets/what-is-the-difference-between-filler-panels-and-end-panels)
- [Apple RoomPlan ML Research](https://machinelearning.apple.com/research/roomplan)
