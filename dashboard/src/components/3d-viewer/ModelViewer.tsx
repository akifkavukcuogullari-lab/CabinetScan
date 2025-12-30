'use client'

import { useEffect, useRef, useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import {
  Box,
  Maximize2,
  Minimize2,
  RotateCcw,
  Download,
  Smartphone,
  Loader2,
  Eye,
  Monitor,
  ExternalLink
} from 'lucide-react'

interface ModelViewerProps {
  glbUrl?: string        // GLB for web 3D viewing
  usdzUrl?: string       // USDZ for iOS AR Quick Look
  previewImageUrl?: string
  alt?: string
  className?: string
  showTitle?: boolean
  title?: string
  description?: string
  compact?: boolean
  minimal?: boolean      // Clean mode with floating controls for embedded views
  rotationAngle?: number // Auto-straightening rotation angle in degrees
  onError?: () => void
}

export function ModelViewer({
  glbUrl,
  usdzUrl,
  previewImageUrl,
  alt = '3D Room Scan',
  className = '',
  showTitle = true,
  title = '3D Room Scan',
  description = 'Interactive 3D model captured with LiDAR',
  compact = false,
  minimal = false,
  rotationAngle = 0,
  onError
}: ModelViewerProps) {
  const containerRef = useRef<HTMLDivElement>(null)
  const viewerContainerRef = useRef<HTMLDivElement>(null)
  const modelViewerRef = useRef<HTMLElement | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [hasError, setHasError] = useState(false)
  const [isFullscreen, setIsFullscreen] = useState(false)
  const [isScriptLoaded, setIsScriptLoaded] = useState(false)
  const [isIOS, setIsIOS] = useState(false)

  // Detect iOS device
  useEffect(() => {
    if (typeof window !== 'undefined') {
      const iOS = /iPad|iPhone|iPod/.test(navigator.userAgent)
      setIsIOS(iOS)
    }
  }, [])

  // Load model-viewer script when we have GLB
  useEffect(() => {
    if (!glbUrl) {
      setIsLoading(false)
      return
    }

    const existingScript = document.querySelector('script[src*="model-viewer"]')
    if (existingScript) {
      setIsScriptLoaded(true)
      return
    }

    const script = document.createElement('script')
    script.type = 'module'
    script.src = 'https://ajax.googleapis.com/ajax/libs/model-viewer/3.3.0/model-viewer.min.js'
    script.onload = () => setIsScriptLoaded(true)
    script.onerror = () => {
      console.error('Failed to load model-viewer script')
      setHasError(true)
    }
    document.head.appendChild(script)
  }, [glbUrl])

  // Handle model-viewer events
  useEffect(() => {
    if (!isScriptLoaded || !modelViewerRef.current) return

    const viewer = modelViewerRef.current

    const handleLoad = () => {
      setIsLoading(false)
      setHasError(false)
    }

    const handleError = () => {
      setIsLoading(false)
      setHasError(true)
      onError?.()
    }

    // Set a timeout to detect if model fails to load
    const timeoutId = setTimeout(() => {
      if (isLoading) {
        setIsLoading(false)
      }
    }, 15000) // 15 second timeout

    viewer.addEventListener('load', handleLoad)
    viewer.addEventListener('error', handleError)

    return () => {
      clearTimeout(timeoutId)
      viewer.removeEventListener('load', handleLoad)
      viewer.removeEventListener('error', handleError)
    }
  }, [isScriptLoaded, isLoading, onError])

  // Handle fullscreen toggle - only fullscreen the viewer area
  const toggleFullscreen = async () => {
    if (!viewerContainerRef.current) return

    if (!isFullscreen) {
      try {
        await viewerContainerRef.current.requestFullscreen()
        setIsFullscreen(true)
      } catch (err) {
        console.error('Fullscreen not supported:', err)
      }
    } else {
      try {
        await document.exitFullscreen()
        setIsFullscreen(false)
      } catch (err) {
        console.error('Error exiting fullscreen:', err)
      }
    }
  }

  // Listen for fullscreen changes
  useEffect(() => {
    const handleFullscreenChange = () => {
      setIsFullscreen(!!document.fullscreenElement)
    }
    document.addEventListener('fullscreenchange', handleFullscreenChange)
    return () => document.removeEventListener('fullscreenchange', handleFullscreenChange)
  }, [])

  // Reset camera position
  const resetCamera = () => {
    if (modelViewerRef.current) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const viewer = modelViewerRef.current as any
      viewer.cameraOrbit = 'auto auto auto'
      viewer.fieldOfView = 'auto'
    }
  }

  const viewerHeight = minimal ? 'h-[60vh] min-h-[400px]' : compact ? 'h-64' : 'h-[400px]'

  // If no GLB available, show fallback with preview image
  if (!glbUrl) {
    // Minimal mode - clean viewer without Card wrapper
    if (minimal) {
      return (
        <div className={`relative ${className}`} ref={containerRef}>
          <div
            ref={viewerContainerRef}
            className={`relative ${viewerHeight} w-full rounded-lg overflow-hidden bg-gray-50`}
          >
            {/* Preview image */}
            {previewImageUrl ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={previewImageUrl}
                alt={alt}
                className="w-full h-full object-contain"
              />
            ) : (
              <div className="w-full h-full flex items-center justify-center">
                <div className="text-center">
                  <Box className="h-16 w-16 text-gray-300 mx-auto mb-3" />
                  <p className="text-gray-400 text-sm">No 3D model available</p>
                </div>
              </div>
            )}

            {/* Floating controls */}
            <div className="absolute top-3 right-3 z-20 flex gap-1 bg-white/90 backdrop-blur-sm rounded-full px-2 py-1 shadow-sm border border-gray-200/50">
              <Button
                variant="ghost"
                size="icon"
                className="h-8 w-8"
                onClick={toggleFullscreen}
                title={isFullscreen ? 'Exit fullscreen' : 'Enter fullscreen'}
              >
                {isFullscreen ? <Minimize2 className="h-4 w-4" /> : <Maximize2 className="h-4 w-4" />}
              </Button>
            </div>
          </div>
        </div>
      )
    }

    // Standard fallback with Card wrapper
    const hasUsdzFile = !!usdzUrl

    return (
      <Card className={className} ref={containerRef}>
        {showTitle && (
          <CardHeader className="pb-2">
            <div className="flex items-center justify-between">
              <div>
                <CardTitle className="flex items-center gap-2">
                  <Box className="h-5 w-5 text-blue-600" />
                  {title}
                </CardTitle>
                <CardDescription>
                  {hasUsdzFile
                    ? 'Download the 3D model or view in AR on Apple devices'
                    : description}
                </CardDescription>
              </div>
              <div className="flex items-center gap-2">
                {usdzUrl && (
                  <a href={usdzUrl} download>
                    <Button variant="outline" size="sm" title="Download USDZ file">
                      <Download className="h-4 w-4" />
                    </Button>
                  </a>
                )}
              </div>
            </div>
          </CardHeader>
        )}
        <CardContent className={showTitle ? 'pt-2' : ''}>
          <div className={`relative ${viewerHeight} w-full rounded-lg overflow-hidden bg-gradient-to-b from-gray-900 to-gray-800`}>
            {/* Preview image */}
            {previewImageUrl ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={previewImageUrl}
                alt={alt}
                className="w-full h-full object-contain"
              />
            ) : (
              <div className="w-full h-full flex items-center justify-center">
                <div className="text-center">
                  <Box className="h-20 w-20 text-gray-600 mx-auto mb-4" />
                  <p className="text-gray-400 text-sm">3D Model Preview</p>
                </div>
              </div>
            )}

            {/* Overlay with info and actions */}
            <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-transparent to-transparent flex flex-col justify-end p-6">
              <div className="text-white space-y-4">
                {hasUsdzFile ? (
                  <>
                    <div className="bg-white/10 backdrop-blur-sm rounded-lg p-4 border border-white/20">
                      <div className="flex items-start gap-3">
                        <div className="bg-blue-500/20 rounded-full p-2">
                          <Smartphone className="h-5 w-5 text-blue-400" />
                        </div>
                        <div className="flex-1">
                          <p className="font-medium text-white mb-1">3D Model Available</p>
                          <p className="text-sm text-gray-300">
                            This scan includes a USDZ 3D model. Download to view on Mac, or open directly on iPhone/iPad to see in AR.
                          </p>
                        </div>
                      </div>
                    </div>
                    <div className="flex flex-wrap gap-3">
                      <a href={usdzUrl} download className="inline-block">
                        <Button
                          className="bg-blue-600 hover:bg-blue-700 text-white shadow-lg"
                          size="sm"
                        >
                          <Download className="h-4 w-4 mr-2" />
                          Download USDZ
                        </Button>
                      </a>
                      <a
                        href={usdzUrl}
                        rel="ar"
                        className="inline-block"
                      >
                        <Button
                          variant="outline"
                          className="bg-white/10 hover:bg-white/20 text-white border-white/30"
                          size="sm"
                        >
                          <Smartphone className="h-4 w-4 mr-2" />
                          View in AR (iOS/iPadOS)
                        </Button>
                      </a>
                    </div>
                  </>
                ) : (
                  <div className="flex items-center gap-2 text-sm opacity-90">
                    <Monitor className="h-4 w-4" />
                    <span>No 3D model available for this scan</span>
                  </div>
                )}
              </div>
            </div>
          </div>
        </CardContent>
      </Card>
    )
  }

  // GLB is available - show full 3D viewer
  // Apply rotation angle to model orientation for auto-straightening (rotate around Y-axis)
  const modelViewerHTML = isScriptLoaded ? `
    <model-viewer
      src="${glbUrl}"
      ${usdzUrl ? `ios-src="${usdzUrl}"` : ''}
      ${previewImageUrl ? `poster="${previewImageUrl}"` : ''}
      alt="${alt}"
      camera-controls
      auto-rotate
      rotation-per-second="30deg"
      shadow-intensity="1"
      shadow-softness="0.5"
      exposure="1"
      environment-image="neutral"
      loading="eager"
      interaction-prompt="auto"
      interaction-prompt-style="wiggle"
      interaction-prompt-threshold="3000"
      camera-orbit="45deg 55deg auto"
      orientation="0deg ${-rotationAngle}deg 0deg"
      field-of-view="45deg"
      min-camera-orbit="auto auto auto"
      max-camera-orbit="auto auto auto"
      min-field-of-view="25deg"
      max-field-of-view="75deg"
      style="width: 100%; height: 100%; background-color: transparent;"
    ></model-viewer>
  ` : ''

  // Minimal mode with floating controls and light background
  if (minimal) {
    return (
      <div className={`relative ${className}`} ref={containerRef}>
        <div
          ref={viewerContainerRef}
          className={`relative ${isFullscreen ? 'h-screen w-screen' : viewerHeight + ' w-full'} rounded-lg overflow-hidden bg-gray-50`}
        >
          {/* Floating controls */}
          <div className="absolute top-3 right-3 z-20 flex gap-1 bg-white/90 backdrop-blur-sm rounded-full px-2 py-1 shadow-sm border border-gray-200/50">
            <Button
              variant="ghost"
              size="icon"
              className="h-8 w-8"
              onClick={resetCamera}
              title="Reset camera position"
            >
              <RotateCcw className="h-4 w-4" />
            </Button>
            <Button
              variant="ghost"
              size="icon"
              className="h-8 w-8"
              onClick={toggleFullscreen}
              title={isFullscreen ? 'Exit fullscreen' : 'Enter fullscreen'}
            >
              {isFullscreen ? <Minimize2 className="h-4 w-4" /> : <Maximize2 className="h-4 w-4" />}
            </Button>
          </div>

          {/* Loading overlay */}
          {isLoading && (
            <div className="absolute inset-0 flex flex-col items-center justify-center bg-white/90 z-10">
              <Loader2 className="h-8 w-8 text-blue-500 animate-spin mb-2" />
              <p className="text-gray-600 text-sm">Loading 3D Model...</p>
            </div>
          )}

          {/* Model viewer container */}
          {isScriptLoaded && (
            <div
              ref={(el) => {
                if (el) {
                  modelViewerRef.current = el.querySelector('model-viewer')
                }
              }}
              className="w-full h-full"
              dangerouslySetInnerHTML={{ __html: modelViewerHTML }}
            />
          )}

          {/* Interaction hint - subtle */}
          {!isLoading && !hasError && (
            <div className="absolute bottom-3 left-3 z-20 text-xs text-gray-500 bg-white/80 backdrop-blur-sm px-2 py-1 rounded-full border border-gray-200/50">
              Drag to rotate | Scroll to zoom
            </div>
          )}
        </div>
      </div>
    )
  }

  // Standard mode with Card wrapper
  return (
    <Card className={className} ref={containerRef}>
      {showTitle && (
        <CardHeader className="pb-2">
          <div className="flex items-center justify-between">
            <div>
              <CardTitle className="flex items-center gap-2">
                <Box className="h-5 w-5 text-blue-600" />
                {title}
              </CardTitle>
              <CardDescription>{description}</CardDescription>
            </div>
            <div className="flex items-center gap-2">
              <Button
                variant="outline"
                size="sm"
                onClick={resetCamera}
                title="Reset camera position"
              >
                <RotateCcw className="h-4 w-4" />
              </Button>
              <Button
                variant="outline"
                size="sm"
                onClick={toggleFullscreen}
                title={isFullscreen ? 'Exit fullscreen' : 'Enter fullscreen'}
              >
                {isFullscreen ? (
                  <Minimize2 className="h-4 w-4" />
                ) : (
                  <Maximize2 className="h-4 w-4" />
                )}
              </Button>
              {usdzUrl && (
                <a href={usdzUrl} download>
                  <Button variant="outline" size="sm" title="Download USDZ file">
                    <Download className="h-4 w-4" />
                  </Button>
                </a>
              )}
            </div>
          </div>
        </CardHeader>
      )}
      <CardContent className={showTitle ? 'pt-2' : ''}>
        <div
          ref={viewerContainerRef}
          className={`relative ${isFullscreen ? 'h-screen w-screen' : viewerHeight + ' w-full'} rounded-lg overflow-hidden bg-gradient-to-b from-gray-900 to-gray-800`}
        >
          {/* Fullscreen exit button */}
          {isFullscreen && (
            <div className="absolute top-4 right-4 z-30 flex gap-2">
              <Button
                variant="outline"
                size="sm"
                onClick={resetCamera}
                className="bg-white/10 hover:bg-white/20 text-white border-white/30"
                title="Reset camera position"
              >
                <RotateCcw className="h-4 w-4" />
              </Button>
              <Button
                variant="outline"
                size="sm"
                onClick={toggleFullscreen}
                className="bg-white/10 hover:bg-white/20 text-white border-white/30"
                title="Exit fullscreen"
              >
                <Minimize2 className="h-4 w-4" />
              </Button>
            </div>
          )}

          {/* Loading overlay */}
          {isLoading && (
            <div className="absolute inset-0 flex flex-col items-center justify-center bg-gray-900/90 z-10">
              <Loader2 className="h-10 w-10 text-blue-400 animate-spin mb-3" />
              <p className="text-gray-200 font-medium">Loading 3D Model...</p>
              <p className="text-gray-400 text-sm">This may take a moment</p>
            </div>
          )}

          {/* Model viewer container */}
          {isScriptLoaded && (
            <div
              ref={(el) => {
                if (el) {
                  modelViewerRef.current = el.querySelector('model-viewer')
                }
              }}
              className="w-full h-full"
              dangerouslySetInnerHTML={{ __html: modelViewerHTML }}
            />
          )}

          {/* AR button overlay (iOS only) */}
          {isIOS && usdzUrl && !isLoading && !hasError && (
            <div className="absolute bottom-4 right-4 z-20">
              <Button
                size="sm"
                className="bg-blue-600 hover:bg-blue-700 text-white shadow-lg"
                onClick={() => {
                  // eslint-disable-next-line @typescript-eslint/no-explicit-any
                  const viewer = modelViewerRef.current as any
                  if (viewer?.activateAR) {
                    viewer.activateAR()
                  }
                }}
              >
                <Smartphone className="h-4 w-4 mr-2" />
                View in AR
              </Button>
            </div>
          )}

          {/* Interaction hint */}
          {!isLoading && !hasError && (
            <div className="absolute bottom-4 left-4 z-20 text-xs text-white/70 bg-black/40 px-2 py-1 rounded">
              Drag to rotate | Scroll to zoom | Shift+drag to pan
            </div>
          )}
        </div>
      </CardContent>
    </Card>
  )
}

// Compact viewer for list/card contexts
export function ModelViewerCompact({
  glbUrl,
  usdzUrl,
  previewImageUrl,
  alt = '3D Room Scan',
  className = '',
  onClick
}: {
  glbUrl?: string
  usdzUrl?: string
  previewImageUrl?: string
  alt?: string
  className?: string
  onClick?: () => void
}) {
  const [isHovered, setIsHovered] = useState(false)
  const [hasError, setHasError] = useState(false)

  const hasModel = glbUrl || usdzUrl

  if (hasError || !hasModel) {
    return (
      <div
        className={`relative h-32 w-full rounded-lg bg-gray-100 flex items-center justify-center ${className}`}
        onClick={onClick}
      >
        <Box className="h-8 w-8 text-gray-400" />
      </div>
    )
  }

  return (
    <div
      className={`relative h-32 w-full rounded-lg overflow-hidden cursor-pointer group ${className}`}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
      onClick={onClick}
    >
      {previewImageUrl ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={previewImageUrl}
          alt={alt}
          className="w-full h-full object-cover transition-transform duration-300 group-hover:scale-105"
          onError={() => setHasError(true)}
        />
      ) : (
        <div className="w-full h-full bg-gradient-to-br from-blue-50 to-blue-100 flex items-center justify-center">
          <Box className="h-10 w-10 text-blue-400" />
        </div>
      )}

      {/* Hover overlay */}
      <div className={`absolute inset-0 bg-black/40 flex items-center justify-center transition-opacity duration-200 ${isHovered ? 'opacity-100' : 'opacity-0'}`}>
        <div className="flex items-center gap-2 text-white font-medium">
          <Eye className="h-5 w-5" />
          View 3D Scan
        </div>
      </div>

      {/* 3D indicator badge */}
      <div className="absolute top-2 right-2 bg-blue-600 text-white text-xs px-2 py-1 rounded-full font-medium">
        3D
      </div>
    </div>
  )
}
