'use client'

import { useState, useEffect } from 'react'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import {
  ZoomIn,
  ZoomOut,
  RotateCcw,
  Maximize2,
  Minimize2,
  RotateCw,
  Download,
  HelpCircle,
  X
} from 'lucide-react'

interface ToolbarProps {
  autoRotate: boolean
  onAutoRotateToggle: () => void
  onZoomIn: () => void
  onZoomOut: () => void
  onReset: () => void
  onFullscreenToggle: () => void
  isFullscreen: boolean
  downloadUrl?: string
  className?: string
}

export function Toolbar({
  autoRotate,
  onAutoRotateToggle,
  onZoomIn,
  onZoomOut,
  onReset,
  onFullscreenToggle,
  isFullscreen,
  downloadUrl,
  className
}: ToolbarProps) {
  const [showHelp, setShowHelp] = useState(false)
  const [hasSeenHelp, setHasSeenHelp] = useState(false)

  // Show help tooltip on first load
  useEffect(() => {
    const hasSeenKey = 'premium-viewer-help-seen'
    const hasSeen = localStorage.getItem(hasSeenKey)

    if (!hasSeen) {
      const timer = setTimeout(() => {
        setShowHelp(true)
        // Auto-hide after 5 seconds
        setTimeout(() => {
          setShowHelp(false)
          setHasSeenHelp(true)
          localStorage.setItem(hasSeenKey, 'true')
        }, 5000)
      }, 1500)

      return () => clearTimeout(timer)
    } else {
      setHasSeenHelp(true)
    }
  }, [])

  return (
    <div className={cn('absolute z-10', className)}>
      {/* Main toolbar */}
      <div className="flex items-center gap-1 bg-white/95 backdrop-blur-sm rounded-lg shadow-lg border border-slate-200 p-1">
        {/* Zoom controls */}
        <div className="flex items-center">
          <Button
            variant="ghost"
            size="icon-sm"
            onClick={onZoomIn}
            title="Zoom in (+)"
            className="h-8 w-8 hover:bg-slate-100"
          >
            <ZoomIn className="h-4 w-4" />
          </Button>
          <Button
            variant="ghost"
            size="icon-sm"
            onClick={onZoomOut}
            title="Zoom out (-)"
            className="h-8 w-8 hover:bg-slate-100"
          >
            <ZoomOut className="h-4 w-4" />
          </Button>
        </div>

        <div className="w-px h-6 bg-slate-200" />

        {/* Camera controls */}
        <div className="flex items-center">
          <Button
            variant="ghost"
            size="icon-sm"
            onClick={onReset}
            title="Reset view (R)"
            className="h-8 w-8 hover:bg-slate-100"
          >
            <RotateCcw className="h-4 w-4" />
          </Button>
          <Button
            variant={autoRotate ? 'default' : 'ghost'}
            size="icon-sm"
            onClick={onAutoRotateToggle}
            title="Toggle auto-rotate (A)"
            className={cn(
              'h-8 w-8',
              autoRotate
                ? 'bg-blue-600 hover:bg-blue-700 text-white'
                : 'hover:bg-slate-100'
            )}
          >
            <RotateCw className={cn('h-4 w-4', autoRotate && 'animate-spin-slow')} />
          </Button>
        </div>

        <div className="w-px h-6 bg-slate-200" />

        {/* View controls */}
        <div className="flex items-center">
          <Button
            variant="ghost"
            size="icon-sm"
            onClick={onFullscreenToggle}
            title={isFullscreen ? 'Exit fullscreen (F)' : 'Enter fullscreen (F)'}
            className="h-8 w-8 hover:bg-slate-100"
          >
            {isFullscreen ? (
              <Minimize2 className="h-4 w-4" />
            ) : (
              <Maximize2 className="h-4 w-4" />
            )}
          </Button>

          {/* Download button */}
          {downloadUrl && (
            <a href={downloadUrl} download>
              <Button
                variant="ghost"
                size="icon-sm"
                title="Download 3D model"
                className="h-8 w-8 hover:bg-slate-100"
              >
                <Download className="h-4 w-4" />
              </Button>
            </a>
          )}
        </div>

        <div className="w-px h-6 bg-slate-200" />

        {/* Help */}
        <Button
          variant="ghost"
          size="icon-sm"
          onClick={() => setShowHelp(!showHelp)}
          title="Show help"
          className={cn(
            'h-8 w-8',
            showHelp ? 'bg-slate-100' : 'hover:bg-slate-100'
          )}
        >
          <HelpCircle className="h-4 w-4" />
        </Button>
      </div>

      {/* Help tooltip */}
      {showHelp && (
        <div className="absolute top-12 right-0 w-72 bg-white/95 backdrop-blur-sm rounded-lg shadow-xl border border-slate-200 p-4">
          <div className="flex items-start justify-between mb-3">
            <h4 className="font-semibold text-slate-900">Navigation Controls</h4>
            <button
              onClick={() => setShowHelp(false)}
              className="p-1 hover:bg-slate-100 rounded-full -mr-1 -mt-1"
            >
              <X className="h-4 w-4 text-slate-500" />
            </button>
          </div>

          <div className="space-y-2 text-sm">
            <div className="flex items-center gap-3">
              <div className="w-20 shrink-0">
                <span className="px-2 py-0.5 bg-slate-100 rounded text-xs font-mono">
                  Left drag
                </span>
              </div>
              <span className="text-slate-600">Rotate view</span>
            </div>
            <div className="flex items-center gap-3">
              <div className="w-20 shrink-0">
                <span className="px-2 py-0.5 bg-slate-100 rounded text-xs font-mono">
                  Right drag
                </span>
              </div>
              <span className="text-slate-600">Pan view</span>
            </div>
            <div className="flex items-center gap-3">
              <div className="w-20 shrink-0">
                <span className="px-2 py-0.5 bg-slate-100 rounded text-xs font-mono">
                  Scroll
                </span>
              </div>
              <span className="text-slate-600">Zoom in/out</span>
            </div>

            <div className="pt-2 border-t border-slate-200 mt-3">
              <p className="text-xs text-slate-500 font-medium mb-2">Keyboard shortcuts:</p>
              <div className="grid grid-cols-2 gap-1 text-xs">
                <div>
                  <kbd className="px-1.5 py-0.5 bg-slate-100 rounded font-mono">R</kbd>
                  <span className="ml-2 text-slate-600">Reset</span>
                </div>
                <div>
                  <kbd className="px-1.5 py-0.5 bg-slate-100 rounded font-mono">F</kbd>
                  <span className="ml-2 text-slate-600">Fullscreen</span>
                </div>
                <div>
                  <kbd className="px-1.5 py-0.5 bg-slate-100 rounded font-mono">A</kbd>
                  <span className="ml-2 text-slate-600">Auto-rotate</span>
                </div>
                <div>
                  <kbd className="px-1.5 py-0.5 bg-slate-100 rounded font-mono">+/-</kbd>
                  <span className="ml-2 text-slate-600">Zoom</span>
                </div>
              </div>
            </div>
          </div>

          {/* First-time indicator */}
          {!hasSeenHelp && (
            <div className="absolute -top-1 right-4 w-2 h-2 bg-blue-500 rounded-full animate-ping" />
          )}
        </div>
      )}

      {/* Slow spin animation for auto-rotate icon */}
      <style jsx global>{`
        @keyframes spin-slow {
          from {
            transform: rotate(0deg);
          }
          to {
            transform: rotate(360deg);
          }
        }
        .animate-spin-slow {
          animation: spin-slow 3s linear infinite;
        }
      `}</style>
    </div>
  )
}

// Interaction hint that appears at bottom of viewer
export function InteractionHint({ className }: { className?: string }) {
  const [visible, setVisible] = useState(true)

  useEffect(() => {
    const timer = setTimeout(() => setVisible(false), 8000)
    return () => clearTimeout(timer)
  }, [])

  if (!visible) return null

  return (
    <div
      className={cn(
        'flex items-center gap-2 px-3 py-1.5 bg-black/60 backdrop-blur-sm text-white text-xs rounded-full',
        'transition-opacity duration-500',
        className
      )}
    >
      <span className="inline-flex gap-1">
        <span className="opacity-80">Drag to rotate</span>
        <span className="opacity-40">|</span>
        <span className="opacity-80">Scroll to zoom</span>
        <span className="opacity-40">|</span>
        <span className="opacity-80">Right-drag to pan</span>
      </span>
    </div>
  )
}
