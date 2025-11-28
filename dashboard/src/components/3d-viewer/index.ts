// Premium 3D Viewer Components
// Uses React Three Fiber for high-performance WebGL rendering

export { PremiumModelViewer, PremiumModelViewerCompact } from './PremiumModelViewer'
export type { PremiumModelViewerProps } from './PremiumModelViewer'

// Legacy model-viewer based component (fallback for USDZ-only)
export { ModelViewer, ModelViewerCompact } from './ModelViewer'

// Individual scene components (for advanced customization)
export { Scene, preloadModel } from './Scene'
export { Controls } from './Controls'
export type { ControlsRef } from './Controls'
export { Toolbar, InteractionHint } from './Toolbar'
export { LoadingScreen } from './LoadingScreen'
