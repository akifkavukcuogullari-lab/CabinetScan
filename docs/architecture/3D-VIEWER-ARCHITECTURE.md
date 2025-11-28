# NextLean Scan - Premium 3D Visualization Architecture

**Version:** 1.0
**Date:** 2025-11-28
**Author:** Architect Agent

---

## Executive Summary

This document outlines the architecture for a world-class 3D visualization experience in the NextLean Scan dashboard. The goal is to create an impressive, "WOW-factor" 3D viewer that makes showroom owners proud to demonstrate customer room scans to their clients.

---

## Table of Contents

1. [Technology Stack Recommendation](#1-technology-stack-recommendation)
2. [Competitor Analysis](#2-competitor-analysis)
3. [Architecture Overview](#3-architecture-overview)
4. [File Format Strategy](#4-file-format-strategy)
5. [Component Architecture](#5-component-architecture)
6. [Feature Priority Matrix](#6-feature-priority-matrix)
7. [Implementation Phases](#7-implementation-phases)
8. [Performance Benchmarks](#8-performance-benchmarks)
9. [Inspiration Gallery](#9-inspiration-gallery)

---

## 1. Technology Stack Recommendation

### Primary Recommendation: React Three Fiber + Drei

After extensive research comparing available 3D web technologies, **React Three Fiber (R3F) with Drei helpers** is the recommended stack for NextLean Scan.

#### Why React Three Fiber?

| Factor | React Three Fiber | Google Model Viewer | Babylon.js |
|--------|------------------|---------------------|------------|
| **React Integration** | Native - built for React | Web Component - awkward in React | Requires wrapper |
| **Flexibility** | Full Three.js power | Limited to viewer functionality | Full engine power |
| **Bundle Size** | ~150KB core + tree-shakeable | ~200KB fixed | ~400KB minimum |
| **Learning Curve** | Familiar React patterns | Lowest | Steeper |
| **Customization** | Unlimited | Very limited | Unlimited |
| **Performance** | Excellent (matches raw Three.js) | Good | Excellent |
| **Community** | Large, active (pmndrs ecosystem) | Google-maintained | Microsoft-maintained |
| **AR Support** | Via WebXR | Native (best AR support) | Via WebXR |

#### Decision Rationale

1. **React Native Integration**: NextLean dashboard is built with Next.js 15 + React 19. R3F provides the most seamless integration, using familiar React patterns like hooks, components, and JSX.

2. **Flexibility for Premium UX**: Model Viewer is simple but limited. We need custom lighting, post-processing effects, measurement overlays, and interactive annotations that Model Viewer cannot provide.

3. **Performance**: R3F performance matches or exceeds raw Three.js. It uses React's reconciler efficiently and supports InstancedMesh for complex scenes.

4. **Ecosystem**: The Drei library provides 100+ ready-made abstractions for common 3D needs (cameras, controls, helpers, shaders, etc.).

5. **Future-Proof**: R3F supports WebXR, WebGPU (upcoming), and integrates with the broader Three.js ecosystem.

#### Recommended Package Stack

```json
{
  "dependencies": {
    "@react-three/fiber": "^8.15.0",
    "@react-three/drei": "^9.92.0",
    "@react-three/postprocessing": "^2.15.0",
    "three": "^0.160.0",
    "three-stdlib": "^2.28.0",
    "leva": "^0.9.35",
    "maath": "^0.10.0"
  }
}
```

#### Hybrid Approach for AR

For AR Quick Look on iOS, we maintain the current approach of providing a download link to the USDZ file, which automatically triggers iOS AR Quick Look. For in-browser AR (Android/WebXR), we can integrate WebXR through R3F.

---

## 2. Competitor Analysis

### Matterport (Industry Leader)
- **Strength**: Dollhouse view, minimap, compass, seamless navigation
- **Strength**: Mattertags for annotations and embedded media
- **Strength**: 4K photo generation, schematic floor plans
- **Weakness**: Requires proprietary camera hardware
- **Weakness**: Expensive ($69-309/month for business plans)

**What to Adopt**: Dollhouse view toggle, minimap navigation, measurement annotations

### Canvas.io (Direct Competitor)
- **Strength**: LiDAR-based scanning (same as our approach)
- **Strength**: Professional CAD file output
- **Strength**: SDK for third-party integration
- **Weakness**: Basic 3D viewer in web interface
- **Weakness**: Pay-per-scan pricing model

**Opportunity**: Canvas has a mediocre web viewer. Our premium visualization can be a key differentiator.

### iGUIDE
- **Strength**: Floor plan + 3D tour integration
- **Strength**: Click-to-teleport navigation
- **Strength**: Measurement accuracy (0.5% or better)
- **Weakness**: Real estate focused, not cabinet/kitchen specific

**What to Adopt**: Floor plan overlay with click-to-navigate, measurement display

### Cupix
- **Strength**: 3D annotations (pushpins, 3D boxes, hotspots)
- **Strength**: Floor plan as navigation map
- **Strength**: BIM file support (IFC, RVT)
- **Weakness**: Construction-focused, complex interface

**What to Adopt**: 3D annotation system, floor plan as navigation overlay

### Competitive Positioning

NextLean Scan can differentiate by:
1. **Kitchen/Cabinet Specific**: Optimized for cabinet showroom use cases
2. **Instant Visualization**: No post-processing wait time (unlike Canvas)
3. **Beautiful Default Rendering**: Professional lighting and materials out of the box
4. **Integrated Product Selection**: View products overlaid in the 3D space
5. **Simpler UX**: Less cluttered than construction-focused tools

---

## 3. Architecture Overview

### System Architecture Diagram

```
+------------------------------------------------------------------+
|                      NextLean Scan Dashboard                       |
|------------------------------------------------------------------|
|                                                                    |
|  +--------------------+    +----------------------------------+    |
|  |   Project Detail   |    |      Premium 3D Viewer           |    |
|  |       Page         |--->|  (React Three Fiber + Drei)      |    |
|  +--------------------+    +----------------------------------+    |
|                                         |                          |
|                                         v                          |
|                            +------------------------+              |
|                            |    Scene Manager       |              |
|                            +------------------------+              |
|                                    |                               |
|        +---------------+----------+----------+---------------+     |
|        |               |                     |               |     |
|        v               v                     v               v     |
|  +-----------+  +------------+  +------------------+  +----------+ |
|  | Lighting  |  |  Camera    |  |  Model Loader   |  | Controls | |
|  |  System   |  |  System    |  |  (GLB/USDZ)     |  |  System  | |
|  +-----------+  +------------+  +------------------+  +----------+ |
|                                         |                          |
|                                         v                          |
|                            +------------------------+              |
|                            |   Render Pipeline      |              |
|                            |   (Post-Processing)    |              |
|                            +------------------------+              |
|                                         |                          |
|                                         v                          |
|                            +------------------------+              |
|                            |   Annotations Layer    |              |
|                            |   (Measurements, Tags) |              |
|                            +------------------------+              |
+------------------------------------------------------------------+
                                    |
                                    v
+------------------------------------------------------------------+
|                        Backend Services                           |
|------------------------------------------------------------------|
|                                                                    |
|  +------------------+    +-------------------+    +--------------+ |
|  | Supabase Storage |    | Edge Function:   |    | Supabase DB  | |
|  | (USDZ/GLB files) |    | USDZ to GLB      |    | (Metadata)   | |
|  +------------------+    | Converter        |    +--------------+ |
|                          +-------------------+                     |
+------------------------------------------------------------------+
```

### Data Flow Diagram

```
                    iOS App (RoomPlan Scan)
                              |
                              v
              +-------------------------------+
              |  1. USDZ file generated       |
              |  2. Preview image captured    |
              |  3. Measurements extracted    |
              +-------------------------------+
                              |
                              v
              +-------------------------------+
              |  Edge Function: submit-project |
              |  - Uploads USDZ to Storage     |
              |  - Triggers GLB conversion     |
              |  - Stores metadata in DB       |
              +-------------------------------+
                              |
            +-----------------+-----------------+
            |                                   |
            v                                   v
+---------------------+           +------------------------+
| Supabase Storage    |           | project_measurements   |
| /scans/{project_id}/|           | - usdz_file_url       |
| - room.usdz         |           | - glb_file_url        |
| - room.glb          |           | - preview_image_url   |
| - preview.jpg       |           | - measurements (JSON) |
+---------------------+           +------------------------+
            |                                   |
            +-----------------------------------+
                              |
                              v
              +-------------------------------+
              |  Dashboard: 3D Viewer         |
              |  - Loads GLB for web viewing  |
              |  - Falls back to USDZ for AR  |
              |  - Displays measurements      |
              +-------------------------------+
```

---

## 4. File Format Strategy

### The USDZ vs GLB Challenge

**Problem**: Apple's RoomPlan exports USDZ format, but web browsers work best with GLB (glTF Binary).

**Solution**: Dual-format storage with server-side conversion.

### Recommended Approach

```
+------------------+     +------------------+     +------------------+
|  iOS App         |     |  Edge Function   |     |  Storage         |
|  (RoomPlan)      |---->|  (Convert)       |---->|  (Both formats)  |
+------------------+     +------------------+     +------------------+
        |                        |                        |
        v                        v                        v
    USDZ file             USDZ -> GLB              room.usdz
    (original)            conversion               room.glb
                                                   preview.jpg
```

### Conversion Options

#### Option A: Server-Side Conversion (Recommended)

Use a Supabase Edge Function that calls an external conversion API:

1. **Sirv API** - Professional 3D conversion service
   - Cost: Pay-per-conversion
   - Reliability: High
   - Speed: Fast (seconds)

2. **Self-Hosted usd-from-gltf** - Open source USD tools
   - Cost: Server hosting only
   - Reliability: Depends on implementation
   - Speed: Variable

3. **Blender Cloud Render** - Headless Blender for conversion
   - Cost: Server hosting
   - Reliability: High
   - Speed: Slower (requires full Blender)

#### Option B: Client-Side Conversion

Use three-usdz-loader in the browser:
- Pro: No server costs
- Con: Larger bundle size
- Con: Slower initial load
- Con: Inconsistent results

### Recommended Implementation

```typescript
// Edge Function: convert-usdz-to-glb

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  const { projectId, usdzUrl } = await req.json()

  // Option 1: Call external conversion API
  const conversionResponse = await fetch('https://api.sirv.com/v2/files/convert', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${Deno.env.get('SIRV_API_KEY')}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      input: usdzUrl,
      output: { format: 'glb' }
    })
  })

  const { glbUrl } = await conversionResponse.json()

  // Store GLB URL in database
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  await supabase
    .from('project_measurements')
    .update({ glb_file_url: glbUrl })
    .eq('project_id', projectId)

  return new Response(JSON.stringify({ success: true, glbUrl }))
})
```

### Database Schema Update

```sql
-- Add GLB file URL to project_measurements
ALTER TABLE project_measurements
ADD COLUMN glb_file_url TEXT;

-- Add conversion status
ALTER TABLE project_measurements
ADD COLUMN conversion_status TEXT DEFAULT 'pending'
  CHECK (conversion_status IN ('pending', 'processing', 'completed', 'failed'));
```

---

## 5. Component Architecture

### Directory Structure

```
/dashboard/src/components/3d-viewer/
├── index.ts                      # Public exports
├── PremiumModelViewer.tsx        # Main container component
│
├── core/
│   ├── Scene.tsx                 # R3F Canvas and scene setup
│   ├── Camera.tsx                # Camera configuration
│   ├── Lighting.tsx              # Professional lighting setup
│   ├── Model.tsx                 # GLB/USDZ model loader
│   ├── Environment.tsx           # HDR environment maps
│   └── PostProcessing.tsx        # Visual effects pipeline
│
├── controls/
│   ├── OrbitControls.tsx         # Camera orbit with momentum
│   ├── ViewModeSelector.tsx      # Orbit/Walkthrough/Top toggle
│   ├── ZoomControls.tsx          # Zoom in/out buttons
│   └── FullscreenToggle.tsx      # Fullscreen mode
│
├── annotations/
│   ├── MeasurementLabel.tsx      # 3D dimension labels
│   ├── RoomDimensions.tsx        # Room boundary measurements
│   ├── ObjectHighlight.tsx       # Highlight detected objects
│   └── Hotspot.tsx               # Interactive info points
│
├── overlays/
│   ├── Toolbar.tsx               # Main control toolbar
│   ├── Minimap.tsx               # Floor plan minimap
│   ├── LoadingScreen.tsx         # Beautiful loading animation
│   ├── OnboardingHint.tsx        # First-time user tooltip
│   ├── KeyboardShortcuts.tsx     # Shortcut helper panel
│   └── StatsPanel.tsx            # Performance stats (dev mode)
│
├── effects/
│   ├── BloomEffect.tsx           # Subtle glow on highlights
│   ├── AmbientOcclusion.tsx      # SSAO for depth
│   ├── ColorGrading.tsx          # Color correction
│   └── Vignette.tsx              # Subtle edge darkening
│
├── hooks/
│   ├── useModelLoader.ts         # Load and cache 3D models
│   ├── useCamera.ts              # Camera state management
│   ├── useAnnotations.ts         # Measurement annotations
│   ├── useMeasurements.ts        # Parse RoomPlan measurements
│   ├── useViewMode.ts            # View mode state
│   ├── useKeyboardShortcuts.ts   # Keyboard event handling
│   └── usePerformance.ts         # FPS monitoring
│
├── utils/
│   ├── lighting-presets.ts       # Studio, showroom, natural presets
│   ├── camera-presets.ts         # Default camera positions
│   ├── measurement-parser.ts     # Parse RoomPlan JSON to 3D coords
│   └── screenshot.ts             # Capture current view
│
└── types/
    └── index.ts                  # TypeScript definitions
```

### Core Component Design

#### PremiumModelViewer.tsx (Main Container)

```tsx
// Type definitions for the main viewer component

interface PremiumModelViewerProps {
  // Model sources
  glbUrl: string | null
  usdzUrl: string | null
  previewImageUrl?: string

  // Measurement data from RoomPlan
  measurements: RoomPlanMeasurements | null

  // Display options
  showAnnotations?: boolean
  showMinimap?: boolean
  defaultViewMode?: 'orbit' | 'walkthrough' | 'top'

  // Theme
  theme?: 'light' | 'dark' | 'auto'

  // Callbacks
  onLoad?: () => void
  onError?: (error: Error) => void
  onScreenshot?: (dataUrl: string) => void
}

interface RoomPlanMeasurements {
  room: {
    min_x: number
    max_x: number
    min_z: number
    max_z: number
    ceiling_height_ft: number
  }
  walls: WallMeasurement[]
  doors: DoorMeasurement[]
  windows: WindowMeasurement[]
  cabinets: {
    upper: CabinetMeasurement[]
    lower: CabinetMeasurement[]
  }
  appliances: ApplianceMeasurement[]
  countertops: CountertopMeasurement[]
}
```

#### Lighting System

```typescript
// lighting-presets.ts

export const lightingPresets = {
  // Professional photography studio lighting
  studio: {
    ambient: { intensity: 0.3, color: '#ffffff' },
    key: {
      position: [5, 8, 5],
      intensity: 1.5,
      color: '#fff5eb',
      castShadow: true
    },
    fill: {
      position: [-5, 3, -5],
      intensity: 0.7,
      color: '#e6f0ff'
    },
    rim: {
      position: [0, 5, -10],
      intensity: 0.5,
      color: '#ffffff'
    }
  },

  // Warm showroom lighting
  showroom: {
    ambient: { intensity: 0.4, color: '#fff8f0' },
    spotlights: [
      { position: [0, 8, 0], intensity: 2, angle: Math.PI / 3 },
      { position: [5, 6, 5], intensity: 1.5, angle: Math.PI / 4 },
      { position: [-5, 6, 5], intensity: 1.5, angle: Math.PI / 4 }
    ],
    environment: 'studio'
  },

  // Natural daylight
  natural: {
    ambient: { intensity: 0.5, color: '#87CEEB' },
    sun: {
      position: [10, 15, 10],
      intensity: 2,
      color: '#FFF4E0',
      castShadow: true
    },
    environment: 'apartment'
  }
}
```

#### Loading Screen Design

```tsx
// LoadingScreen.tsx - Beautiful loading animation

interface LoadingScreenProps {
  progress: number // 0-100
  status: 'loading' | 'processing' | 'rendering'
}

// Visual design:
// - Elegant animated 3D cube or room wireframe
// - Smooth progress bar with gradient
// - Status text: "Loading 3D model...", "Preparing scene...", "Almost ready..."
// - Subtle particle effects in background
// - Brand-consistent colors from showroom branding
```

---

## 6. Feature Priority Matrix

### MVP (Phase 1) - Core Impressive Experience

| Feature | Priority | Effort | Impact |
|---------|----------|--------|--------|
| GLB model loading with R3F | P0 | Medium | Critical |
| Professional 3-point lighting | P0 | Low | High |
| Smooth orbit controls with momentum | P0 | Low | High |
| Beautiful loading animation | P0 | Medium | High |
| Zoom controls (buttons + scroll) | P0 | Low | Medium |
| Fullscreen mode | P0 | Low | Medium |
| Reset camera button | P0 | Low | Low |
| Basic shadows | P0 | Low | Medium |
| Auto-rotate on load | P0 | Low | Medium |
| Responsive canvas (mobile-friendly) | P0 | Medium | High |

### Phase 2 - Enhanced Visualization

| Feature | Priority | Effort | Impact |
|---------|----------|--------|--------|
| Minimap (floor plan overlay) | P1 | High | High |
| Measurement annotations in 3D | P1 | High | High |
| View mode toggle (orbit/top/walkthrough) | P1 | Medium | Medium |
| Post-processing (SSAO, bloom) | P1 | Medium | Medium |
| HDR environment maps | P1 | Low | Medium |
| Onboarding tooltip | P1 | Low | Medium |
| Keyboard shortcuts | P1 | Low | Low |
| Download screenshot button | P1 | Low | Medium |

### Phase 3 - Premium Features

| Feature | Priority | Effort | Impact |
|---------|----------|--------|--------|
| Object highlighting on hover | P2 | High | Medium |
| Click object for details | P2 | High | Medium |
| Exploded view mode | P2 | High | Wow factor |
| Light/dark theme toggle | P2 | Low | Low |
| Share 3D view (generate link) | P2 | High | Medium |
| Video recording of rotation | P2 | High | Medium |
| AR Quick Look button (iOS) | P2 | Medium | Medium |
| WebXR AR mode | P2 | High | Medium |
| Multiple lighting presets | P2 | Low | Low |

### Phase 4 - Advanced Features

| Feature | Priority | Effort | Impact |
|---------|----------|--------|--------|
| Product overlay in 3D | P3 | Very High | Wow factor |
| Before/after comparison | P3 | High | Medium |
| Measurement tool (click-to-measure) | P3 | Very High | High |
| Guided tour mode | P3 | High | Medium |
| VR mode (WebXR) | P3 | Very High | Wow factor |
| Collaborative viewing | P3 | Very High | Medium |

---

## 7. Implementation Phases

### Phase 1: Foundation (Week 1-2)

**Goal**: Replace current model-viewer with impressive R3F viewer

#### Tasks:
1. Set up React Three Fiber in Next.js dashboard
2. Create base Scene component with professional lighting
3. Implement GLB model loader with drei's useGLTF
4. Add smooth OrbitControls with momentum
5. Create beautiful loading animation
6. Implement fullscreen mode
7. Add zoom and reset controls
8. Ensure mobile responsiveness

#### Deliverables:
- `PremiumModelViewer` component
- Loading animation
- Basic controls toolbar

#### Success Criteria:
- Viewer loads GLB files
- 60 FPS on modern devices
- Works on mobile browsers
- Looks significantly better than current viewer

### Phase 2: Measurements & Navigation (Week 3-4)

**Goal**: Add measurement overlays and navigation aids

#### Tasks:
1. Parse RoomPlan measurements JSON
2. Create 3D measurement labels (drei's Html or Billboard)
3. Build minimap component
4. Implement click-on-minimap navigation
5. Add view mode selector (orbit/top/walkthrough)
6. Add post-processing effects (SSAO, subtle bloom)
7. Implement keyboard shortcuts
8. Add screenshot functionality

#### Deliverables:
- Measurement annotations in 3D
- Minimap component
- Multiple view modes
- Screenshot button

#### Success Criteria:
- Measurements display accurately in 3D
- Minimap shows camera position
- Users can navigate via minimap clicks

### Phase 3: Polish & Advanced Features (Week 5-6)

**Goal**: Premium touches and advanced interactions

#### Tasks:
1. Object highlighting on hover
2. Click-to-select with detail panel
3. Onboarding tooltip for new users
4. Multiple lighting presets
5. Light/dark theme support
6. AR Quick Look integration
7. Share button with link generation

#### Deliverables:
- Interactive object selection
- Lighting preset switcher
- Share functionality

#### Success Criteria:
- Users can interact with individual room elements
- AR works on iOS devices
- Shareable links work

### Phase 4: Future Enhancements (Future)

**Goal**: Cutting-edge features

#### Potential Features:
- Product visualization overlay
- WebXR VR mode
- Collaborative viewing
- AI-powered suggestions

---

## 8. Performance Benchmarks

### Target Metrics

| Metric | Target | Acceptable | Poor |
|--------|--------|------------|------|
| Initial Load (3G) | < 3s | < 5s | > 8s |
| Initial Load (4G) | < 2s | < 3s | > 5s |
| Time to Interactive | < 1s | < 2s | > 3s |
| Frame Rate | 60 FPS | 45 FPS | < 30 FPS |
| Memory Usage | < 200MB | < 400MB | > 600MB |
| Bundle Size | < 300KB | < 500KB | > 800KB |

### Optimization Strategies

#### Model Optimization
```
1. GLB Compression
   - Use Draco compression for meshes (up to 90% smaller)
   - Use KTX2 for textures (up to 75% smaller)

2. Level of Detail (LOD)
   - Generate multiple LOD levels for large models
   - Switch based on camera distance

3. Mesh Optimization
   - Remove hidden faces
   - Simplify geometry where possible
   - Use instancing for repeated objects
```

#### Loading Optimization
```
1. Progressive Loading
   - Show low-res model immediately
   - Stream high-res textures progressively

2. Lazy Loading
   - Don't load 3D viewer until tab is clicked
   - Use Suspense for loading states

3. Caching
   - Cache GLB files in IndexedDB
   - Use service worker for offline support
```

#### Rendering Optimization
```
1. Frustum Culling
   - Only render objects in camera view

2. Occlusion Culling
   - Don't render hidden objects

3. Frame Limiting
   - Use invalidateFrameloop in R3F
   - Only render when scene changes

4. Resolution Scaling
   - Reduce render resolution on low-end devices
   - Use dpr={[1, 2]} for adaptive pixel ratio
```

### Performance Monitoring

```typescript
// usePerformance.ts hook

import { useFrame } from '@react-three/fiber'
import { useState, useRef } from 'react'

export function usePerformance() {
  const [fps, setFps] = useState(60)
  const [triangles, setTriangles] = useState(0)
  const [drawCalls, setDrawCalls] = useState(0)

  const frames = useRef(0)
  const lastTime = useRef(performance.now())

  useFrame(({ gl }) => {
    frames.current++
    const now = performance.now()

    if (now - lastTime.current >= 1000) {
      setFps(Math.round(frames.current))
      setTriangles(gl.info.render.triangles)
      setDrawCalls(gl.info.render.calls)

      frames.current = 0
      lastTime.current = now
    }
  })

  return { fps, triangles, drawCalls }
}
```

---

## 9. Inspiration Gallery

### Impressive 3D Web Experiences to Study

#### Product Configurators
1. **Apple Product Pages** - Smooth 3D product rotation with subtle effects
2. **Nike Sneaker Configurator** - Interactive customization with WebGL
3. **Tesla Car Configurator** - High-quality automotive 3D rendering

#### Architectural Visualization
1. **Matterport Showcase** - Industry standard for 3D space tours
2. **Archilogic** - Interactive floor plan to 3D
3. **Planner 5D** - Room design with 3D preview

#### Technical Showcases
1. **Bruno Simon's Portfolio** (bruno-simon.com) - Creative 3D experience
2. **Lusion Interactive** - Agency with stunning WebGL work
3. **Active Theory Projects** - High-end interactive experiences

### Design Principles to Adopt

#### Visual Quality
- **Soft shadows** - Avoid harsh, unrealistic shadows
- **Ambient occlusion** - Adds depth and realism
- **Subtle bloom** - Creates premium feel on highlights
- **Color grading** - Consistent, warm color palette
- **Anti-aliasing** - Smooth edges (SMAA or FXAA)

#### Interaction Design
- **Smooth easing** - All transitions use easing curves
- **Momentum** - Camera controls have inertia
- **Snap points** - Camera snaps to useful angles
- **Hover feedback** - Objects respond to hover
- **Touch-friendly** - Large touch targets, gesture support

#### Loading Experience
- **Never empty** - Always show something (preview, skeleton)
- **Progress indication** - Show loading progress when possible
- **Smooth transitions** - Fade in the model smoothly
- **Fallback content** - Show preview image if 3D fails

---

## Appendix A: Code Examples

### Basic R3F Setup

```tsx
// Scene.tsx

import { Canvas } from '@react-three/fiber'
import { OrbitControls, Environment, ContactShadows } from '@react-three/drei'
import { Suspense } from 'react'

export function Scene({ children }: { children: React.ReactNode }) {
  return (
    <Canvas
      camera={{ position: [5, 5, 5], fov: 45 }}
      dpr={[1, 2]}
      gl={{
        antialias: true,
        alpha: true,
        powerPreference: 'high-performance'
      }}
    >
      <Suspense fallback={<LoadingFallback />}>
        {/* Lighting */}
        <ambientLight intensity={0.4} />
        <directionalLight
          position={[10, 10, 5]}
          intensity={1.5}
          castShadow
        />

        {/* Environment for reflections */}
        <Environment preset="apartment" />

        {/* Contact shadows for grounding */}
        <ContactShadows
          position={[0, -0.01, 0]}
          opacity={0.5}
          scale={10}
          blur={2}
        />

        {/* Model and annotations */}
        {children}

        {/* Controls */}
        <OrbitControls
          enableDamping
          dampingFactor={0.05}
          minDistance={2}
          maxDistance={20}
          maxPolarAngle={Math.PI / 2}
        />
      </Suspense>
    </Canvas>
  )
}
```

### Model Loader

```tsx
// Model.tsx

import { useGLTF, useProgress } from '@react-three/drei'
import { useEffect, useRef } from 'react'
import * as THREE from 'three'

interface ModelProps {
  url: string
  onLoad?: () => void
}

export function Model({ url, onLoad }: ModelProps) {
  const { scene } = useGLTF(url)
  const modelRef = useRef<THREE.Group>(null)

  useEffect(() => {
    if (scene) {
      // Center the model
      const box = new THREE.Box3().setFromObject(scene)
      const center = box.getCenter(new THREE.Vector3())
      scene.position.sub(center)

      // Enable shadows
      scene.traverse((child) => {
        if (child instanceof THREE.Mesh) {
          child.castShadow = true
          child.receiveShadow = true
        }
      })

      onLoad?.()
    }
  }, [scene, onLoad])

  return <primitive ref={modelRef} object={scene} />
}

// Preload models
useGLTF.preload('/models/room.glb')
```

### Measurement Label

```tsx
// MeasurementLabel.tsx

import { Html, Line } from '@react-three/drei'
import { Vector3 } from 'three'

interface MeasurementLabelProps {
  start: [number, number, number]
  end: [number, number, number]
  label: string
  color?: string
}

export function MeasurementLabel({
  start,
  end,
  label,
  color = '#2563EB'
}: MeasurementLabelProps) {
  const midpoint = new Vector3()
    .fromArray(start)
    .add(new Vector3().fromArray(end))
    .multiplyScalar(0.5)

  return (
    <group>
      {/* Measurement line */}
      <Line
        points={[start, end]}
        color={color}
        lineWidth={2}
        dashed
        dashScale={10}
      />

      {/* End caps */}
      <mesh position={start}>
        <sphereGeometry args={[0.02, 16, 16]} />
        <meshBasicMaterial color={color} />
      </mesh>
      <mesh position={end}>
        <sphereGeometry args={[0.02, 16, 16]} />
        <meshBasicMaterial color={color} />
      </mesh>

      {/* Label */}
      <Html
        position={[midpoint.x, midpoint.y + 0.1, midpoint.z]}
        center
        distanceFactor={10}
      >
        <div className="px-2 py-1 bg-white rounded shadow text-sm font-mono">
          {label}
        </div>
      </Html>
    </group>
  )
}
```

---

## Appendix B: Database Schema Updates

```sql
-- Update project_measurements for 3D viewer support

ALTER TABLE project_measurements ADD COLUMN IF NOT EXISTS glb_file_url TEXT;
ALTER TABLE project_measurements ADD COLUMN IF NOT EXISTS glb_file_size BIGINT;
ALTER TABLE project_measurements ADD COLUMN IF NOT EXISTS conversion_status TEXT
  DEFAULT 'pending'
  CHECK (conversion_status IN ('pending', 'processing', 'completed', 'failed', 'not_needed'));
ALTER TABLE project_measurements ADD COLUMN IF NOT EXISTS conversion_error TEXT;
ALTER TABLE project_measurements ADD COLUMN IF NOT EXISTS converted_at TIMESTAMPTZ;

-- Index for finding unconverted files
CREATE INDEX IF NOT EXISTS idx_measurements_conversion_status
  ON project_measurements(conversion_status)
  WHERE conversion_status = 'pending';

-- Comment for documentation
COMMENT ON COLUMN project_measurements.glb_file_url IS
  'URL to the GLB file converted from USDZ for web viewing';
COMMENT ON COLUMN project_measurements.conversion_status IS
  'Status of USDZ to GLB conversion: pending, processing, completed, failed, not_needed';
```

---

## Appendix C: Edge Function for USDZ Upload

```typescript
// supabase/functions/submit-project/index.ts
// Updated to handle USDZ upload and trigger conversion

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  // ... existing code ...

  // After USDZ is uploaded to storage
  if (usdzFileUrl) {
    // Queue GLB conversion (async)
    const conversionResponse = await fetch(
      `${Deno.env.get('SUPABASE_URL')}/functions/v1/convert-usdz-to-glb`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          projectId,
          measurementId,
          usdzUrl: usdzFileUrl
        })
      }
    )

    // Don't wait for conversion - it happens in background
    console.log('Conversion queued:', conversionResponse.status)
  }

  // ... rest of function ...
})
```

---

## Sources & References

### 3D Visualization Libraries
- [React Three Fiber Documentation](https://r3f.docs.pmnd.rs/getting-started/introduction)
- [Drei Helpers Library](https://github.com/pmndrs/drei)
- [Vercel: Add 3D to web projects with R3F](https://vercel.com/blog/add-3d-to-your-web-projects-with-v0-and-react-three-fiber)
- [Three.js vs Babylon.js Comparison](https://blog.logrocket.com/three-js-vs-babylon-js/)
- [Babylon.js vs React Three Fiber](https://aircada.com/blog/babylon-js-vs-react-three-fiber)

### File Format & Conversion
- [Meshy AI USDZ to GLB Converter](https://www.meshy.ai/3d-tools/file-converter/usdz/to/glb)
- [Convert3D.org](https://convert3d.org/usdz-to-glb)
- [Sirv USDZ to GLB API](https://sirv.com/help/articles/convert-usdz-to-glb-via-api/)

### Competitor Research
- [Matterport Platform](https://matterport.com/)
- [Canvas.io Pricing](https://canvas.io/pricing/)
- [iGUIDE Floor Plans](https://goiguide.com/)
- [Cupix Features](https://homes.cupix.com/homes/features/standard.html)

### Apple RoomPlan
- [RoomPlan Developer Overview](https://developer.apple.com/augmented-reality/roomplan/)
- [WWDC22: Create parametric 3D room scans](https://developer.apple.com/videos/play/wwdc2022/10127/)
- [WWDC23: Explore enhancements to RoomPlan](https://developer.apple.com/videos/play/wwdc2023/10192/)

### WebGL Inspiration
- [Awwwards WebGL Examples](https://www.awwwards.com/30-experimental-webgl-websites.html)
- [Creative Bloq WebGL Showcase](https://www.creativebloq.com/3d/30-amazing-examples-webgl-action-6142954)
- [Slider Revolution WebGL Examples](https://www.sliderrevolution.com/design/webgl-examples/)

---

*Document generated by NextLean Scan Architect Agent*
