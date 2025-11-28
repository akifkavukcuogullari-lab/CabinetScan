'use client'

import { useMemo } from 'react'
import { Box, Ruler, Home } from 'lucide-react'

interface FloorPlanThumbnailProps {
  measurements: any
  className?: string
  showStats?: boolean
  onClick?: () => void
}

export function FloorPlanThumbnail({
  measurements,
  className = '',
  showStats = true,
  onClick
}: FloorPlanThumbnailProps) {
  // Generate SVG floor plan thumbnail
  const svgContent = useMemo(() => {
    if (!measurements || !measurements.room) {
      return null
    }

    const {
      room,
      walls = [],
      doors = [],
      windows = [],
      cabinets = { upper: [], lower: [] },
      appliances = [],
      countertops = []
    } = measurements

    // Calculate bounds
    const roomWidth = room.max_x - room.min_x
    const roomDepth = room.max_z - room.min_z

    if (roomWidth <= 0 || roomDepth <= 0) {
      return null
    }

    // Viewport for thumbnail
    const viewportWidth = 200
    const viewportHeight = 150
    const padding = 20

    const scaleX = (viewportWidth - padding * 2) / roomWidth
    const scaleZ = (viewportHeight - padding * 2) / roomDepth
    const scale = Math.min(scaleX, scaleZ)

    // Transform coordinates
    const toSVG = (x: number, z: number) => ({
      x: (x - room.min_x) * scale + padding,
      y: (z - room.min_z) * scale + padding
    })

    return (
      <svg
        viewBox={`0 0 ${viewportWidth} ${viewportHeight}`}
        className="w-full h-full"
        style={{ backgroundColor: '#f8fafc' }}
      >
        {/* Background grid pattern */}
        <defs>
          <pattern id="grid-thumb" width="10" height="10" patternUnits="userSpaceOnUse">
            <path d="M 10 0 L 0 0 0 10" fill="none" stroke="#e2e8f0" strokeWidth="0.5" />
          </pattern>
        </defs>
        <rect width="100%" height="100%" fill="url(#grid-thumb)" />

        {/* Walls */}
        {walls.map((wall: any, index: number) => {
          const start = toSVG(wall.start.x, wall.start.z)
          const end = toSVG(wall.end.x, wall.end.z)
          return (
            <line
              key={`wall-${index}`}
              x1={start.x}
              y1={start.y}
              x2={end.x}
              y2={end.y}
              stroke="#374151"
              strokeWidth="3"
              strokeLinecap="round"
            />
          )
        })}

        {/* Doors */}
        {doors.map((door: any, index: number) => {
          const pos = toSVG(door.position.x, door.position.z)
          const doorWidth = Math.max(door.width_ft * scale, 8)
          return (
            <g key={`door-${index}`}>
              <rect
                x={pos.x - doorWidth / 2}
                y={pos.y - 2}
                width={doorWidth}
                height={4}
                fill="#f8fafc"
                stroke="#60a5fa"
                strokeWidth="1.5"
              />
            </g>
          )
        })}

        {/* Windows */}
        {windows.map((window: any, index: number) => {
          const pos = toSVG(window.position.x, window.position.z)
          const windowWidth = Math.max(window.width_ft * scale, 8)
          return (
            <rect
              key={`window-${index}`}
              x={pos.x - windowWidth / 2}
              y={pos.y - 2}
              width={windowWidth}
              height={4}
              fill="#93c5fd"
              stroke="#3b82f6"
              strokeWidth="1"
            />
          )
        })}

        {/* Lower Cabinets */}
        {cabinets.lower?.map((cabinet: any, index: number) => {
          const pos = toSVG(cabinet.position.x, cabinet.position.z)
          const width = Math.max(cabinet.width_ft * scale, 6)
          const depth = Math.max(cabinet.depth_ft * scale, 4)
          return (
            <rect
              key={`lower-${index}`}
              x={pos.x - width / 2}
              y={pos.y - depth / 2}
              width={width}
              height={depth}
              fill="#e5e7eb"
              stroke="#6b7280"
              strokeWidth="1"
            />
          )
        })}

        {/* Upper Cabinets */}
        {cabinets.upper?.map((cabinet: any, index: number) => {
          const pos = toSVG(cabinet.position.x, cabinet.position.z)
          const width = Math.max(cabinet.width_ft * scale, 6)
          const depth = Math.max(cabinet.depth_ft * scale, 4)
          return (
            <rect
              key={`upper-${index}`}
              x={pos.x - width / 2}
              y={pos.y - depth / 2}
              width={width}
              height={depth}
              fill="none"
              stroke="#9ca3af"
              strokeWidth="1"
              strokeDasharray="2"
            />
          )
        })}

        {/* Countertops */}
        {countertops.map((countertop: any, index: number) => {
          const pos = toSVG(countertop.position.x, countertop.position.z)
          const width = Math.max(countertop.width_ft * scale, 6)
          const depth = Math.max(countertop.depth_ft * scale, 4)
          return (
            <rect
              key={`ct-${index}`}
              x={pos.x - width / 2}
              y={pos.y - depth / 2}
              width={width}
              height={depth}
              fill="#6ee7b7"
              stroke="#10b981"
              strokeWidth="1"
              opacity="0.6"
            />
          )
        })}

        {/* Appliances */}
        {appliances.map((appliance: any, index: number) => {
          const pos = toSVG(appliance.position.x, appliance.position.z)
          const width = Math.max(appliance.width_ft * scale, 6)
          const depth = Math.max(appliance.depth_ft * scale, 4)
          return (
            <rect
              key={`app-${index}`}
              x={pos.x - width / 2}
              y={pos.y - depth / 2}
              width={width}
              height={depth}
              fill="#fca5a5"
              stroke="#dc2626"
              strokeWidth="1"
            />
          )
        })}
      </svg>
    )
  }, [measurements])

  // Calculate stats
  const stats = useMemo(() => {
    if (!measurements?.room) return null

    const roomWidth = measurements.room.max_x - measurements.room.min_x
    const roomDepth = measurements.room.max_z - measurements.room.min_z
    const wallCount = measurements.walls?.length || 0
    const doorCount = measurements.doors?.length || 0
    const cabinetCount = (measurements.cabinets?.upper?.length || 0) + (measurements.cabinets?.lower?.length || 0)

    return {
      dimensions: `${roomWidth.toFixed(0)}' x ${roomDepth.toFixed(0)}'`,
      walls: wallCount,
      doors: doorCount,
      cabinets: cabinetCount
    }
  }, [measurements])

  // Empty/invalid state
  if (!svgContent) {
    return (
      <div
        className={`relative h-28 w-full rounded-lg bg-gradient-to-br from-gray-50 to-gray-100 border border-gray-200 flex flex-col items-center justify-center cursor-pointer hover:bg-gray-100 transition-colors ${className}`}
        onClick={onClick}
      >
        <Home className="h-8 w-8 text-gray-300 mb-1" />
        <span className="text-xs text-gray-400">No floor plan data</span>
      </div>
    )
  }

  return (
    <div
      className={`relative rounded-lg overflow-hidden border border-gray-200 cursor-pointer group hover:border-blue-400 transition-all hover:shadow-md ${className}`}
      onClick={onClick}
    >
      {/* Floor plan SVG */}
      <div className="h-28 w-full">
        {svgContent}
      </div>

      {/* Stats overlay */}
      {showStats && stats && (
        <div className="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/70 to-transparent p-2">
          <div className="flex items-center gap-3 text-white text-xs">
            <span className="flex items-center gap-1">
              <Ruler className="h-3 w-3" />
              {stats.dimensions}
            </span>
            {stats.cabinets > 0 && (
              <span className="flex items-center gap-1">
                <Box className="h-3 w-3" />
                {stats.cabinets} cabinets
              </span>
            )}
          </div>
        </div>
      )}

      {/* Hover effect */}
      <div className="absolute inset-0 bg-blue-600/0 group-hover:bg-blue-600/10 transition-colors pointer-events-none" />

      {/* Floor plan badge */}
      <div className="absolute top-2 right-2 bg-white/90 text-gray-600 text-xs px-1.5 py-0.5 rounded font-medium shadow-sm">
        2D
      </div>
    </div>
  )
}
