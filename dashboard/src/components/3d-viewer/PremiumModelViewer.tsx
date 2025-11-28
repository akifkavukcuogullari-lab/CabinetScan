'use client'

import { Suspense, useRef, useState, useEffect, useCallback } from 'react'
import { Canvas } from '@react-three/fiber'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import {
  Box,
  AlertCircle,
  Download,
  RefreshCw
} from 'lucide-react'

import { Scene } from './Scene'
import { Controls, ControlsRef } from './Controls'
import { Toolbar, InteractionHint } from './Toolbar'
import { LoadingScreen } from './LoadingScreen'

export interface PremiumModelViewerProps {
  glbUrl?: string
  usdzUrl?: string // For AR fallback/download
  title?: string
  description?: string
  className?: string
  showTitle?: boolean
  compact?: boolean
  onLoad?: () => void
  onError?: (error: Error) => void
}

// Error fallback component
function ErrorState({
  error,
  downloadUrl,
  onRetry
}: {
  error: Error
  downloadUrl?: string
  onRetry: () => void
}) {
  return (
    <div className="flex flex-col items-center justify-center h-full bg-slate-50 rounded-lg p-8">
      <div className="w-16 h-16 rounded-full bg-red-100 flex items-center justify-center mb-4">
        <AlertCircle className="h-8 w-8 text-red-500" />
      </div>
      <h3 className="text-lg font-semibold text-slate-900 mb-2">
        Unable to Load 3D Model
      </h3>
      <p className="text-slate-500 text-sm text-center max-w-md mb-6">
        {error.message || 'The 3D model could not be displayed. Please try again or download the file to view it in a compatible viewer.'}
      </p>
      <div className="flex items-center gap-3">
        <Button variant="outline" onClick={onRetry}>
          <RefreshCw className="h-4 w-4 mr-2" />
          Try Again
        </Button>
        {downloadUrl && (
          <a href={downloadUrl} download>
            <Button>
              <Download className="h-4 w-4 mr-2" />
              Download File
            </Button>
          </a>
        )}
      </div>
    </div>
  )
}

// No model URL state
function NoModelState() {
  return (
    <div className="flex flex-col items-center justify-center h-full bg-slate-50 rounded-lg p-8">
      <div className="w-16 h-16 rounded-full bg-slate-100 flex items-center justify-center mb-4">
        <Box className="h-8 w-8 text-slate-400" />
      </div>
      <h3 className="text-lg font-semibold text-slate-900 mb-2">
        No 3D Model Available
      </h3>
      <p className="text-slate-500 text-sm text-center max-w-md">
        This project does not have a 3D model attached. The customer may have submitted without a room scan.
      </p>
    </div>
  )
}

export function PremiumModelViewer({
  glbUrl,
  usdzUrl,
  title = '3D Room Scan',
  description = 'Interactive 3D model - drag to rotate, scroll to zoom',
  className,
  showTitle = true,
  compact = false,
  onLoad,
  onError
}: PremiumModelViewerProps) {
  const containerRef = useRef<HTMLDivElement>(null)
  const controlsRef = useRef<ControlsRef>(null)

  const [isLoaded, setIsLoaded] = useState(false)
  const [loadProgress, setLoadProgress] = useState(0)
  const [error, setError] = useState<Error | null>(null)
  const [isFullscreen, setIsFullscreen] = useState(false)
  const [autoRotate, setAutoRotate] = useState(false)
  const [retryKey, setRetryKey] = useState(0)

  // Handle model load success
  const handleLoad = useCallback(() => {
    setLoadProgress(100)
    // Slight delay before showing model for smooth transition
    setTimeout(() => {
      setIsLoaded(true)
      onLoad?.()
    }, 300)
  }, [onLoad])

  // Handle model load error
  const handleError = useCallback((err: Error) => {
    console.error('Model loading error:', err)
    setError(err)
    onError?.(err)
  }, [onError])

  // Handle retry
  const handleRetry = useCallback(() => {
    setError(null)
    setIsLoaded(false)
    setLoadProgress(0)
    setRetryKey((k) => k + 1)
  }, [])

  // Fullscreen handling
  const toggleFullscreen = useCallback(async () => {
    if (!containerRef.current) return

    try {
      if (!isFullscreen) {
        await containerRef.current.requestFullscreen()
      } else {
        await document.exitFullscreen()
      }
    } catch (err) {
      console.error('Fullscreen error:', err)
    }
  }, [isFullscreen])

  // Listen for fullscreen changes
  useEffect(() => {
    const handleFullscreenChange = () => {
      setIsFullscreen(!!document.fullscreenElement)
    }
    document.addEventListener('fullscreenchange', handleFullscreenChange)
    return () => document.removeEventListener('fullscreenchange', handleFullscreenChange)
  }, [])

  // Keyboard shortcuts
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Ignore if typing in an input
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) {
        return
      }

      switch (e.key.toLowerCase()) {
        case 'r':
          controlsRef.current?.reset()
          break
        case 'f':
          toggleFullscreen()
          break
        case 'a':
          setAutoRotate((prev) => !prev)
          break
        case '+':
        case '=':
          controlsRef.current?.zoomIn()
          break
        case '-':
        case '_':
          controlsRef.current?.zoomOut()
          break
      }
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [toggleFullscreen])

  // Simulate loading progress
  useEffect(() => {
    if (!glbUrl || isLoaded || error) return

    const interval = setInterval(() => {
      setLoadProgress((prev) => {
        // Slowly progress to 90%, actual completion will set to 100
        if (prev >= 90) return prev
        return prev + Math.random() * 15
      })
    }, 200)

    return () => clearInterval(interval)
  }, [glbUrl, isLoaded, error])

  const viewerHeight = compact ? 'h-64' : 'h-[500px]'
  const downloadUrl = glbUrl || usdzUrl

  return (
    <Card className={cn('overflow-hidden', className)} ref={containerRef}>
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
          </div>
        </CardHeader>
      )}

      <CardContent className={showTitle ? 'pt-2' : 'p-0'}>
        <div
          className={cn(
            'relative w-full rounded-lg overflow-hidden',
            'bg-gradient-to-br from-slate-100 via-slate-50 to-slate-100',
            viewerHeight,
            isFullscreen && 'fixed inset-0 z-50 h-screen rounded-none'
          )}
        >
          {/* No URL provided */}
          {!glbUrl && !usdzUrl && <NoModelState />}

          {/* Error state */}
          {error && (
            <ErrorState
              error={error}
              downloadUrl={downloadUrl}
              onRetry={handleRetry}
            />
          )}

          {/* 3D Viewer */}
          {glbUrl && !error && (
            <>
              {/* Loading overlay */}
              <LoadingScreen
                progress={loadProgress}
                isLoaded={isLoaded}
              />

              {/* Toolbar */}
              <Toolbar
                autoRotate={autoRotate}
                onAutoRotateToggle={() => setAutoRotate(!autoRotate)}
                onZoomIn={() => controlsRef.current?.zoomIn()}
                onZoomOut={() => controlsRef.current?.zoomOut()}
                onReset={() => controlsRef.current?.reset()}
                onFullscreenToggle={toggleFullscreen}
                isFullscreen={isFullscreen}
                downloadUrl={downloadUrl}
                className="top-4 right-4"
              />

              {/* Interaction hint */}
              {isLoaded && (
                <div className="absolute bottom-4 left-1/2 -translate-x-1/2 z-10">
                  <InteractionHint />
                </div>
              )}

              {/* Three.js Canvas */}
              <Canvas
                key={retryKey}
                camera={{
                  position: [5, 3, 5],
                  fov: 50,
                  near: 0.1,
                  far: 1000
                }}
                shadows
                dpr={[1, 2]}
                gl={{
                  antialias: true,
                  alpha: true,
                  powerPreference: 'high-performance'
                }}
                style={{
                  background: 'transparent'
                }}
              >
                <Suspense fallback={null}>
                  <Scene
                    glbUrl={glbUrl}
                    onLoad={handleLoad}
                    onError={handleError}
                  />
                  <Controls
                    ref={controlsRef}
                    autoRotate={autoRotate}
                    autoRotateSpeed={1}
                  />
                </Suspense>
              </Canvas>
            </>
          )}
        </div>
      </CardContent>
    </Card>
  )
}

// Compact version for lists/grids
export function PremiumModelViewerCompact({
  glbUrl,
  usdzUrl,
  previewImageUrl,
  alt = '3D Room Scan',
  className,
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
  const hasModel = glbUrl || usdzUrl

  if (!hasModel) {
    return (
      <div
        className={cn(
          'relative h-32 w-full rounded-lg bg-slate-100 flex items-center justify-center',
          className
        )}
      >
        <Box className="h-8 w-8 text-slate-400" />
      </div>
    )
  }

  return (
    <div
      className={cn(
        'relative h-32 w-full rounded-lg overflow-hidden cursor-pointer group',
        className
      )}
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
        />
      ) : (
        <div className="w-full h-full bg-gradient-to-br from-blue-50 to-blue-100 flex items-center justify-center">
          <Box className="h-10 w-10 text-blue-400" />
        </div>
      )}

      {/* Hover overlay */}
      <div
        className={cn(
          'absolute inset-0 bg-black/50 flex items-center justify-center transition-opacity duration-200',
          isHovered ? 'opacity-100' : 'opacity-0'
        )}
      >
        <div className="flex items-center gap-2 text-white font-medium">
          <Box className="h-5 w-5" />
          View 3D Scan
        </div>
      </div>

      {/* 3D badge */}
      <div className="absolute top-2 right-2 bg-blue-600 text-white text-xs px-2 py-1 rounded-full font-medium shadow-sm">
        3D
      </div>
    </div>
  )
}
