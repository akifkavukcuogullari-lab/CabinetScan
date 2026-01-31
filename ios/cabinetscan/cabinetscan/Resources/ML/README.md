# Core ML Models for AI Flow

This directory contains the Core ML models required for depth estimation and object detection.

## Required Models

### 1. Depth Anything V2 Small (REQUIRED)
- **File:** `DepthAnythingV2SmallF16.mlpackage`
- **Size:** ~50 MB
- **Source:** https://huggingface.co/apple/coreml-depth-anything-v2-small
- **License:** Apache 2.0
- **Purpose:** Primary depth estimation from RGB images

**Download Instructions:**
1. Visit https://huggingface.co/apple/coreml-depth-anything-v2-small
2. Download `DepthAnythingV2SmallF16.mlpackage`
3. Place in this directory
4. Add to Xcode project with target membership: cabinetscan

### 2. DeepLabV3 (REQUIRED)
- **File:** `DeepLabV3.mlmodel` or `DeepLabV3.mlpackage`
- **Size:** ~8 MB
- **Source:** https://developer.apple.com/machine-learning/models/
- **License:** Apache 2.0
- **Purpose:** Semantic segmentation for cabinet/appliance detection

**Download Instructions:**
1. Visit https://developer.apple.com/machine-learning/models/
2. Search for "DeepLabV3"
3. Download the model
4. Place in this directory
5. Add to Xcode project with target membership: cabinetscan

### 3. MobileSAM (OPTIONAL)
- **File:** `MobileSAM.mlpackage`
- **Size:** ~10 MB
- **Source:** https://github.com/ChaoningZhang/MobileSAM (convert to CoreML)
- **License:** Apache 2.0
- **Purpose:** Edge refinement for precise boundaries

**Note:** MobileSAM is optional and loaded on-demand only when edge refinement is triggered.

## Adding Models to Xcode

1. Drag the `.mlpackage` or `.mlmodel` file into the Resources/ML group in Xcode
2. Ensure "Copy items if needed" is checked
3. Ensure target membership includes `cabinetscan`
4. Build the project - Xcode will auto-generate Swift model classes

## Model Configuration

All models are configured to use:
- Compute Units: `.all` (Neural Engine + GPU + CPU fallback)
- Precision: Float16 for memory efficiency
- `allowLowPrecisionAccumulationOnGPU = true` for performance

## Verification

After adding models, verify by:
1. Building the project (Cmd+B)
2. Check no compilation errors
3. Run on device and check model loading logs
