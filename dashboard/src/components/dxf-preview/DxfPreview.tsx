'use client'

import { useState, useMemo, useRef, useEffect } from 'react'
import { Button } from '@/components/ui/button'
import { Checkbox } from '@/components/ui/checkbox'
import {
  RotateCcw,
  ZoomIn,
  ZoomOut,
  Maximize2,
  Minimize2,
  Layers,
  ChevronLeft,
  ChevronRight
} from 'lucide-react'

// Types matching InteractiveFloorPlan
interface Position {
  x: number
  z: number
  y?: number
}

interface WallData {
  id: string
  position: Position
  start: Position
  end: Position
  width_ft: number
  height_ft: number
  thickness_ft: number
  linear_ft: number
}

interface CabinetData {
  id: string
  type: string
  position: Position
  width_ft: number
  height_ft: number
  depth_ft: number
  corners?: Position[]
}

interface ApplianceData {
  id: string
  type: string
  position: Position
  width_ft: number
  height_ft: number
  depth_ft: number
  corners?: Position[]
}

interface DoorData {
  id: string
  position: Position
  width_ft: number
  height_ft: number
}

interface WindowData {
  id: string
  position: Position
  width_ft: number
  height_ft: number
}

interface RoomBounds {
  min_x: number
  max_x: number
  min_z: number
  max_z: number
  ceiling_height_ft: number
}

interface MeasurementsData {
  room?: RoomBounds
  walls?: WallData[]
  cabinets?: {
    upper?: CabinetData[]
    lower?: CabinetData[]
  }
  appliances?: ApplianceData[]
  doors?: DoorData[]
  windows?: WindowData[]
  countertop_summary?: {
    total_area_sqft: number
  }
}

interface DxfPreviewProps {
  measurements: MeasurementsData | null | undefined
  className?: string
  isLoading?: boolean
}

// CAD-style layer colors
const LAYER_COLORS = {
  WALLS: '#e5e7eb',        // White/Gray
  CABINETS_LOWER: '#06b6d4', // Cyan
  CABINETS_UPPER: '#d946ef', // Magenta
  APPLIANCES: '#ef4444',    // Red
  DOORS: '#22c55e',         // Green
  WINDOWS: '#3b82f6',       // Blue
  COUNTERTOPS: '#eab308',   // Yellow
  GRID: '#374151',          // Dark gray
  TEXT: '#9ca3af'           // Light gray
}

type LayerKey = keyof typeof LAYER_COLORS

interface LayerVisibility {
  WALLS: boolean
  CABINETS_LOWER: boolean
  CABINETS_UPPER: boolean
  APPLIANCES: boolean
  DOORS: boolean
  WINDOWS: boolean
}

export function DxfPreview({
  measurements,
  className = '',
  isLoading = false
}: DxfPreviewProps) {
  const containerRef = useRef<HTMLDivElement>(null)
  const [zoom, setZoom] = useState(1)
  const [panOffset, setPanOffset] = useState({ x: 0, y: 0 })
  const [isFullscreen, setIsFullscreen] = useState(false)
  const [isPanning, setIsPanning] = useState(false)
  const [lastPanPoint, setLastPanPoint] = useState({ x: 0, y: 0 })
  const [showLayerPanel, setShowLayerPanel] = useState(true)
  const [mouseCoords, setMouseCoords] = useState({ x: 0, y: 0 })
  const [layerVisibility, setLayerVisibility] = useState<LayerVisibility>({
    WALLS: true,
    CABINETS_LOWER: true,
    CABINETS_UPPER: true,
    APPLIANCES: true,
    DOORS: true,
    WINDOWS: true
  })

  // Calculate dominant angle from walls to auto-straighten the view
  const dominantAngle = useMemo(() => {
    if (!measurements?.walls || measurements.walls.length === 0) return 0

    // Find the longest wall and calculate its angle
    let longestWall: WallData | null = null
    let maxLength = 0

    for (const wall of measurements.walls) {
      if (wall.linear_ft > maxLength) {
        maxLength = wall.linear_ft
        longestWall = wall
      }
    }

    if (!longestWall) return 0

    // Calculate angle of longest wall
    const dx = longestWall.end.x - longestWall.start.x
    const dz = longestWall.end.z - longestWall.start.z
    let angle = Math.atan2(dz, dx) * (180 / Math.PI)

    // Snap to nearest 90 degree increment
    const snapped = Math.round(angle / 90) * 90
    return snapped - angle
  }, [measurements])

  // Calculate bounds and scale
  const { viewBox, scale, roomWidth, roomDepth, centerX, centerY } = useMemo(() => {
    if (!measurements?.room) {
      return { viewBox: '0 0 400 300', scale: 1, roomWidth: 0, roomDepth: 0, centerX: 0, centerY: 0 }
    }

    const room = measurements.room
    const roomW = (room.max_x - room.min_x) || 20
    const roomD = (room.max_z - room.min_z) || 15
    const margin = 3 // Feet of margin

    const minX = room.min_x - margin
    const minZ = room.min_z - margin
    const width = roomW + margin * 2
    const height = roomD + margin * 2

    // Calculate center for rotation
    const cX = (room.min_x + room.max_x) / 2
    const cY = (room.min_z + room.max_z) / 2

    // Scale to fit in a reasonable viewBox while maintaining aspect ratio
    const targetWidth = 800
    const targetHeight = 600
    const scaleX = targetWidth / width
    const scaleY = targetHeight / height
    const s = Math.min(scaleX, scaleY)

    return {
      viewBox: `${minX * s} ${minZ * s} ${width * s} ${height * s}`,
      scale: s,
      roomWidth: roomW,
      roomDepth: roomD,
      centerX: cX * s,
      centerY: cY * s
    }
  }, [measurements])

  // Handle zoom
  const handleZoom = (delta: number) => {
    setZoom(prev => Math.max(0.5, Math.min(3, prev + delta)))
  }

  // Reset view
  const resetView = () => {
    setZoom(1)
    setPanOffset({ x: 0, y: 0 })
  }

  // Toggle fullscreen
  const toggleFullscreen = async () => {
    if (!containerRef.current) return

    if (!isFullscreen) {
      try {
        await containerRef.current.requestFullscreen()
        setIsFullscreen(true)
      } catch {
        console.error('Fullscreen not supported')
      }
    } else {
      try {
        await document.exitFullscreen()
        setIsFullscreen(false)
      } catch {
        console.error('Error exiting fullscreen')
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

  // Pan handling
  const handleMouseDown = (e: React.MouseEvent) => {
    if (e.button === 0) { // Left click
      setIsPanning(true)
      setLastPanPoint({ x: e.clientX, y: e.clientY })
    }
  }

  const handleMouseMove = (e: React.MouseEvent) => {
    // Update coordinates display
    if (measurements?.room) {
      const rect = e.currentTarget.getBoundingClientRect()
      const x = ((e.clientX - rect.left) / rect.width) * roomWidth
      const y = ((e.clientY - rect.top) / rect.height) * roomDepth
      setMouseCoords({ x, y })
    }

    if (isPanning) {
      const dx = e.clientX - lastPanPoint.x
      const dy = e.clientY - lastPanPoint.y
      setPanOffset(prev => ({ x: prev.x + dx, y: prev.y + dy }))
      setLastPanPoint({ x: e.clientX, y: e.clientY })
    }
  }

  const handleMouseUp = () => {
    setIsPanning(false)
  }

  // Wheel zoom
  const handleWheel = (e: React.WheelEvent) => {
    e.preventDefault()
    const delta = e.deltaY > 0 ? -0.1 : 0.1
    handleZoom(delta)
  }

  // Toggle layer visibility
  const toggleLayer = (layer: keyof LayerVisibility) => {
    setLayerVisibility(prev => ({ ...prev, [layer]: !prev[layer] }))
  }

  // Count entities in each layer
  const layerCounts = useMemo(() => ({
    WALLS: measurements?.walls?.length || 0,
    CABINETS_LOWER: measurements?.cabinets?.lower?.length || 0,
    CABINETS_UPPER: measurements?.cabinets?.upper?.length || 0,
    APPLIANCES: measurements?.appliances?.length || 0,
    DOORS: measurements?.doors?.length || 0,
    WINDOWS: measurements?.windows?.length || 0
  }), [measurements])

  if (!measurements || isLoading) {
    return (
      <div className={`relative ${className}`}>
        <div className="h-[60vh] min-h-[400px] bg-gray-900 rounded-lg flex items-center justify-center">
          {isLoading ? (
            <div className="text-center">
              <div className="w-8 h-8 border-2 border-cyan-500 border-t-transparent rounded-full animate-spin mx-auto mb-2" />
              <p className="text-gray-400 text-sm">Loading CAD preview...</p>
            </div>
          ) : (
            <div className="text-center">
              <Layers className="h-12 w-12 text-gray-600 mx-auto mb-3" />
              <p className="text-gray-400 text-sm">No measurements available</p>
            </div>
          )}
        </div>
      </div>
    )
  }

  return (
    <div className={`relative ${className}`} ref={containerRef}>
      {/* Main CAD viewer */}
      <div
        className={`relative ${isFullscreen ? 'h-screen' : 'h-[60vh] min-h-[400px]'} bg-gray-900 rounded-lg overflow-hidden`}
        onMouseDown={handleMouseDown}
        onMouseMove={handleMouseMove}
        onMouseUp={handleMouseUp}
        onMouseLeave={handleMouseUp}
        onWheel={handleWheel}
        style={{ cursor: isPanning ? 'grabbing' : 'crosshair' }}
      >
        {/* Layer panel toggle */}
        <Button
          variant="ghost"
          size="icon"
          className="absolute top-3 left-3 z-30 h-8 w-8 bg-gray-800/90 hover:bg-gray-700 text-gray-300"
          onClick={() => setShowLayerPanel(!showLayerPanel)}
        >
          {showLayerPanel ? <ChevronLeft className="h-4 w-4" /> : <Layers className="h-4 w-4" />}
        </Button>

        {/* Layer panel */}
        {showLayerPanel && (
          <div className="absolute top-12 left-3 z-20 w-44 bg-gray-800/95 backdrop-blur-sm rounded-lg border border-gray-700 p-3">
            <div className="text-xs font-medium text-gray-400 mb-2 uppercase tracking-wider">Layers</div>
            <div className="space-y-1.5">
              {(Object.keys(layerVisibility) as Array<keyof LayerVisibility>).map(layer => (
                <label
                  key={layer}
                  className="flex items-center gap-2 cursor-pointer hover:bg-gray-700/50 rounded px-1.5 py-1 -mx-1.5"
                >
                  <Checkbox
                    checked={layerVisibility[layer]}
                    onCheckedChange={() => toggleLayer(layer)}
                    className="h-3.5 w-3.5 border-gray-600 data-[state=checked]:bg-transparent data-[state=checked]:border-gray-500"
                  />
                  <div
                    className="w-3 h-0.5 rounded-full"
                    style={{ backgroundColor: LAYER_COLORS[layer as LayerKey] }}
                  />
                  <span className="text-xs text-gray-300 flex-1">{layer.replace('_', ' ')}</span>
                  <span className="text-xs text-gray-500">{layerCounts[layer]}</span>
                </label>
              ))}
            </div>
          </div>
        )}

        {/* Floating controls */}
        <div className="absolute top-3 right-3 z-20 flex gap-1 bg-gray-800/90 backdrop-blur-sm rounded-full px-2 py-1">
          <Button
            variant="ghost"
            size="icon"
            className="h-8 w-8 text-gray-300 hover:text-white hover:bg-gray-700"
            onClick={resetView}
            title="Reset view"
          >
            <RotateCcw className="h-4 w-4" />
          </Button>
          <Button
            variant="ghost"
            size="icon"
            className="h-8 w-8 text-gray-300 hover:text-white hover:bg-gray-700"
            onClick={() => handleZoom(0.2)}
            title="Zoom in"
          >
            <ZoomIn className="h-4 w-4" />
          </Button>
          <Button
            variant="ghost"
            size="icon"
            className="h-8 w-8 text-gray-300 hover:text-white hover:bg-gray-700"
            onClick={() => handleZoom(-0.2)}
            title="Zoom out"
          >
            <ZoomOut className="h-4 w-4" />
          </Button>
          <Button
            variant="ghost"
            size="icon"
            className="h-8 w-8 text-gray-300 hover:text-white hover:bg-gray-700"
            onClick={toggleFullscreen}
            title={isFullscreen ? 'Exit fullscreen' : 'Enter fullscreen'}
          >
            {isFullscreen ? <Minimize2 className="h-4 w-4" /> : <Maximize2 className="h-4 w-4" />}
          </Button>
        </div>

        {/* SVG Canvas */}
        <svg
          viewBox={viewBox}
          className="w-full h-full"
          style={{
            transform: `scale(${zoom}) translate(${panOffset.x / zoom}px, ${panOffset.y / zoom}px)`,
            transformOrigin: 'center center'
          }}
        >
          {/* Grid */}
          <defs>
            <pattern
              id="dxf-grid"
              width={scale}
              height={scale}
              patternUnits="userSpaceOnUse"
            >
              <path
                d={`M ${scale} 0 L 0 0 0 ${scale}`}
                fill="none"
                stroke={LAYER_COLORS.GRID}
                strokeWidth="0.5"
                opacity="0.3"
              />
            </pattern>
            <pattern
              id="dxf-grid-major"
              width={scale * 5}
              height={scale * 5}
              patternUnits="userSpaceOnUse"
            >
              <path
                d={`M ${scale * 5} 0 L 0 0 0 ${scale * 5}`}
                fill="none"
                stroke={LAYER_COLORS.GRID}
                strokeWidth="1"
                opacity="0.5"
              />
            </pattern>
          </defs>

          {/* Background grid (not rotated) */}
          <rect
            x={measurements.room ? (measurements.room.min_x - 10) * scale : 0}
            y={measurements.room ? (measurements.room.min_z - 10) * scale : 0}
            width={measurements.room ? (roomWidth + 20) * scale : 800}
            height={measurements.room ? (roomDepth + 20) * scale : 600}
            fill="url(#dxf-grid)"
          />
          <rect
            x={measurements.room ? (measurements.room.min_x - 10) * scale : 0}
            y={measurements.room ? (measurements.room.min_z - 10) * scale : 0}
            width={measurements.room ? (roomWidth + 20) * scale : 800}
            height={measurements.room ? (roomDepth + 20) * scale : 600}
            fill="url(#dxf-grid-major)"
          />

          {/* Rotated content group - auto-straightens the floor plan */}
          <g transform={`rotate(${dominantAngle} ${centerX} ${centerY})`}>
          {/* Walls */}
          {layerVisibility.WALLS && measurements.walls?.map(wall => (
            <line
              key={wall.id}
              x1={wall.start.x * scale}
              y1={wall.start.z * scale}
              x2={wall.end.x * scale}
              y2={wall.end.z * scale}
              stroke={LAYER_COLORS.WALLS}
              strokeWidth={Math.max(2, wall.thickness_ft * scale * 0.5)}
              strokeLinecap="round"
            />
          ))}

          {/* Lower Cabinets */}
          {layerVisibility.CABINETS_LOWER && measurements.cabinets?.lower?.map(cabinet => {
            if (cabinet.corners && cabinet.corners.length >= 3) {
              const points = cabinet.corners.map(c => `${c.x * scale},${c.z * scale}`).join(' ')
              return (
                <polygon
                  key={cabinet.id}
                  points={points}
                  fill={LAYER_COLORS.CABINETS_LOWER}
                  fillOpacity="0.2"
                  stroke={LAYER_COLORS.CABINETS_LOWER}
                  strokeWidth="1.5"
                />
              )
            }
            // Fallback to rectangle
            const x = (cabinet.position.x - cabinet.width_ft / 2) * scale
            const y = (cabinet.position.z - cabinet.depth_ft / 2) * scale
            const width = cabinet.width_ft * scale
            const height = cabinet.depth_ft * scale
            return (
              <rect
                key={cabinet.id}
                x={x}
                y={y}
                width={width}
                height={height}
                fill={LAYER_COLORS.CABINETS_LOWER}
                fillOpacity="0.2"
                stroke={LAYER_COLORS.CABINETS_LOWER}
                strokeWidth="1.5"
              />
            )
          })}

          {/* Upper Cabinets (dashed) */}
          {layerVisibility.CABINETS_UPPER && measurements.cabinets?.upper?.map(cabinet => {
            if (cabinet.corners && cabinet.corners.length >= 3) {
              const points = cabinet.corners.map(c => `${c.x * scale},${c.z * scale}`).join(' ')
              return (
                <polygon
                  key={cabinet.id}
                  points={points}
                  fill={LAYER_COLORS.CABINETS_UPPER}
                  fillOpacity="0.15"
                  stroke={LAYER_COLORS.CABINETS_UPPER}
                  strokeWidth="1.5"
                  strokeDasharray="8 4"
                />
              )
            }
            const x = (cabinet.position.x - cabinet.width_ft / 2) * scale
            const y = (cabinet.position.z - cabinet.depth_ft / 2) * scale
            const width = cabinet.width_ft * scale
            const height = cabinet.depth_ft * scale
            return (
              <rect
                key={cabinet.id}
                x={x}
                y={y}
                width={width}
                height={height}
                fill={LAYER_COLORS.CABINETS_UPPER}
                fillOpacity="0.15"
                stroke={LAYER_COLORS.CABINETS_UPPER}
                strokeWidth="1.5"
                strokeDasharray="8 4"
              />
            )
          })}

          {/* Appliances */}
          {layerVisibility.APPLIANCES && measurements.appliances?.map(appliance => {
            if (appliance.corners && appliance.corners.length >= 3) {
              const points = appliance.corners.map(c => `${c.x * scale},${c.z * scale}`).join(' ')
              return (
                <polygon
                  key={appliance.id}
                  points={points}
                  fill={LAYER_COLORS.APPLIANCES}
                  fillOpacity="0.2"
                  stroke={LAYER_COLORS.APPLIANCES}
                  strokeWidth="1.5"
                />
              )
            }
            const x = (appliance.position.x - appliance.width_ft / 2) * scale
            const y = (appliance.position.z - appliance.depth_ft / 2) * scale
            const width = appliance.width_ft * scale
            const height = appliance.depth_ft * scale
            return (
              <rect
                key={appliance.id}
                x={x}
                y={y}
                width={width}
                height={height}
                fill={LAYER_COLORS.APPLIANCES}
                fillOpacity="0.2"
                stroke={LAYER_COLORS.APPLIANCES}
                strokeWidth="1.5"
              />
            )
          })}

          {/* Doors */}
          {layerVisibility.DOORS && measurements.doors?.map(door => {
            const x = (door.position.x - door.width_ft / 2) * scale
            const y = door.position.z * scale
            const width = door.width_ft * scale
            return (
              <g key={door.id}>
                {/* Door opening line */}
                <line
                  x1={x}
                  y1={y}
                  x2={x + width}
                  y2={y}
                  stroke={LAYER_COLORS.DOORS}
                  strokeWidth="3"
                />
                {/* Door swing arc */}
                <path
                  d={`M ${x} ${y} A ${width} ${width} 0 0 1 ${x + width} ${y - width}`}
                  fill="none"
                  stroke={LAYER_COLORS.DOORS}
                  strokeWidth="1"
                  strokeDasharray="4 2"
                />
              </g>
            )
          })}

          {/* Windows */}
          {layerVisibility.WINDOWS && measurements.windows?.map(window => {
            const x = (window.position.x - window.width_ft / 2) * scale
            const y = window.position.z * scale
            const width = window.width_ft * scale
            return (
              <g key={window.id}>
                {/* Window frame */}
                <line
                  x1={x}
                  y1={y - 2}
                  x2={x + width}
                  y2={y - 2}
                  stroke={LAYER_COLORS.WINDOWS}
                  strokeWidth="4"
                />
                <line
                  x1={x}
                  y1={y + 2}
                  x2={x + width}
                  y2={y + 2}
                  stroke={LAYER_COLORS.WINDOWS}
                  strokeWidth="4"
                />
                {/* Center divider */}
                <line
                  x1={x + width / 2}
                  y1={y - 4}
                  x2={x + width / 2}
                  y2={y + 4}
                  stroke={LAYER_COLORS.WINDOWS}
                  strokeWidth="1"
                />
              </g>
            )
          })}
          </g>
        </svg>

        {/* Status bar */}
        <div className="absolute bottom-3 left-3 right-3 z-20 flex items-center justify-between">
          {/* Coordinates */}
          <div className="bg-gray-800/90 backdrop-blur-sm rounded px-3 py-1.5 text-xs font-mono text-gray-400">
            X: {mouseCoords.x.toFixed(2)} ft &nbsp; Y: {mouseCoords.y.toFixed(2)} ft
          </div>

          {/* Scale indicator */}
          <div className="bg-gray-800/90 backdrop-blur-sm rounded px-3 py-1.5 text-xs font-mono text-gray-400">
            Scale: {Math.round(zoom * 100)}% &nbsp;|&nbsp; Room: {roomWidth.toFixed(1)} x {roomDepth.toFixed(1)} ft
          </div>
        </div>
      </div>
    </div>
  )
}
