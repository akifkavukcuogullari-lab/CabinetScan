# Cabinet Measurement Research: Achieving +/-2" Accuracy Without LiDAR

**Date:** 2026-02-02
**Goal:** Find the BEST approach to achieve +/-2 inch accuracy for automatic cabinet measurement on non-LiDAR iPhones

---

## Executive Summary

After comprehensive research on 15 different approaches, here are the findings:

### Top Recommendations

| Rank | Approach | Expected Accuracy | Viability | Recommendation |
|------|----------|-------------------|-----------|----------------|
| 1 | **Bluetooth Laser Distance Meter** | +/-0.5" | HIGH | Best accuracy, minimal user effort |
| 2 | **Reference Object + Standard Cabinet Fitting** | +/-1-2" | HIGH | Best pure-software solution |
| 3 | **Apple Depth Pro (Server-Side)** | +/-2-4" | MEDIUM | Best AI-only approach |
| 4 | **Multi-View Stereo (DUSt3R/MASt3R)** | +/-3-6" | MEDIUM | Promising but unproven for cabinets |

### Hard Truth

**No current monocular depth estimation technology can reliably achieve +/-2" accuracy for cabinet measurement without:**
1. A known reference object in the scene, OR
2. Hardware assistance (laser rangefinder), OR
3. Constraining to standard cabinet sizes

The fundamental problem is **scale ambiguity** - without knowing the absolute distance to any surface, all measurements are relative.

---

## Detailed Analysis of All 15 Approaches

---

### 1. iPhone TrueDepth Camera (Front-Facing)

**How it works:**
- iPhone X+ has structured light depth sensor on front
- Projects 30,000+ infrared dots
- Triangulates to create depth map
- Used for Face ID

**Technical specifications:**
- Range: 14cm to 100cm (0.5 to 3.3 feet) only
- Accuracy: Sub-millimeter at close range (0.387mm average discrepancy in studies)
- Resolution: 640x480 depth points

**Realistic accuracy for cabinets:** NOT APPLICABLE

**Can it run on iPhone?** Yes, but only front camera

**Development complexity:** Low

**User experience:** Would require holding phone backwards, extremely awkward

**VERDICT: NOT VIABLE**
- Range is far too limited (max 3.3 feet)
- Only works on front camera
- Designed for face-distance scanning, not room scanning

**Sources:**
- [ResearchGate - TrueDepth Measurement Accuracy](https://www.researchgate.net/publication/335876093)
- [Laan Labs TrueDepth Case Study](https://labs.laan.com/casestudies/truedepth-3d-scanning-case-study/)

---

### 2. Apple Depth Pro Model (October 2024)

**How it works:**
- Foundation model for monocular metric depth estimation
- Uses multi-scale vision transformer
- Trained on real + synthetic datasets
- Claims absolute scale without camera intrinsics

**Technical specifications:**
- Output: 2.25 megapixel depth map
- Speed: 0.3 seconds on GPU (M-series Mac)
- Accuracy: Best-in-class for zero-shot metric depth (outperforms Depth Anything V2, Metric3D)

**Realistic accuracy for cabinets:**
- Paper claims "metric" but actual error rates not published for indoor cabinet scenarios
- Likely 5-15% relative error based on similar models
- For a 36" cabinet: +/-2" to +/-5" error range
- **Cannot guarantee +/-2" for all scenarios**

**Can it run on iPhone?**
- Not officially
- Community CoreML conversions in progress (1024x1024 float16)
- Depth Anything V2 CoreML runs at 31ms on iPhone 12 Pro Max
- Depth Pro is larger, would need optimization

**Development complexity:** HIGH
- Model conversion required
- ~100-200MB model size
- May need server-side for full quality

**User experience:** Seamless (just point and scan)

**VERDICT: PROMISING BUT INSUFFICIENT ALONE**
- Best monocular depth model available
- Still cannot guarantee +/-2" without reference calibration
- Could be combined with reference objects for better results

**Sources:**
- [Apple ML Research - Depth Pro](https://machinelearning.apple.com/research/depth-pro)
- [GitHub - apple/ml-depth-pro](https://github.com/apple/ml-depth-pro)
- [arXiv Paper](https://arxiv.org/abs/2410.02073)

---

### 3. Video Depth Estimation (DepthCrafter, ChronoDepth)

**How it works:**
- Uses temporal consistency across video frames
- Diffusion model generates coherent depth sequences
- Can process 110+ frames at once
- Eliminates flickering between frames

**Technical specifications:**
- DepthCrafter: CVPR 2025 Highlight paper
- Processes variable-length videos
- State-of-the-art temporal consistency

**Realistic accuracy for cabinets:**
- Improves **temporal consistency**, not absolute accuracy
- Still relative depth (scale ambiguity remains)
- Would prevent depth flickering but not solve measurement problem

**Can it run on iPhone?** NO
- Diffusion models require significant GPU memory
- Server-side only (needs 24GB+ VRAM)

**Development complexity:** VERY HIGH
- Server infrastructure required
- Video upload pipeline
- Long processing times

**User experience:** Poor (upload wait time)

**VERDICT: NOT RECOMMENDED**
- Solves wrong problem (consistency, not accuracy)
- Heavy server requirements
- Does not address scale ambiguity

**Sources:**
- [DepthCrafter GitHub](https://github.com/Tencent/DepthCrafter)
- [arXiv Paper](https://arxiv.org/abs/2409.02095)

---

### 4. Foundation Models (GPT-4V, Gemini, Claude)

**How it works:**
- Vision-language models can see and reason about images
- Could potentially estimate dimensions based on learned priors
- Understand spatial relationships, perspective, context

**Technical specifications:**
- GPT-4V: 69.1% on MMMU multimodal benchmark
- Gemini 1.5 Pro: 58.5% on MMMU
- No specific dimension estimation benchmarks exist

**Realistic accuracy for cabinets:**
- **Unknown** - no published benchmarks for physical measurement
- Likely very inconsistent (hallucination risk)
- Might guess "standard" sizes but can't measure precisely
- Could potentially identify cabinet types and suggest standard dimensions

**Can it run on iPhone?** No (API only)

**Development complexity:** LOW (API integration)

**User experience:** Good (take photo, get estimate)

**VERDICT: SUPPLEMENTARY ONLY**
- Could classify cabinet types (base, wall, pantry)
- Could suggest standard dimensions based on cabinet type
- Cannot measure actual dimensions reliably
- Use as validation/suggestion layer, not primary measurement

**Sources:**
- [arXiv - Gemini vs GPT-4V Comparison](https://arxiv.org/abs/2312.15011)

---

### 5. Direct Measurement Prediction Networks

**How it works:**
- Train neural network to directly predict dimensions
- Skip depth estimation entirely
- Learn from labeled measurement data

**Technical specifications:**
- Requires large labeled dataset of cabinets with dimensions
- End-to-end learning approach
- Could use known cabinet datasets

**Realistic accuracy for cabinets:**
- Dependent entirely on training data quality
- Could potentially work well if trained on cabinet-specific data
- No existing kitchen cabinet measurement models found

**Can it run on iPhone?** Yes (if model is small enough)

**Development complexity:** VERY HIGH
- Need to collect/label training data
- Need thousands of cabinet images with measurements
- Significant ML engineering effort

**User experience:** Good (if it works)

**VERDICT: HIGH EFFORT, UNCERTAIN OUTCOME**
- Would require significant data collection
- No existing models to leverage
- Could be a differentiator if built successfully
- 6-12 month research project

---

### 6. Dense Multi-View Stereo (DUSt3R, MASt3R)

**How it works:**
- DUSt3R: Dense Unconstrained Stereo 3D Reconstruction
- Takes multiple images, predicts point clouds directly
- No camera calibration needed
- MASt3R adds matching for better precision

**Technical specifications:**
- DUSt3R: Chamfer distance 1.741mm on DTU (vs SOTA 0.295mm)
- MASt3R: Sub-pixel accuracy for correspondences
- Can handle 1000+ images
- Runs at 15 FPS with MASt3R-SLAM

**Realistic accuracy for cabinets:**
- 1.74mm Chamfer distance sounds good but is on ideal test data
- Real-world indoor accuracy unclear
- **Problem: Uniform cabinet surfaces lack texture for matching**
- Could work well on cabinet doors with patterns/handles

**Can it run on iPhone?** Partially
- MASt3R-SLAM runs at 15 FPS
- Would need optimization for mobile
- Server-side for full quality

**Development complexity:** HIGH
- Complex integration
- Need to handle texture-less surfaces
- May require guided capture

**User experience:** Medium (need multiple angles)

**VERDICT: PROMISING FOR VALIDATION**
- Good for verifying measurements from multiple angles
- Struggles with uniform surfaces
- Best combined with other methods
- Could provide +/-3-6" accuracy realistically

**Sources:**
- [DUSt3R arXiv](https://arxiv.org/abs/2312.14132)
- [MASt3R - Naver Labs](https://europe.naverlabs.com/blog/mast3r-matching-and-stereo-3d-reconstruction/)

---

### 7. Neural Radiance Fields / Gaussian Splatting

**How it works:**
- NeRF: Learn implicit 3D representation from images
- 3D Gaussian Splatting: Explicit 3D Gaussians for faster rendering
- Both can extract geometry from captured images

**Technical specifications:**
- 3DGS: Real-time rendering
- NeRF: Higher quality but slower
- 2D Gaussian Splatting (2DGS): Better geometric accuracy

**Realistic accuracy for cabinets:**
- **Problem: Optimized for visual quality, not geometric accuracy**
- Photogrammetry struggles with reflective/uniform surfaces
- Cabinet surfaces are often glossy, uniform color
- Edge extraction unreliable

**Can it run on iPhone?** No (training requires GPU, inference possible)

**Development complexity:** VERY HIGH

**User experience:** Poor (long capture, processing time)

**VERDICT: NOT RECOMMENDED FOR MEASUREMENT**
- Designed for rendering, not measurement
- Struggles with cabinet surface types
- Overkill for 2D floor plan generation

**Sources:**
- [PyImageSearch - 3DGS vs NeRF](https://pyimagesearch.com/2024/12/09/3d-gaussian-splatting-vs-nerf/)

---

### 8. Edge Detection + Vanishing Point Geometry

**How it works:**
- Detect edges in image (cabinet boundaries)
- Find vanishing points (perspective convergence)
- Calculate dimensions using perspective geometry
- Requires one known reference length

**Technical specifications:**
- Classic computer vision approach
- Can achieve 1-3% error with good vanishing points
- Works best in Manhattan-world scenes (orthogonal walls)

**Realistic accuracy for cabinets:**
- For a wall 12 feet wide: 1-3% = +/-1.4 to +/-4.3"
- **Depends heavily on image quality and edge detection**
- Kitchens usually have good vanishing points (cabinets are rectangular)
- Need clean cabinet edges (problematic with shadows, handles)

**Can it run on iPhone?** Yes

**Development complexity:** MEDIUM

**User experience:** May need specific camera positioning

**VERDICT: VIABLE WITH CONSTRAINTS**
- Could achieve +/-2" in ideal conditions
- Need reference object for scale
- Combine with edge detection ML models
- Best for wall-to-wall measurements, harder for individual cabinets

**Sources:**
- [ScienceDirect - Vanishing Point Height Measurement](https://www.sciencedirect.com/science/article/abs/pii/S1077314215000855)

---

### 9. Reference Objects We Haven't Considered

**Standard reference objects in kitchens:**

| Object | Dimensions | Reliability | Visibility |
|--------|------------|-------------|------------|
| Electrical outlet (US duplex) | 4.5" x 2.75" | Very High | Often visible |
| Light switch | 4.5" x 2.75" | Very High | Often visible |
| Credit card | 3.37" x 2.125" | Perfect | User provides |
| US Letter paper | 8.5" x 11" | Perfect | User provides |
| iPhone (user's device) | Model-specific | Perfect | Always available |
| Standard door width | 32-36" | High | Sometimes visible |
| Countertop height | 36" | High | Usually visible |
| Backsplash tile (common) | 3x6", 4x4" | Medium | Often visible |

**Best reference object: Electrical Outlet**
- Present in every kitchen
- Standardized dimensions (NEMA WD 6)
- Usually multiple visible
- Not obscured by cabinets

**Implementation approach:**
1. Detect electrical outlets using YOLO/object detection
2. Use known outlet dimensions (4.5" x 2.75") for scale
3. Calculate pixels-per-inch ratio
4. Apply to cabinet measurements

**Realistic accuracy:**
- If outlet detected correctly: +/-1-2" possible
- Depends on outlet visibility and detection accuracy
- Multiple outlets provide validation

**Can it run on iPhone?** Yes

**Development complexity:** MEDIUM

**User experience:** Good (automatic detection), or guided ("include outlet in photo")

**VERDICT: HIGHLY RECOMMENDED**
- Low friction (outlets exist in all kitchens)
- Known standardized dimensions
- Can validate with multiple outlets
- Key component of hybrid solution

**Sources:**
- [Archtoolbox - Electrical Faceplate Dimensions](https://www.archtoolbox.com/electrical-faceplate-types-and-dimensions/)

---

### 10. Learning from LiDAR Data (Transfer Learning)

**How it works:**
- Train depth model on LiDAR ground truth
- Model learns to predict metric depth
- Deploy on non-LiDAR devices

**Technical specifications:**
- LiDARTouch: Uses sparse LiDAR (4 beams) + camera
- Depth Anything + LiDAR rescaling achieves similar to fine-tuned models
- Transfer learning from LiDAR-rich datasets (KITTI, NYU-D)

**Realistic accuracy for cabinets:**
- Fine-tuned on NYU-D (indoor): AbsRel ~0.05 (5% relative error)
- For 36" cabinet: +/-1.8" theoretically
- **But:** NYU-D has different scenes than kitchens
- Would need kitchen-specific fine-tuning

**Can it run on iPhone?** Yes (Depth Anything V2 runs on iPhone)

**Development complexity:** MEDIUM-HIGH
- Need to fine-tune existing models
- Need kitchen-specific training data
- Model conversion to CoreML

**User experience:** Good (seamless)

**VERDICT: VIABLE PATH**
- Build on Depth Anything V2 (already have CoreML)
- Fine-tune on kitchen/cabinet data
- Combine with reference object calibration
- Could achieve +/-2-3" with proper training

**Sources:**
- [LiDARTouch Paper](https://www.sciencedirect.com/science/article/abs/pii/S1077314222001795)

---

### 11. Professional/Commercial Solutions

**Matterport:**
- Uses infrared depth sensors (structured light)
- ~1% accuracy on measurements
- Requires Matterport Pro camera ($3,000+) OR Pro3 ($6,000+)
- iPhone app available but lower accuracy

**Canvas by Occipital:**
- Uses LiDAR (iPad Pro/iPhone Pro required)
- 1-2% accuracy (99% accurate marketing claim)
- iOS-only
- **Cannot work without LiDAR**

**iGUIDE:**
- Uses proprietary PLANIX camera with lidar
- 0.5% measurement uncertainty
- ~1cm uncertainty at 130 feet
- Requires $3,000+ hardware

**Key insight:** ALL professional solutions require specialized hardware (LiDAR, structured light, or proprietary sensors). None achieve high accuracy with monocular camera alone.

**VERDICT: CONFIRMS HARDWARE IS NEEDED FOR PRO ACCURACY**
- All commercial solutions use depth sensors
- No pure-software solution exists commercially
- Canvas requires LiDAR, not viable for non-LiDAR phones

**Sources:**
- [Canvas Accuracy FAQ](https://support.canvas.io/article/5-what-kind-of-accuracy-can-i-expect-from-canvas)
- [iGUIDE vs Matterport](https://goiguide.com/matterport-alternative)

---

### 12. Hardware Additions (Bluetooth Laser Distance Meter)

**How it works:**
- User points Bluetooth-enabled laser at cabinet surface
- Laser measures distance precisely
- App reads measurement via Bluetooth
- User marks point on screen

**Available hardware:**
| Device | Price | Range | Accuracy | Bluetooth |
|--------|-------|-------|----------|-----------|
| Bosch GLM50 | $100 | 165 ft | +/-1/16" | Yes |
| Leica DISTO D2 | $200 | 330 ft | +/-1/16" | Yes |
| Leica DISTO X3 | $400 | 500 ft | +/-1/16" | Yes |

**Available SDKs:**
- **Leica DISTO API** - Available through Geosystems Developer Network
- **Spike Partner Program** (ikeGPS) - APIs, SDKs, XML integration
- **Bosch MeasureOn** - App with Bluetooth integration

**App integrations exist:**
- magicplan PrecisionLink
- Floor Plan Creator (Web Bluetooth)
- Live Home 3D (Bosch integration)

**Realistic accuracy:** +/-1/16" to +/-1/4" (EXCELLENT)

**Can it run on iPhone?** Yes (Bluetooth LE)

**Development complexity:** MEDIUM
- Need to integrate Leica/Bosch SDK
- Handle pairing, measurement reading
- UI for point marking

**User experience:**
- Requires hardware purchase ($100-200)
- User points laser at each measurement point
- More effort than pure scan, but guided

**VERDICT: BEST ACCURACY OPTION**
- Achieves better than +/-2" easily
- Established SDKs and integrations
- Reasonable hardware cost
- Could be "pro" tier feature

**Implementation concept:**
```
User Flow:
1. Open app, pair Bluetooth laser
2. See camera preview on screen
3. Point laser at cabinet corner, press measure
4. Tap screen where laser dot is
5. Repeat for other corners
6. App calculates dimensions from laser distances + geometry
```

**Sources:**
- [Leica DISTO Apps](https://shop.leica-geosystems.com/learn/leica-disto/leica-disto-apps)
- [Spike Partner Program](https://spike.ikegps.com/)
- [magicplan PrecisionLink](https://help.magicplan.app/laser-distance-meters)

---

### 13. Crowdsourced Calibration

**How it works:**
- Collect scanning data from many users
- Include ground truth measurements (user verification)
- Train models on aggregated data
- Improve accuracy over time

**Technical specifications:**
- Would need thousands of verified kitchen scans
- Build proprietary kitchen depth/measurement dataset
- Continuous improvement loop

**Realistic accuracy:**
- Long-term potential for improvement
- Initial accuracy would match current methods
- Could eventually achieve +/-2" with enough data

**Can it run on iPhone?** Yes (data collection)

**Development complexity:** HIGH
- Backend infrastructure for data collection
- Verification/quality control pipeline
- Model retraining pipeline

**User experience:**
- Users would need to verify measurements
- Creates friction

**VERDICT: LONG-TERM STRATEGY**
- Not immediate solution
- Good as background data collection
- Could differentiate over time
- Start collecting data now, benefit later

---

### 14. Cabinet Industry Standards

**Standard cabinet dimensions (US):**

**Base Cabinets:**
- Heights: 34.5" (universal)
- Depths: 24" (universal)
- Widths: 9", 12", 15", 18", 21", 24", 27", 30", 33", 36", 48" (3" increments)

**Wall Cabinets:**
- Heights: 12", 15", 18", 24", 30", 36", 42"
- Depths: 12", 15"
- Widths: Same as base (9"-48" in 3" increments)

**Tall/Pantry Cabinets:**
- Heights: 84", 90", 96"
- Depths: 12", 24"
- Widths: 12", 24", 36"

**Corner Cabinets:**
- Lazy Susan: 33"-36" width
- Blind corner: 36" width

**Key insight:** 90%+ of cabinets fit standard sizes. Non-standard cabinets are expensive custom work.

**Implementation approach:**
1. Detect cabinet type (base/wall/tall)
2. Detect cabinet features (doors, drawers, handles)
3. Estimate rough width from image
4. Snap to nearest standard size
5. Flag potential non-standard for manual review

**Realistic accuracy:**
- Standard cabinets: Exact (if type detected correctly)
- Non-standard cabinets: Flagged for review
- Risk: Wrong standard size selected (+/-3" error between sizes)

**Can it run on iPhone?** Yes

**Development complexity:** MEDIUM

**User experience:** Good (automatic), with confirmation step

**VERDICT: CRITICAL COMPONENT**
- Must be part of any solution
- Dramatically reduces error for most cabinets
- Provides validation layer
- Users can confirm/adjust suggested sizes

**Sources:**
- [Kitchen Cabinet Kings Size Guide](https://kitchencabinetkings.com/guides/kitchen-cabinet-sizes)
- [CabinetCorp Standard Sizes](https://www.cabinetcorp.com/2021/06/21/kitchen-cabinet-guide-for-standard-sizes-and-dimensions/)

---

### 15. Hybrid AI + Post-Processing

**Recommended hybrid approach combining multiple methods:**

```
Pipeline:
                                    ┌─────────────────┐
                                    │  Reference      │
                                    │  Object         │
                                    │  Detection      │
                                    │  (outlet/card)  │
                                    └────────┬────────┘
                                             │
┌──────────────┐    ┌──────────────┐    ┌───▼───────────┐
│   Video/     │───▶│   Depth Pro  │───▶│    Scale      │
│   Photos     │    │   or Depth   │    │   Calibration │
│   Capture    │    │   Anything   │    │               │
└──────────────┘    └──────────────┘    └───────┬───────┘
                                                │
                    ┌──────────────┐    ┌───────▼───────┐
                    │   Cabinet    │◀───│   Calibrated  │
                    │   Type       │    │   Depth Map   │
                    │   Detection  │    │               │
                    │   (YOLO)     │    └───────────────┘
                    └──────┬───────┘
                           │
                    ┌──────▼───────┐
                    │   Standard   │
                    │   Size       │
                    │   Fitting    │
                    └──────┬───────┘
                           │
                    ┌──────▼───────┐    ┌──────────────┐
                    │   Vanishing  │    │   Multi-     │
                    │   Point      │◀───│   View       │
                    │   Validation │    │   Validation │
                    └──────┬───────┘    └──────────────┘
                           │
                    ┌──────▼───────┐
                    │   User       │
                    │   Confirmation│
                    │   UI         │
                    └──────┬───────┘
                           │
                    ┌──────▼───────┐
                    │   Final      │
                    │   Output     │
                    └──────────────┘
```

**Components:**

1. **Reference Object Detection** - Detect outlet or user-provided reference
2. **Depth Estimation** - Depth Pro or Depth Anything V2 with scale calibration
3. **Cabinet Detection** - YOLO for bounding boxes
4. **Standard Size Fitting** - Snap to standard cabinet sizes
5. **Geometry Validation** - Vanishing points, perspective checks
6. **User Confirmation** - Allow manual adjustment

**Expected accuracy:**
- With reference object + standard fitting: +/-1-2" for standard cabinets
- Non-standard cabinets: Flagged, may have +/-3-4" error

**Can it run on iPhone?** Mostly (depth estimation might need server)

**Development complexity:** HIGH (but achievable)

**User experience:** Good with guidance

**VERDICT: RECOMMENDED APPROACH**

---

## Final Recommendations

### Tier 1: Achievable +/-2" Accuracy

**Option A: Bluetooth Laser Integration (Recommended for Pro Users)**
- Cost: User buys $100-200 laser
- Accuracy: +/-1/16" to +/-1/4"
- Development: 4-6 weeks
- Best for: Contractors, designers who need precision

**Option B: Reference Object + Standard Fitting (Recommended for General Users)**
- Cost: Free (use existing outlets)
- Accuracy: +/-1-2" for standard cabinets
- Development: 8-12 weeks
- Best for: Homeowners, casual users

### Tier 2: Best-Effort +/-3-4" Accuracy

**Option C: Depth Pro + Standard Fitting**
- Cost: Server compute costs
- Accuracy: +/-3-4" realistically
- Development: 6-8 weeks
- Best for: Quick estimates, lead generation

### Not Recommended

- Pure monocular depth without reference: Cannot achieve +/-2"
- NeRF/3DGS: Overkill, wrong problem
- DepthCrafter/video depth: Solves wrong problem
- TrueDepth: Range too limited

---

## Implementation Roadmap

### Phase 1: Foundation (Weeks 1-4)
1. Implement reference object detection (electrical outlets)
2. Add scale calibration using reference objects
3. Integrate standard cabinet size database
4. Add "snap to standard" logic

### Phase 2: Enhancement (Weeks 5-8)
1. Upgrade to Depth Pro (server-side) or fine-tune Depth Anything
2. Add vanishing point geometry validation
3. Implement multi-image validation
4. Add user confirmation/adjustment UI

### Phase 3: Pro Features (Weeks 9-12)
1. Bluetooth laser integration (Leica SDK)
2. Pro user tier with laser-assisted measurements
3. Crowdsourced data collection for future improvements

---

## Appendix: Accuracy Comparison Table

| Method | Best Case | Typical Case | Worst Case | Requirements |
|--------|-----------|--------------|------------|--------------|
| LiDAR (iPhone Pro) | +/-0.5" | +/-1" | +/-2" | LiDAR device |
| Bluetooth Laser | +/-0.1" | +/-0.25" | +/-0.5" | $100+ hardware |
| Reference + Standard | +/-1" | +/-2" | +/-4" | Visible outlet |
| Depth Pro + Reference | +/-2" | +/-3" | +/-6" | Server + reference |
| Pure Depth Estimation | +/-3" | +/-6" | +/-12" | Nothing |
| Manual Entry | +/-0.5" | +/-1" | +/-2" | User tape measure |

---

## Key Takeaways

1. **No magic solution exists** - Every commercial solution uses specialized hardware
2. **Reference objects are essential** - Scale ambiguity cannot be solved without known references
3. **Standard sizes are a cheat code** - 90% of cabinets fit standards, use this
4. **Bluetooth laser is the accuracy king** - Best ROI for users who need precision
5. **Hybrid approaches win** - Combine multiple signals for best results
6. **User confirmation is necessary** - Always let users verify/adjust measurements

---

## References

- [Apple Depth Pro](https://machinelearning.apple.com/research/depth-pro)
- [Depth Anything V2](https://huggingface.co/blog/Isayoften/monocular-depth-estimation-guide)
- [DUSt3R Paper](https://arxiv.org/abs/2312.14132)
- [Canvas Accuracy](https://support.canvas.io/article/5-what-kind-of-accuracy-can-i-expect-from-canvas)
- [iGUIDE Technology](https://goiguide.com/matterport-alternative)
- [Leica DISTO SDK](https://shop.leica-geosystems.com/learn/leica-disto/leica-disto-apps)
- [Standard Cabinet Sizes](https://kitchencabinetkings.com/guides/kitchen-cabinet-sizes)
- [Electrical Outlet Dimensions](https://www.archtoolbox.com/electrical-faceplate-types-and-dimensions/)
- [DepthCrafter](https://github.com/Tencent/DepthCrafter)
- [MASt3R](https://europe.naverlabs.com/blog/mast3r-matching-and-stereo-3d-reconstruction/)
