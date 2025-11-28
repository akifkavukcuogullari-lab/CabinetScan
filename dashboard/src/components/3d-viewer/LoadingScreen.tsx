'use client'

import { useEffect, useState } from 'react'
import { cn } from '@/lib/utils'

interface LoadingScreenProps {
  progress?: number
  isLoaded?: boolean
  className?: string
}

export function LoadingScreen({
  progress = 0,
  isLoaded = false,
  className
}: LoadingScreenProps) {
  const [fadeOut, setFadeOut] = useState(false)
  const [hidden, setHidden] = useState(false)

  useEffect(() => {
    if (isLoaded) {
      // Start fade out animation
      setFadeOut(true)
      // Remove from DOM after animation
      const timer = setTimeout(() => setHidden(true), 500)
      return () => clearTimeout(timer)
    }
  }, [isLoaded])

  if (hidden) return null

  return (
    <div
      className={cn(
        'absolute inset-0 z-20 flex flex-col items-center justify-center',
        'bg-gradient-to-br from-slate-50 via-white to-slate-100',
        'transition-opacity duration-500 ease-out',
        fadeOut ? 'opacity-0 pointer-events-none' : 'opacity-100',
        className
      )}
    >
      {/* Animated 3D cube loader */}
      <div className="relative mb-8">
        <div className="cube-loader">
          <div className="cube-face cube-front" />
          <div className="cube-face cube-back" />
          <div className="cube-face cube-right" />
          <div className="cube-face cube-left" />
          <div className="cube-face cube-top" />
          <div className="cube-face cube-bottom" />
        </div>
      </div>

      {/* Loading text */}
      <div className="text-center space-y-3">
        <h3 className="text-lg font-semibold text-slate-700">
          Loading 3D Model
        </h3>
        <p className="text-sm text-slate-500">
          Preparing your interactive room scan...
        </p>
      </div>

      {/* Progress bar */}
      <div className="mt-6 w-48">
        <div className="h-1.5 bg-slate-200 rounded-full overflow-hidden">
          <div
            className="h-full bg-gradient-to-r from-blue-500 to-blue-600 rounded-full transition-all duration-300 ease-out"
            style={{ width: `${Math.max(5, progress)}%` }}
          />
        </div>
        <p className="text-xs text-slate-400 text-center mt-2">
          {progress > 0 ? `${Math.round(progress)}%` : 'Initializing...'}
        </p>
      </div>

      {/* CSS for cube animation */}
      <style jsx>{`
        .cube-loader {
          width: 40px;
          height: 40px;
          position: relative;
          transform-style: preserve-3d;
          animation: cubeRotate 2s infinite ease-in-out;
        }

        .cube-face {
          position: absolute;
          width: 40px;
          height: 40px;
          border: 2px solid rgba(59, 130, 246, 0.3);
          background: linear-gradient(135deg, rgba(59, 130, 246, 0.1) 0%, rgba(59, 130, 246, 0.05) 100%);
          backdrop-filter: blur(2px);
        }

        .cube-front {
          transform: translateZ(20px);
          border-color: rgba(59, 130, 246, 0.5);
          background: linear-gradient(135deg, rgba(59, 130, 246, 0.2) 0%, rgba(59, 130, 246, 0.1) 100%);
        }

        .cube-back {
          transform: translateZ(-20px) rotateY(180deg);
        }

        .cube-right {
          transform: translateX(20px) rotateY(90deg);
        }

        .cube-left {
          transform: translateX(-20px) rotateY(-90deg);
        }

        .cube-top {
          transform: translateY(-20px) rotateX(90deg);
          border-color: rgba(59, 130, 246, 0.4);
        }

        .cube-bottom {
          transform: translateY(20px) rotateX(-90deg);
        }

        @keyframes cubeRotate {
          0% {
            transform: rotateX(-20deg) rotateY(0deg);
          }
          50% {
            transform: rotateX(-20deg) rotateY(180deg);
          }
          100% {
            transform: rotateX(-20deg) rotateY(360deg);
          }
        }
      `}</style>
    </div>
  )
}
