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
  AlertCircle,
  Eye
} from 'lucide-react'

interface ModelViewerProps {
  usdzUrl: string
  previewImageUrl?: string
  alt?: string
  className?: string
  showTitle?: boolean
  title?: string
  description?: string
  compact?: boolean
  onError?: () => void
}

export function ModelViewer({
  usdzUrl,
  previewImageUrl,
  alt = '3D Room Scan',
  className = '',
  showTitle = true,
  title = '3D Room Scan',
  description = 'Interactive 3D model captured with LiDAR',
  compact = false,
  onError
}: ModelViewerProps) {
  const containerRef = useRef<HTMLDivElement>(null)
  const modelViewerRef = useRef<HTMLElement | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [hasError, setHasError] = useState(false)
  const [isFullscreen, setIsFullscreen] = useState(false)
  const [isScriptLoaded, setIsScriptLoaded] = useState(false)
  const [supportsAR, setSupportsAR] = useState(false)

  // Load model-viewer script
  useEffect(() => {
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

    return () => {
      // Keep script loaded for future use
    }
  }, [])

  // Check AR support
  useEffect(() => {
    if (typeof window !== 'undefined') {
      // Check for WebXR or iOS AR Quick Look support
      const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent)
      const hasWebXR = 'xr' in navigator
      setSupportsAR(isIOS || hasWebXR)
    }
  }, [])

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

    viewer.addEventListener('load', handleLoad)
    viewer.addEventListener('error', handleError)

    return () => {
      viewer.removeEventListener('load', handleLoad)
      viewer.removeEventListener('error', handleError)
    }
  }, [isScriptLoaded, onError])

  // Handle fullscreen toggle
  const toggleFullscreen = async () => {
    if (!containerRef.current) return

    if (!isFullscreen) {
      try {
        await containerRef.current.requestFullscreen()
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

  // Render error state
  if (hasError && !isLoading) {
    return (
      <Card className={className}>
        {showTitle && (
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Box className="h-5 w-5" />
              {title}
            </CardTitle>
            <CardDescription>{description}</CardDescription>
          </CardHeader>
        )}
        <CardContent>
          <div className={`flex flex-col items-center justify-center bg-gray-50 rounded-lg border-2 border-dashed border-gray-200 ${compact ? 'py-8' : 'py-16'}`}>
            <AlertCircle className="h-12 w-12 text-gray-400 mb-4" />
            <h3 className="text-lg font-medium text-gray-700 mb-2">Unable to Load 3D Model</h3>
            <p className="text-gray-500 text-sm text-center max-w-sm mb-4">
              The 3D model could not be displayed. You can download the file to view it in a compatible viewer.
            </p>
            <a
              href={usdzUrl}
              download
              className="inline-flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
            >
              <Download className="h-4 w-4" />
              Download USDZ File
            </a>
          </div>
        </CardContent>
      </Card>
    )
  }

  const viewerHeight = compact ? 'h-64' : 'h-[500px]'

  // Create model-viewer element using dangerouslySetInnerHTML since it's a custom element
  const modelViewerHTML = isScriptLoaded ? `
    <model-viewer
      src="${usdzUrl}"
      ios-src="${usdzUrl}"
      ${previewImageUrl ? `poster="${previewImageUrl}"` : ''}
      alt="${alt}"
      camera-controls
      auto-rotate
      rotation-per-second="30deg"
      shadow-intensity="1"
      shadow-softness="0.5"
      exposure="1"
      ${supportsAR ? 'ar ar-modes="webxr scene-viewer quick-look" ar-scale="fixed"' : ''}
      environment-image="neutral"
      loading="eager"
      interaction-prompt="auto"
      interaction-prompt-style="wiggle"
      interaction-prompt-threshold="3000"
      camera-orbit="45deg 55deg auto"
      field-of-view="45deg"
      min-camera-orbit="auto auto auto"
      max-camera-orbit="auto auto auto"
      min-field-of-view="25deg"
      max-field-of-view="75deg"
      style="width: 100%; height: 100%; background-color: transparent;"
    ></model-viewer>
  ` : ''

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
              <a href={usdzUrl} download>
                <Button variant="outline" size="sm" title="Download USDZ file">
                  <Download className="h-4 w-4" />
                </Button>
              </a>
            </div>
          </div>
        </CardHeader>
      )}
      <CardContent className={showTitle ? 'pt-2' : ''}>
        <div className={`relative ${viewerHeight} w-full rounded-lg overflow-hidden bg-gradient-to-b from-gray-100 to-gray-200`}>
          {/* Loading overlay */}
          {isLoading && (
            <div className="absolute inset-0 flex flex-col items-center justify-center bg-gray-100/90 z-10">
              <Loader2 className="h-10 w-10 text-blue-600 animate-spin mb-3" />
              <p className="text-gray-600 font-medium">Loading 3D Model...</p>
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

          {/* AR button overlay */}
          {supportsAR && !isLoading && !hasError && (
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
            <div className="absolute bottom-4 left-4 z-20 text-xs text-gray-500 bg-white/80 px-2 py-1 rounded">
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
  usdzUrl,
  previewImageUrl,
  alt = '3D Room Scan',
  className = '',
  onClick
}: {
  usdzUrl: string
  previewImageUrl?: string
  alt?: string
  className?: string
  onClick?: () => void
}) {
  const [isHovered, setIsHovered] = useState(false)
  const [hasError, setHasError] = useState(false)

  if (hasError || !usdzUrl) {
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
