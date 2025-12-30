'use client'

import { useState, useMemo, useRef, useCallback, useEffect } from 'react'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  X,
  Ruler,
  Box,
  Square,
  RotateCcw,
  ZoomIn,
  ZoomOut,
  Move,
  Maximize2,
  Minimize2,
  Download,
  Eye,
  EyeOff,
  Compass,
  Keyboard,
  Loader2
} from 'lucide-react'

// iOS data structure types
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

interface InteractiveFloorPlanProps {
  measurements: MeasurementsData | null | undefined
  className?: string
  isLoading?: boolean
  minimal?: boolean
}

interface SelectedObject {
  type: 'wall' | 'cabinet' | 'appliance' | 'door' | 'window'
  data: WallData | CabinetData | ApplianceData | DoorData | WindowData
  label: string
}

interface LabelPosition {
  id: string
  x: number
  y: number
  width: number
  height: number
  text: string
  rotation: number
}

// Collision detection for labels
function resolveCollisions(labels: LabelPosition[]): LabelPosition[] {
  const resolved = [...labels]
  const iterations = 10
  const padding = 4

  for (let iter = 0; iter < iterations; iter++) {
    let hasCollision = false

    for (let i = 0; i < resolved.length; i++) {
      for (let j = i + 1; j < resolved.length; j++) {
        const a = resolved[i]
        const b = resolved[j]

        // Check for overlap
        const overlapX = Math.abs(a.x - b.x) < (a.width + b.width) / 2 + padding
        const overlapY = Math.abs(a.y - b.y) < (a.height + b.height) / 2 + padding

        if (overlapX && overlapY) {
          hasCollision = true

          // Calculate push direction
          const dx = b.x - a.x
          const dy = b.y - a.y
          const distance = Math.sqrt(dx * dx + dy * dy) || 1

          // Push apart
          const pushX = (dx / distance) * 3
          const pushY = (dy / distance) * 3

          resolved[i] = { ...a, x: a.x - pushX, y: a.y - pushY }
          resolved[j] = { ...b, x: b.x + pushX, y: b.y + pushY }
        }
      }
    }

    if (!hasCollision) break
  }

  return resolved
}

export function InteractiveFloorPlan({
  measurements,
  className = '',
  isLoading = false,
  minimal = false
}: InteractiveFloorPlanProps) {
  const [selectedObject, setSelectedObject] = useState<SelectedObject | null>(null)
  const [hoveredObject, setHoveredObject] = useState<string | null>(null)
  const [rotation, setRotation] = useState(0)
  const [targetRotation, setTargetRotation] = useState(0)
  const [zoom, setZoom] = useState(1)
  const [targetZoom, setTargetZoom] = useState(1)
  const [showLabels, setShowLabels] = useState(true)
  const [isFullscreen, setIsFullscreen] = useState(false)
  const [showKeyboardHints, setShowKeyboardHints] = useState(false)
  const [tooltipData, setTooltipData] = useState<{ x: number; y: number; content: string } | null>(null)

  const svgRef = useRef<SVGSVGElement>(null)
  const containerRef = useRef<HTMLDivElement>(null)
  const animationRef = useRef<number | null>(null)

  // Touch gesture state
  const touchRef = useRef<{
    initialDistance: number | null
    initialRotation: number | null
    initialZoom: number
    initialRotationValue: number
    lastTouchEnd: number
  }>({
    initialDistance: null,
    initialRotation: null,
    initialZoom: 1,
    initialRotationValue: 0,
    lastTouchEnd: 0
  })

  // Smooth animation for rotation and zoom
  useEffect(() => {
    const animate = () => {
      setRotation(prev => {
        const diff = targetRotation - prev
        if (Math.abs(diff) < 0.5) return targetRotation
        return prev + diff * 0.15
      })

      setZoom(prev => {
        const diff = targetZoom - prev
        if (Math.abs(diff) < 0.01) return targetZoom
        return prev + diff * 0.15
      })

      animationRef.current = requestAnimationFrame(animate)
    }

    animationRef.current = requestAnimationFrame(animate)

    return () => {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current)
      }
    }
  }, [targetRotation, targetZoom])

  // Sync fullscreen state with browser fullscreen changes
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
      // Don't capture if focused on input
      if (document.activeElement?.tagName === 'INPUT') return

      switch (e.key) {
        case 'ArrowLeft':
          e.preventDefault()
          setTargetRotation(prev => (prev - 15 + 360) % 360)
          break
        case 'ArrowRight':
          e.preventDefault()
          setTargetRotation(prev => (prev + 15) % 360)
          break
        case 'ArrowUp':
        case '+':
        case '=':
          e.preventDefault()
          setTargetZoom(prev => Math.min(2, prev + 0.1))
          break
        case 'ArrowDown':
        case '-':
          e.preventDefault()
          setTargetZoom(prev => Math.max(0.5, prev - 0.1))
          break
        case 'r':
        case 'R':
          e.preventDefault()
          resetView()
          break
        case 'l':
        case 'L':
          e.preventDefault()
          setShowLabels(prev => !prev)
          break
        case 'f':
        case 'F':
          e.preventDefault()
          toggleFullscreen()
          break
        case 'Escape':
          setSelectedObject(null)
          break
        case '?':
          e.preventDefault()
          setShowKeyboardHints(prev => !prev)
          break
      }
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [])

  // Touch gesture handlers
  const handleTouchStart = useCallback((e: React.TouchEvent) => {
    if (e.touches.length === 2) {
      const dx = e.touches[0].clientX - e.touches[1].clientX
      const dy = e.touches[0].clientY - e.touches[1].clientY

      touchRef.current = {
        initialDistance: Math.hypot(dx, dy),
        initialRotation: Math.atan2(dy, dx) * 180 / Math.PI,
        initialZoom: targetZoom,
        initialRotationValue: targetRotation,
        lastTouchEnd: touchRef.current.lastTouchEnd
      }
    }
  }, [targetZoom, targetRotation])

  const handleTouchMove = useCallback((e: React.TouchEvent) => {
    if (e.touches.length === 2 && touchRef.current.initialDistance !== null) {
      e.preventDefault()

      const dx = e.touches[0].clientX - e.touches[1].clientX
      const dy = e.touches[0].clientY - e.touches[1].clientY
      const currentDistance = Math.hypot(dx, dy)
      const currentAngle = Math.atan2(dy, dx) * 180 / Math.PI

      // Pinch to zoom
      const scale = currentDistance / touchRef.current.initialDistance
      const newZoom = Math.max(0.5, Math.min(2, touchRef.current.initialZoom * scale))
      setTargetZoom(newZoom)

      // Two finger rotate
      if (touchRef.current.initialRotation !== null) {
        let angleDiff = currentAngle - touchRef.current.initialRotation
        const newRotation = (touchRef.current.initialRotationValue + angleDiff + 360) % 360
        setTargetRotation(newRotation)
      }
    }
  }, [])

  const handleTouchEnd = useCallback(() => {
    touchRef.current = {
      ...touchRef.current,
      initialDistance: null,
      initialRotation: null,
      lastTouchEnd: Date.now()
    }
  }, [])

  // Extract arrays safely with null checks
  const walls = Array.isArray(measurements?.walls) ? measurements.walls : []
  const upperCabinets = Array.isArray(measurements?.cabinets?.upper) ? measurements.cabinets.upper : []
  const lowerCabinets = Array.isArray(measurements?.cabinets?.lower) ? measurements.cabinets.lower : []
  const appliances = Array.isArray(measurements?.appliances) ? measurements.appliances : []
  const doors = Array.isArray(measurements?.doors) ? measurements.doors : []
  const windows = Array.isArray(measurements?.windows) ? measurements.windows : []
  const room = measurements?.room

  // Check if we have any data to display
  const hasData = walls.length > 0 || lowerCabinets.length > 0 || upperCabinets.length > 0 ||
                  appliances.length > 0 || doors.length > 0 || windows.length > 0

  // Calculate dominant angle from walls to auto-straighten the view
  const dominantAngle = useMemo(() => {
    if (walls.length === 0) return 0

    // Find the longest wall and calculate its angle
    let longestWall: WallData | null = null
    let maxLength = 0

    for (const wall of walls) {
      if (wall.linear_ft > maxLength) {
        maxLength = wall.linear_ft
        longestWall = wall
      }
    }

    if (!longestWall || !longestWall.start || !longestWall.end) return 0

    // Calculate angle of longest wall
    const dx = longestWall.end.x - longestWall.start.x
    const dz = longestWall.end.z - longestWall.start.z
    let angle = Math.atan2(dz, dx) * (180 / Math.PI)

    // Snap to nearest 90 degree increment and return the correction needed
    const snapped = Math.round(angle / 90) * 90
    return snapped - angle // Same formula as DXF preview
  }, [walls])

  // Set initial rotation to auto-straighten when measurements load
  useEffect(() => {
    setRotation(dominantAngle)
    setTargetRotation(dominantAngle)
  }, [dominantAngle])

  // Calculate room center
  const roomCenter = useMemo(() => {
    if (room) {
      return {
        x: (room.min_x + room.max_x) / 2,
        z: (room.min_z + room.max_z) / 2
      }
    }
    if (walls.length > 0) {
      let sumX = 0, sumZ = 0, count = 0
      walls.forEach(wall => {
        if (wall.start && wall.end) {
          sumX += (wall.start.x + wall.end.x) / 2
          sumZ += (wall.start.z + wall.end.z) / 2
          count++
        }
      })
      return { x: sumX / count, z: sumZ / count }
    }
    return { x: 10, z: 10 }
  }, [room, walls])

  // View configuration
  const viewConfig = useMemo(() => {
    const viewWidth = 700
    const viewHeight = 550
    const margin = minimal ? 40 : 60 // Reduced margin for better auto-fit

    if (room && room.min_x !== undefined) {
      const padding = 4
      const minX = room.min_x - padding
      const maxX = room.max_x + padding
      const minZ = room.min_z - padding
      const maxZ = room.max_z + padding

      const roomWidth = maxX - minX
      const roomDepth = maxZ - minZ

      const scaleX = (viewWidth - margin * 2) / roomWidth
      const scaleZ = (viewHeight - margin * 2) / roomDepth
      const scale = Math.min(scaleX, scaleZ) * zoom

      return { minX, maxX, minZ, maxZ, scale, padding: margin, viewWidth, viewHeight, roomWidth, roomDepth }
    }

    if (walls.length === 0) {
      return { minX: 0, maxX: 20, minZ: 0, maxZ: 20, scale: 20 * zoom, padding: margin, viewWidth, viewHeight, roomWidth: 20, roomDepth: 20 }
    }

    let minX = Infinity, maxX = -Infinity
    let minZ = Infinity, maxZ = -Infinity

    walls.forEach((wall: WallData) => {
      if (wall.start && wall.end) {
        minX = Math.min(minX, wall.start.x, wall.end.x)
        maxX = Math.max(maxX, wall.start.x, wall.end.x)
        minZ = Math.min(minZ, wall.start.z, wall.end.z)
        maxZ = Math.max(maxZ, wall.start.z, wall.end.z)
      }
    })

    const padding = 4
    minX -= padding
    maxX += padding
    minZ -= padding
    maxZ += padding

    const roomWidth = maxX - minX
    const roomDepth = maxZ - minZ

    const scaleX = (viewWidth - margin * 2) / roomWidth
    const scaleZ = (viewHeight - margin * 2) / roomDepth
    const scale = Math.min(scaleX, scaleZ) * zoom

    return { minX, maxX, minZ, maxZ, scale, padding: margin, viewWidth, viewHeight, roomWidth, roomDepth }
  }, [walls, room, zoom, minimal])

  const { viewWidth, viewHeight } = viewConfig

  // Transform coordinates with rotation
  const toScreen = useCallback((x: number, z: number) => {
    const dx = x - roomCenter.x
    const dz = z - roomCenter.z

    const rad = (rotation * Math.PI) / 180
    const rotX = dx * Math.cos(rad) - dz * Math.sin(rad)
    const rotZ = dx * Math.sin(rad) + dz * Math.cos(rad)

    const centerScreenX = viewWidth / 2
    const centerScreenY = viewHeight / 2

    return {
      x: centerScreenX + rotX * viewConfig.scale,
      y: centerScreenY + rotZ * viewConfig.scale
    }
  }, [roomCenter, rotation, viewWidth, viewHeight, viewConfig.scale])

  // Find nearest wall
  const findNearestWall = useCallback((pos: Position): WallData | null => {
    let nearestWall: WallData | null = null
    let minDist = Infinity

    walls.forEach(wall => {
      if (!wall.start || !wall.end) return

      const dx = wall.end.x - wall.start.x
      const dz = wall.end.z - wall.start.z
      const len2 = dx * dx + dz * dz

      if (len2 === 0) return

      let t = ((pos.x - wall.start.x) * dx + (pos.z - wall.start.z) * dz) / len2
      t = Math.max(0, Math.min(1, t))

      const projX = wall.start.x + t * dx
      const projZ = wall.start.z + t * dz
      const dist = Math.sqrt((pos.x - projX) ** 2 + (pos.z - projZ) ** 2)

      if (dist < minDist) {
        minDist = dist
        nearestWall = wall
      }
    })

    return nearestWall
  }, [walls])

  // Get outside direction (away from room center)
  const getOutsideDirection = useCallback((wallStart: Position, wallEnd: Position) => {
    const midX = (wallStart.x + wallEnd.x) / 2
    const midZ = (wallStart.z + wallEnd.z) / 2

    const toCenterX = roomCenter.x - midX
    const toCenterZ = roomCenter.z - midZ

    const wallDx = wallEnd.x - wallStart.x
    const wallDz = wallEnd.z - wallStart.z
    const wallLen = Math.sqrt(wallDx * wallDx + wallDz * wallDz)

    if (wallLen === 0) return { x: 0, y: -1 }

    const perpX = -wallDz / wallLen
    const perpZ = wallDx / wallLen

    const dot = perpX * toCenterX + perpZ * toCenterZ

    if (dot > 0) {
      return { x: -perpX, y: -perpZ }
    } else {
      return { x: perpX, y: perpZ }
    }
  }, [roomCenter])

  // Get short appliance label
  const getApplianceLabel = (type: string): string => {
    const t = type.toLowerCase()
    if (t.includes('refrigerator') || t.includes('fridge')) return 'REF'
    if (t.includes('stove') || t.includes('oven') || t.includes('range')) return 'STOVE'
    if (t.includes('dishwasher')) return 'DW'
    if (t.includes('sink')) return 'SINK'
    if (t.includes('microwave')) return 'MW'
    if (t.includes('washer')) return 'W'
    if (t.includes('dryer')) return 'D'
    return type.substring(0, 3).toUpperCase()
  }

  // Render appliance icon
  const renderApplianceIcon = useCallback((type: string, cx: number, cy: number, width: number, height: number, showLabel: boolean = true) => {
    const t = type.toLowerCase()
    const iconScale = Math.min(width, height) * 0.3
    const label = getApplianceLabel(type)

    // Icon elements
    let icon = null

    if (t.includes('stove') || t.includes('oven') || t.includes('range')) {
      const burnerR = iconScale * 0.15
      const offset = iconScale * 0.25
      icon = (
        <g className="transition-opacity duration-200">
          {[-1, 1].map(dx =>
            [-1, 1].map(dy => (
              <circle
                key={`burner-${dx}-${dy}`}
                cx={cx + dx * offset}
                cy={cy + dy * offset - 4}
                r={burnerR}
                fill="none"
                stroke="#ea580c"
                strokeWidth="1.5"
              />
            ))
          )}
        </g>
      )
    } else if (t.includes('refrigerator') || t.includes('fridge')) {
      icon = (
        <g className="transition-opacity duration-200">
          <line
            x1={cx - iconScale * 0.4}
            y1={cy - iconScale * 0.3}
            x2={cx + iconScale * 0.4}
            y2={cy - iconScale * 0.3}
            stroke="#0891b2"
            strokeWidth="2"
          />
          <rect
            x={cx - iconScale * 0.4}
            y={cy - iconScale * 0.5}
            width={iconScale * 0.8}
            height={iconScale * 0.8}
            fill="none"
            stroke="#0891b2"
            strokeWidth="1"
            rx="2"
          />
        </g>
      )
    } else if (t.includes('sink')) {
      icon = (
        <ellipse
          cx={cx}
          cy={cy - 4}
          rx={iconScale * 0.4}
          ry={iconScale * 0.25}
          fill="none"
          stroke="#6b7280"
          strokeWidth="1.5"
          className="transition-opacity duration-200"
        />
      )
    } else if (t.includes('dishwasher')) {
      const s = iconScale * 0.25
      icon = (
        <g className="transition-opacity duration-200">
          <rect
            x={cx - s}
            y={cy - s - 4}
            width={s * 2}
            height={s * 2}
            fill="none"
            stroke="#6b7280"
            strokeWidth="1"
            rx="2"
          />
          <line x1={cx - s + 2} y1={cy - 4} x2={cx + s - 2} y2={cy - 4} stroke="#6b7280" strokeWidth="1" />
        </g>
      )
    }

    return (
      <g className="pointer-events-none">
        {icon}
        {showLabel && (
          <text
            x={cx}
            y={cy + (icon ? 8 : 0)}
            textAnchor="middle"
            dominantBaseline="middle"
            fontSize="8"
            fontWeight="600"
            fill="#92400e"
            className="pointer-events-none"
          >
            {label}
          </text>
        )}
      </g>
    )
  }, [])

  // Format measurements
  const formatFeetInches = (feet: number) => {
    const wholeFeet = Math.floor(feet)
    const inches = Math.round((feet - wholeFeet) * 12)
    if (inches === 12) return `${wholeFeet + 1}'0"`
    return `${wholeFeet}'${inches}"`
  }

  const formatInches = (feet: number) => {
    return `${Math.round(feet * 12)}"`
  }

  // Reset view with animation (resets to auto-straightened angle)
  const resetView = useCallback(() => {
    setTargetRotation(dominantAngle)
    setTargetZoom(1)
  }, [dominantAngle])

  // Toggle fullscreen
  const toggleFullscreen = useCallback(async () => {
    if (!containerRef.current) return

    try {
      if (!document.fullscreenElement) {
        // Enter fullscreen
        await containerRef.current.requestFullscreen()
        setIsFullscreen(true)
      } else {
        // Exit fullscreen
        await document.exitFullscreen()
        setIsFullscreen(false)
      }
    } catch (error) {
      console.error('Fullscreen error:', error)
    }
  }, [])

  // Export functions
  const exportAsPNG = useCallback(async () => {
    if (!svgRef.current) return

    const svg = svgRef.current
    const svgData = new XMLSerializer().serializeToString(svg)
    const svgBlob = new Blob([svgData], { type: 'image/svg+xml;charset=utf-8' })
    const svgUrl = URL.createObjectURL(svgBlob)

    const img = new Image()
    img.onload = () => {
      const canvas = document.createElement('canvas')
      const scale = 2 // Higher resolution
      canvas.width = viewWidth * scale
      canvas.height = viewHeight * scale

      const ctx = canvas.getContext('2d')
      if (!ctx) return

      ctx.fillStyle = '#ffffff'
      ctx.fillRect(0, 0, canvas.width, canvas.height)
      ctx.scale(scale, scale)
      ctx.drawImage(img, 0, 0)

      const pngUrl = canvas.toDataURL('image/png')
      const link = document.createElement('a')
      link.download = 'floor-plan.png'
      link.href = pngUrl
      link.click()

      URL.revokeObjectURL(svgUrl)
    }
    img.src = svgUrl
  }, [viewWidth, viewHeight])

  const exportAsSVG = useCallback(() => {
    if (!svgRef.current) return

    const svg = svgRef.current.cloneNode(true) as SVGSVGElement
    const svgData = new XMLSerializer().serializeToString(svg)
    const svgBlob = new Blob([svgData], { type: 'image/svg+xml;charset=utf-8' })
    const svgUrl = URL.createObjectURL(svgBlob)

    const link = document.createElement('a')
    link.download = 'floor-plan.svg'
    link.href = svgUrl
    link.click()

    URL.revokeObjectURL(svgUrl)
  }, [])

  // Handle hover tooltip
  const handleHover = useCallback((
    e: React.MouseEvent,
    id: string,
    content: string
  ) => {
    setHoveredObject(id)
    const rect = containerRef.current?.getBoundingClientRect()
    if (rect) {
      setTooltipData({
        x: e.clientX - rect.left,
        y: e.clientY - rect.top - 40,
        content
      })
    }
  }, [])

  const handleHoverEnd = useCallback(() => {
    setHoveredObject(null)
    setTooltipData(null)
  }, [])

  // Calculate wall labels with collision avoidance (including segments split by doors/windows)
  const wallLabels = useMemo(() => {
    if (!showLabels) return []

    const labels: LabelPosition[] = []

    walls.forEach((wall, idx) => {
      if (!wall.start || !wall.end) return

      const wallDx = wall.end.x - wall.start.x
      const wallDz = wall.end.z - wall.start.z
      const wallLengthCoords = Math.sqrt(wallDx * wallDx + wallDz * wallDz)
      const wallLengthFt = wall.linear_ft || wall.width_ft || 0

      if (wallLengthCoords === 0 || wallLengthFt === 0) return

      // Find doors and windows on this wall
      const openingsOnWall: Array<{ position: number; width: number }> = []

      // Check doors
      doors.forEach(door => {
        const dx = door.position.x - wall.start.x
        const dz = door.position.z - wall.start.z
        const t = (dx * wallDx + dz * wallDz) / (wallLengthCoords * wallLengthCoords)

        if (t >= -0.05 && t <= 1.05) {
          const projX = wall.start.x + t * wallDx
          const projZ = wall.start.z + t * wallDz
          const dist = Math.sqrt((door.position.x - projX) ** 2 + (door.position.z - projZ) ** 2)

          if (dist < 1.5) {
            openingsOnWall.push({ position: t * wallLengthFt, width: door.width_ft })
          }
        }
      })

      // Check windows
      windows.forEach(window => {
        const dx = window.position.x - wall.start.x
        const dz = window.position.z - wall.start.z
        const t = (dx * wallDx + dz * wallDz) / (wallLengthCoords * wallLengthCoords)

        if (t >= -0.05 && t <= 1.05) {
          const projX = wall.start.x + t * wallDx
          const projZ = wall.start.z + t * wallDz
          const dist = Math.sqrt((window.position.x - projX) ** 2 + (window.position.z - projZ) ** 2)

          if (dist < 1.5) {
            openingsOnWall.push({ position: t * wallLengthFt, width: window.width_ft })
          }
        }
      })

      // Sort openings by position along the wall
      openingsOnWall.sort((a, b) => a.position - b.position)

      // Calculate wall segments
      const segments: Array<{ start: number; end: number; length: number }> = []
      let currentPos = 0

      openingsOnWall.forEach(opening => {
        const openingStart = opening.position - opening.width / 2
        const openingEnd = opening.position + opening.width / 2

        // Segment before the opening
        if (openingStart > currentPos + 0.5) {
          segments.push({
            start: currentPos,
            end: openingStart,
            length: openingStart - currentPos
          })
        }

        currentPos = openingEnd
      })

      // Final segment after last opening
      if (currentPos < wallLengthFt - 0.5) {
        segments.push({
          start: currentPos,
          end: wallLengthFt,
          length: wallLengthFt - currentPos
        })
      }

      // If no segments (no openings or wall too short), use the whole wall
      if (segments.length === 0) {
        const start = toScreen(wall.start.x, wall.start.z)
        const end = toScreen(wall.end.x, wall.end.z)

        const midX = (start.x + end.x) / 2
        const midY = (start.y + end.y) / 2

        const screenAngle = Math.atan2(end.y - start.y, end.x - start.x) * 180 / Math.PI
        const textAngle = (screenAngle > 90 || screenAngle < -90) ? screenAngle + 180 : screenAngle

        const outside = getOutsideDirection(wall.start, wall.end)
        const rad = (rotation * Math.PI) / 180
        const rotOutX = outside.x * Math.cos(rad) - outside.y * Math.sin(rad)
        const rotOutY = outside.x * Math.sin(rad) + outside.y * Math.cos(rad)

        const labelOffset = 22

        labels.push({
          id: `wall-label-${idx}`,
          x: midX + rotOutX * labelOffset,
          y: midY + rotOutY * labelOffset,
          width: 48,
          height: 18,
          text: formatFeetInches(wallLengthFt),
          rotation: textAngle
        })
      } else {
        // Create labels for each segment
        segments.forEach((segment, segIdx) => {
          // Convert feet position to parametric position (0-1) then to coordinates
          const tStart = segment.start / wallLengthFt
          const tEnd = segment.end / wallLengthFt

          const segmentStartX = wall.start.x + wallDx * tStart
          const segmentStartZ = wall.start.z + wallDz * tStart
          const segmentEndX = wall.start.x + wallDx * tEnd
          const segmentEndZ = wall.start.z + wallDz * tEnd

          const segStart = toScreen(segmentStartX, segmentStartZ)
          const segEnd = toScreen(segmentEndX, segmentEndZ)

          const midX = (segStart.x + segEnd.x) / 2
          const midY = (segStart.y + segEnd.y) / 2

          const screenAngle = Math.atan2(segEnd.y - segStart.y, segEnd.x - segStart.x) * 180 / Math.PI
          const textAngle = (screenAngle > 90 || screenAngle < -90) ? screenAngle + 180 : screenAngle

          const outside = getOutsideDirection(wall.start, wall.end)
          const rad = (rotation * Math.PI) / 180
          const rotOutX = outside.x * Math.cos(rad) - outside.y * Math.sin(rad)
          const rotOutY = outside.x * Math.sin(rad) + outside.y * Math.cos(rad)

          const labelOffset = 22

          labels.push({
            id: `wall-label-${idx}-seg-${segIdx}`,
            x: midX + rotOutX * labelOffset,
            y: midY + rotOutY * labelOffset,
            width: 48,
            height: 18,
            text: formatFeetInches(segment.length),
            rotation: textAngle
          })
        })
      }
    })

    return resolveCollisions(labels)
  }, [walls, doors, windows, showLabels, toScreen, getOutsideDirection, rotation])

  // Render detail panel
  const renderDetailPanel = () => {
    if (!selectedObject) return null

    const { type, data, label } = selectedObject

    return (
      <div
        className="absolute top-4 right-4 w-64 bg-white rounded-xl shadow-2xl border border-gray-100 p-4 z-30 animate-in slide-in-from-right-2 duration-300"
        style={{ backdropFilter: 'blur(8px)' }}
      >
        <div className="flex items-center justify-between mb-3">
          <Badge variant="outline" className="capitalize font-medium">{label}</Badge>
          <button
            onClick={() => setSelectedObject(null)}
            className="p-1.5 hover:bg-gray-100 rounded-lg transition-colors duration-200"
            aria-label="Close details"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {type === 'wall' && (
          <div className="space-y-3">
            <div className="flex items-center gap-3 p-2 bg-blue-50 rounded-lg">
              <div className="p-1.5 bg-blue-100 rounded-md">
                <Ruler className="h-4 w-4 text-blue-600" />
              </div>
              <div>
                <span className="text-xs text-gray-500 block">Length</span>
                <span className="font-semibold text-gray-900">
                  {formatFeetInches((data as WallData).width_ft || (data as WallData).linear_ft)}
                </span>
              </div>
            </div>
            <div className="flex items-center gap-3 p-2 bg-blue-50 rounded-lg">
              <div className="p-1.5 bg-blue-100 rounded-md">
                <Box className="h-4 w-4 text-blue-600" />
              </div>
              <div>
                <span className="text-xs text-gray-500 block">Height</span>
                <span className="font-semibold text-gray-900">{formatFeetInches((data as WallData).height_ft)}</span>
              </div>
            </div>
          </div>
        )}

        {type === 'cabinet' && (
          <div className="space-y-3">
            <div className="flex items-center gap-3 p-2 bg-green-50 rounded-lg">
              <div className="p-1.5 bg-green-100 rounded-md">
                <Ruler className="h-4 w-4 text-green-600" />
              </div>
              <div>
                <span className="text-xs text-gray-500 block">Width</span>
                <span className="font-semibold text-gray-900">{formatFeetInches((data as CabinetData).width_ft)}</span>
              </div>
            </div>
            <div className="flex items-center gap-3 p-2 bg-green-50 rounded-lg">
              <div className="p-1.5 bg-green-100 rounded-md">
                <Ruler className="h-4 w-4 text-green-600" />
              </div>
              <div>
                <span className="text-xs text-gray-500 block">Depth</span>
                <span className="font-semibold text-gray-900">{formatFeetInches((data as CabinetData).depth_ft)}</span>
              </div>
            </div>
            <div className="flex items-center gap-3 p-2 bg-green-50 rounded-lg">
              <div className="p-1.5 bg-green-100 rounded-md">
                <Box className="h-4 w-4 text-green-600" />
              </div>
              <div>
                <span className="text-xs text-gray-500 block">Height</span>
                <span className="font-semibold text-gray-900">{formatFeetInches((data as CabinetData).height_ft)}</span>
              </div>
            </div>
          </div>
        )}

        {type === 'appliance' && (
          <div className="space-y-3">
            <div className="text-base font-medium capitalize text-orange-700 mb-2">
              {(data as ApplianceData).type}
            </div>
            <div className="flex items-center gap-3 p-2 bg-orange-50 rounded-lg">
              <div className="p-1.5 bg-orange-100 rounded-md">
                <Ruler className="h-4 w-4 text-orange-600" />
              </div>
              <div>
                <span className="text-xs text-gray-500 block">Width</span>
                <span className="font-semibold text-gray-900">{formatFeetInches((data as ApplianceData).width_ft)}</span>
              </div>
            </div>
            <div className="flex items-center gap-3 p-2 bg-orange-50 rounded-lg">
              <div className="p-1.5 bg-orange-100 rounded-md">
                <Ruler className="h-4 w-4 text-orange-600" />
              </div>
              <div>
                <span className="text-xs text-gray-500 block">Depth</span>
                <span className="font-semibold text-gray-900">{formatFeetInches((data as ApplianceData).depth_ft)}</span>
              </div>
            </div>
          </div>
        )}

        {(type === 'door' || type === 'window') && (
          <div className="space-y-3">
            <div className="flex items-center gap-3 p-2 bg-cyan-50 rounded-lg">
              <div className="p-1.5 bg-cyan-100 rounded-md">
                <Ruler className="h-4 w-4 text-cyan-600" />
              </div>
              <div>
                <span className="text-xs text-gray-500 block">Width</span>
                <span className="font-semibold text-gray-900">
                  {formatFeetInches((data as DoorData | WindowData).width_ft)}
                </span>
              </div>
            </div>
            <div className="flex items-center gap-3 p-2 bg-cyan-50 rounded-lg">
              <div className="p-1.5 bg-cyan-100 rounded-md">
                <Box className="h-4 w-4 text-cyan-600" />
              </div>
              <div>
                <span className="text-xs text-gray-500 block">Height</span>
                <span className="font-semibold text-gray-900">
                  {formatFeetInches((data as DoorData | WindowData).height_ft)}
                </span>
              </div>
            </div>
          </div>
        )}
      </div>
    )
  }

  // Render loading state
  if (isLoading) {
    if (minimal) {
      return (
        <div className={`flex flex-col items-center justify-center h-[60vh] gap-4 bg-gray-50 rounded-lg ${className}`}>
          <Loader2 className="h-8 w-8 text-blue-500 animate-spin" />
          <p className="text-gray-500 text-sm">Loading floor plan data...</p>
        </div>
      )
    }
    return (
      <Card className={className}>
        <CardContent className="flex flex-col items-center justify-center h-96 gap-4">
          <Loader2 className="h-8 w-8 text-blue-500 animate-spin" />
          <p className="text-gray-500 text-sm">Loading floor plan data...</p>
        </CardContent>
      </Card>
    )
  }

  // Render empty state
  if (!measurements || !hasData) {
    if (minimal) {
      return (
        <div className={`flex flex-col items-center justify-center h-[60vh] gap-4 bg-gray-50 rounded-lg ${className}`}>
          <div className="p-4 bg-white rounded-full shadow-sm">
            <Square className="h-12 w-12 text-gray-300" />
          </div>
          <div className="text-center">
            <p className="text-gray-600 font-medium">No floor plan data available</p>
            <p className="text-gray-400 text-sm mt-1">
              Scan measurements will appear here once processed
            </p>
          </div>
        </div>
      )
    }
    return (
      <Card className={className}>
        <CardHeader className="pb-2">
          <CardTitle className="flex items-center gap-2">
            <Square className="h-5 w-5 text-blue-600" />
            Interactive Floor Plan
          </CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col items-center justify-center h-80 gap-4">
          <div className="p-4 bg-gray-50 rounded-full">
            <Square className="h-12 w-12 text-gray-300" />
          </div>
          <div className="text-center">
            <p className="text-gray-600 font-medium">No floor plan data available</p>
            <p className="text-gray-400 text-sm mt-1">
              Scan measurements will appear here once processed
            </p>
          </div>
        </CardContent>
      </Card>
    )
  }

  const roomArea = room
    ? ((room.max_x - room.min_x) * (room.max_z - room.min_z)).toFixed(0)
    : null

  // Render the SVG content (shared between minimal and full versions)
  const renderSvgContent = () => (
    <>
      {/* Gradient definitions for shadows and effects */}
      <defs>
        <pattern id="grid" width="40" height="40" patternUnits="userSpaceOnUse">
          <path d="M 40 0 L 0 0 0 40" fill="none" stroke="#e5e7eb" strokeWidth="0.5" />
        </pattern>

        {/* Drop shadow filter */}
        <filter id="dropShadow" x="-20%" y="-20%" width="140%" height="140%">
          <feDropShadow dx="0" dy="2" stdDeviation="3" floodOpacity="0.15"/>
        </filter>

        {/* Glow filter for selection */}
        <filter id="glow" x="-50%" y="-50%" width="200%" height="200%">
          <feGaussianBlur stdDeviation="3" result="coloredBlur"/>
          <feMerge>
            <feMergeNode in="coloredBlur"/>
            <feMergeNode in="SourceGraphic"/>
          </feMerge>
        </filter>

        {/* Cabinet gradient */}
        <linearGradient id="cabinetGradient" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stopColor="#fafafa"/>
          <stop offset="100%" stopColor="#f0f0f0"/>
        </linearGradient>

        {/* Selected cabinet gradient */}
        <linearGradient id="cabinetSelectedGradient" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stopColor="#dcfce7"/>
          <stop offset="100%" stopColor="#bbf7d0"/>
        </linearGradient>
      </defs>

      {/* Background with subtle gradient */}
      <rect width="100%" height="100%" fill="#fafafa" />
      <rect width="100%" height="100%" fill="url(#grid)" />
    </>
  )

  // Minimal render mode
  if (minimal) {
    return (
      <div className={`relative ${className}`}>
        {/* Floating controls */}
        <div className="absolute top-3 right-3 z-20 flex gap-1 bg-white/90 backdrop-blur-sm rounded-full px-2 py-1 shadow-sm border border-gray-200/50">
          <Button
            variant="ghost"
            size="icon"
            onClick={resetView}
            title="Reset view"
            className="h-8 w-8 hover:bg-gray-100"
          >
            <RotateCcw className="h-4 w-4" />
          </Button>
          <Button
            variant="ghost"
            size="icon"
            onClick={() => setShowLabels(!showLabels)}
            title={showLabels ? "Hide labels" : "Show labels"}
            className="h-8 w-8 hover:bg-gray-100"
          >
            {showLabels ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
          </Button>
          <Button
            variant="ghost"
            size="icon"
            onClick={toggleFullscreen}
            title="Fullscreen"
            className="h-8 w-8 hover:bg-gray-100"
          >
            {isFullscreen ? <Minimize2 className="h-4 w-4" /> : <Maximize2 className="h-4 w-4" />}
          </Button>
        </div>

        {/* Rotation slider (compact, at bottom) */}
        <div className="absolute bottom-3 left-3 right-3 z-20 flex items-center gap-2 bg-white/90 backdrop-blur-sm rounded-full px-3 py-1.5 shadow-sm border border-gray-200/50">
          <Move className="h-3 w-3 text-gray-400 flex-shrink-0" />
          <input
            type="range"
            min={0}
            max={360}
            step={1}
            value={targetRotation}
            onChange={(e) => setTargetRotation(Number(e.target.value))}
            className="flex-1 h-1.5 bg-gray-200 rounded-lg appearance-none cursor-pointer accent-blue-600"
          />
          <span className="text-xs text-gray-500 w-8 text-right font-mono">{Math.round(rotation)}°</span>
        </div>

        <div
          ref={containerRef}
          className={`relative overflow-hidden ${isFullscreen ? 'h-screen' : 'h-[60vh] min-h-[400px]'}`}
          onTouchStart={handleTouchStart}
          onTouchMove={handleTouchMove}
          onTouchEnd={handleTouchEnd}
          style={{ touchAction: 'none' }}
        >
          <svg
            ref={svgRef}
            viewBox={`0 0 ${viewWidth} ${viewHeight}`}
            className="w-full h-full"
            preserveAspectRatio="xMidYMid slice"
            role="img"
            aria-label="Interactive floor plan showing room layout with walls, cabinets, and appliances"
          >
            {renderSvgContent()}

            {/* Lower Cabinets */}
            {lowerCabinets.map((cabinet, idx) => {
              const id = `cabinet-lower-${idx}`
              const isHovered = hoveredObject === id
              const isSelected = selectedObject?.data?.id === cabinet.id

              if (cabinet.corners && cabinet.corners.length >= 4) {
                const screenCorners = cabinet.corners.map(c => toScreen(c.x, c.z))
                const points = screenCorners.map(s => `${s.x},${s.y}`).join(' ')

                const centerX = screenCorners.reduce((sum, c) => sum + c.x, 0) / screenCorners.length
                const centerY = screenCorners.reduce((sum, c) => sum + c.y, 0) / screenCorners.length

                return (
                  <g key={id} filter={isHovered || isSelected ? 'url(#dropShadow)' : undefined}>
                    <polygon
                      points={points}
                      fill={isSelected ? 'url(#cabinetSelectedGradient)' : isHovered ? '#f0fdf4' : 'url(#cabinetGradient)'}
                      stroke={isSelected ? '#16a34a' : isHovered ? '#22c55e' : '#374151'}
                      strokeWidth={isSelected ? 2.5 : isHovered ? 2 : 1.5}
                      className="cursor-pointer"
                      style={{ transition: 'all 0.2s ease-out' }}
                      onMouseEnter={(e) => handleHover(e, id, `Lower Cabinet: ${formatInches(cabinet.width_ft)} x ${formatInches(cabinet.depth_ft)}`)}
                      onMouseLeave={handleHoverEnd}
                      onClick={() => setSelectedObject({ type: 'cabinet', data: cabinet, label: 'Lower Cabinet' })}
                    />
                    {showLabels && (
                      <text
                        x={centerX}
                        y={centerY}
                        textAnchor="middle"
                        dominantBaseline="middle"
                        fontSize="9"
                        fill="#374151"
                        className="pointer-events-none font-medium"
                        style={{ transition: 'opacity 0.2s' }}
                      >
                        {formatInches(cabinet.width_ft)}
                      </text>
                    )}
                  </g>
                )
              }

              const screen = toScreen(cabinet.position.x, cabinet.position.z)
              const w = cabinet.width_ft * viewConfig.scale
              const d = cabinet.depth_ft * viewConfig.scale

              return (
                <g key={id} filter={isHovered || isSelected ? 'url(#dropShadow)' : undefined}>
                  <rect
                    x={screen.x - w / 2}
                    y={screen.y - d / 2}
                    width={w}
                    height={d}
                    fill={isSelected ? 'url(#cabinetSelectedGradient)' : isHovered ? '#f0fdf4' : 'url(#cabinetGradient)'}
                    stroke={isSelected ? '#16a34a' : isHovered ? '#22c55e' : '#374151'}
                    strokeWidth={isSelected ? 2.5 : isHovered ? 2 : 1.5}
                    rx="2"
                    className="cursor-pointer"
                    style={{ transition: 'all 0.2s ease-out' }}
                    onMouseEnter={(e) => handleHover(e, id, `Lower Cabinet: ${formatInches(cabinet.width_ft)} x ${formatInches(cabinet.depth_ft)}`)}
                    onMouseLeave={handleHoverEnd}
                    onClick={() => setSelectedObject({ type: 'cabinet', data: cabinet, label: 'Lower Cabinet' })}
                  />
                  {showLabels && (
                    <text
                      x={screen.x}
                      y={screen.y}
                      textAnchor="middle"
                      dominantBaseline="middle"
                      fontSize="9"
                      fill="#374151"
                      className="pointer-events-none font-medium"
                    >
                      {formatInches(cabinet.width_ft)}
                    </text>
                  )}
                </g>
              )
            })}

            {/* Appliances */}
            {appliances.map((appliance, idx) => {
              const id = `appliance-${idx}`
              const isHovered = hoveredObject === id
              const isSelected = selectedObject?.data?.id === appliance.id
              const applianceType = appliance.type || 'Appliance'

              if (appliance.corners && appliance.corners.length >= 4) {
                const screenCorners = appliance.corners.map(c => toScreen(c.x, c.z))
                const points = screenCorners.map(s => `${s.x},${s.y}`).join(' ')

                const centerX = screenCorners.reduce((sum, c) => sum + c.x, 0) / screenCorners.length
                const centerY = screenCorners.reduce((sum, c) => sum + c.y, 0) / screenCorners.length

                const xs = screenCorners.map(c => c.x)
                const ys = screenCorners.map(c => c.y)
                const boxWidth = Math.max(...xs) - Math.min(...xs)
                const boxHeight = Math.max(...ys) - Math.min(...ys)

                return (
                  <g key={id} filter={isHovered || isSelected ? 'url(#dropShadow)' : undefined}>
                    <polygon
                      points={points}
                      fill={isSelected ? '#fef3c7' : isHovered ? '#fffbeb' : '#fffef5'}
                      stroke={isSelected ? '#d97706' : isHovered ? '#f59e0b' : '#f59e0b'}
                      strokeWidth={isSelected ? 2.5 : isHovered ? 2 : 1.5}
                      className="cursor-pointer"
                      style={{ transition: 'all 0.2s ease-out' }}
                      onMouseEnter={(e) => handleHover(e, id, `${applianceType}: ${formatInches(appliance.width_ft)} x ${formatInches(appliance.depth_ft)}`)}
                      onMouseLeave={handleHoverEnd}
                      onClick={() => setSelectedObject({ type: 'appliance', data: appliance, label: applianceType })}
                    />
                    {renderApplianceIcon(applianceType, centerX, centerY, boxWidth, boxHeight, false)}
                  </g>
                )
              }

              const screen = toScreen(appliance.position.x, appliance.position.z)
              const w = appliance.width_ft * viewConfig.scale
              const d = appliance.depth_ft * viewConfig.scale

              return (
                <g key={id} filter={isHovered || isSelected ? 'url(#dropShadow)' : undefined}>
                  <rect
                    x={screen.x - w / 2}
                    y={screen.y - d / 2}
                    width={w}
                    height={d}
                    fill={isSelected ? '#fef3c7' : isHovered ? '#fffbeb' : '#fffef5'}
                    stroke={isSelected ? '#d97706' : isHovered ? '#f59e0b' : '#f59e0b'}
                    strokeWidth={isSelected ? 2.5 : isHovered ? 2 : 1.5}
                    rx="2"
                    className="cursor-pointer"
                    style={{ transition: 'all 0.2s ease-out' }}
                    onMouseEnter={(e) => handleHover(e, id, `${applianceType}: ${formatInches(appliance.width_ft)} x ${formatInches(appliance.depth_ft)}`)}
                    onMouseLeave={handleHoverEnd}
                    onClick={() => setSelectedObject({ type: 'appliance', data: appliance, label: applianceType })}
                  />
                  {renderApplianceIcon(applianceType, screen.x, screen.y, w, d, false)}
                </g>
              )
            })}

            {/* Walls */}
            {walls.map((wall, idx) => {
              const id = `wall-${idx}`
              const isHovered = hoveredObject === id
              const isSelected = selectedObject?.data?.id === wall.id

              if (!wall.start || !wall.end) return null

              const start = toScreen(wall.start.x, wall.start.z)
              const end = toScreen(wall.end.x, wall.end.z)
              const lengthFt = wall.width_ft || wall.linear_ft || 0

              return (
                <g key={id}>
                  {/* Wall shadow for depth */}
                  <line
                    x1={start.x + 2}
                    y1={start.y + 2}
                    x2={end.x + 2}
                    y2={end.y + 2}
                    stroke="rgba(0,0,0,0.1)"
                    strokeWidth={8}
                    strokeLinecap="round"
                    className="pointer-events-none"
                  />
                  {/* Main wall */}
                  <line
                    x1={start.x}
                    y1={start.y}
                    x2={end.x}
                    y2={end.y}
                    stroke={isSelected ? '#1e40af' : isHovered ? '#3b82f6' : '#1f2937'}
                    strokeWidth={isSelected ? 8 : isHovered ? 7 : 6}
                    strokeLinecap="round"
                    className="cursor-pointer"
                    style={{ transition: 'stroke 0.2s ease-out, stroke-width 0.2s ease-out' }}
                    onMouseEnter={(e) => handleHover(e, id, `Wall: ${formatFeetInches(lengthFt)} x ${formatFeetInches(wall.height_ft)}`)}
                    onMouseLeave={handleHoverEnd}
                    onClick={() => setSelectedObject({ type: 'wall', data: wall, label: `Wall ${idx + 1}` })}
                  />
                </g>
              )
            })}

            {/* Wall labels with collision avoidance */}
            {wallLabels.map((label) => (
              <g key={label.id}>
                <rect
                  x={label.x - label.width / 2}
                  y={label.y - label.height / 2}
                  width={label.width}
                  height={label.height}
                  fill="white"
                  fillOpacity="0.95"
                  rx="4"
                  filter="url(#dropShadow)"
                  transform={`rotate(${label.rotation}, ${label.x}, ${label.y})`}
                  className="pointer-events-none"
                />
                <text
                  x={label.x}
                  y={label.y}
                  textAnchor="middle"
                  dominantBaseline="middle"
                  fontSize="11"
                  fontWeight="600"
                  fill="#1f2937"
                  transform={`rotate(${label.rotation}, ${label.x}, ${label.y})`}
                  className="pointer-events-none"
                >
                  {label.text}
                </text>
              </g>
            ))}

            {/* Upper Cabinets (dashed purple outline with subtle fill) */}
            {upperCabinets.map((cabinet, idx) => {
              const id = `cabinet-upper-${idx}`
              const isHovered = hoveredObject === id
              const isSelected = selectedObject?.data?.id === cabinet.id

              if (cabinet.corners && cabinet.corners.length >= 4) {
                const screenCorners = cabinet.corners.map(c => toScreen(c.x, c.z))
                const points = screenCorners.map(s => `${s.x},${s.y}`).join(' ')

                const centerX = screenCorners.reduce((sum, c) => sum + c.x, 0) / screenCorners.length
                const centerY = screenCorners.reduce((sum, c) => sum + c.y, 0) / screenCorners.length

                return (
                  <g key={id} filter={isHovered || isSelected ? 'url(#dropShadow)' : undefined}>
                    <polygon
                      points={points}
                      fill={isSelected ? 'rgba(139, 92, 246, 0.15)' : isHovered ? 'rgba(139, 92, 246, 0.1)' : 'rgba(139, 92, 246, 0.05)'}
                      stroke={isSelected ? '#7c3aed' : isHovered ? '#8b5cf6' : '#a78bfa'}
                      strokeWidth={isSelected ? 2.5 : isHovered ? 2 : 1.5}
                      strokeDasharray="6,3"
                      className="cursor-pointer"
                      style={{ transition: 'all 0.2s ease-out' }}
                      onMouseEnter={(e) => handleHover(e, id, `Upper Cabinet: ${formatInches(cabinet.width_ft)} x ${formatInches(cabinet.depth_ft)}`)}
                      onMouseLeave={handleHoverEnd}
                      onClick={() => setSelectedObject({ type: 'cabinet', data: cabinet, label: 'Upper Cabinet' })}
                    />
                    {showLabels && (
                      <text
                        x={centerX}
                        y={centerY}
                        textAnchor="middle"
                        dominantBaseline="middle"
                        fontSize="8"
                        fill="#7c3aed"
                        className="pointer-events-none font-medium"
                        style={{ transition: 'opacity 0.2s' }}
                      >
                        U
                      </text>
                    )}
                  </g>
                )
              }

              const screen = toScreen(cabinet.position.x, cabinet.position.z)
              const w = cabinet.width_ft * viewConfig.scale
              const d = cabinet.depth_ft * viewConfig.scale

              return (
                <g key={id} filter={isHovered || isSelected ? 'url(#dropShadow)' : undefined}>
                  <rect
                    x={screen.x - w / 2}
                    y={screen.y - d / 2}
                    width={w}
                    height={d}
                    fill={isSelected ? 'rgba(139, 92, 246, 0.15)' : isHovered ? 'rgba(139, 92, 246, 0.1)' : 'rgba(139, 92, 246, 0.05)'}
                    stroke={isSelected ? '#7c3aed' : isHovered ? '#8b5cf6' : '#a78bfa'}
                    strokeWidth={isSelected ? 2.5 : isHovered ? 2 : 1.5}
                    strokeDasharray="6,3"
                    rx="2"
                    className="cursor-pointer"
                    style={{ transition: 'all 0.2s ease-out' }}
                    onMouseEnter={(e) => handleHover(e, id, `Upper Cabinet: ${formatInches(cabinet.width_ft)} x ${formatInches(cabinet.depth_ft)}`)}
                    onMouseLeave={handleHoverEnd}
                    onClick={() => setSelectedObject({ type: 'cabinet', data: cabinet, label: 'Upper Cabinet' })}
                  />
                  {showLabels && (
                    <text
                      x={screen.x}
                      y={screen.y}
                      textAnchor="middle"
                      dominantBaseline="middle"
                      fontSize="8"
                      fill="#7c3aed"
                      className="pointer-events-none font-medium"
                    >
                      U
                    </text>
                  )}
                </g>
              )
            })}

            {/* Windows */}
            {windows.map((windowItem, idx) => {
              const id = `window-${idx}`
              const isHovered = hoveredObject === id
              const isSelected = selectedObject?.data?.id === windowItem.id
              const screen = toScreen(windowItem.position.x, windowItem.position.z)
              const w = windowItem.width_ft * viewConfig.scale
              const windowColor = isSelected ? '#0284c7' : isHovered ? '#0ea5e9' : '#38bdf8'

              const nearestWall = findNearestWall(windowItem.position)
              let wallAngle = 0

              if (nearestWall && nearestWall.start && nearestWall.end) {
                const wallDx = nearestWall.end.x - nearestWall.start.x
                const wallDz = nearestWall.end.z - nearestWall.start.z
                wallAngle = Math.atan2(wallDz, wallDx)
              }

              const totalAngle = (wallAngle * 180 / Math.PI) + rotation

              return (
                <g key={id} transform={`rotate(${totalAngle}, ${screen.x}, ${screen.y})`}>
                  <line
                    x1={screen.x - w / 2}
                    y1={screen.y - 3}
                    x2={screen.x + w / 2}
                    y2={screen.y - 3}
                    stroke={windowColor}
                    strokeWidth={isSelected ? 4 : isHovered ? 3.5 : 3}
                    className="cursor-pointer"
                    style={{ transition: 'all 0.2s ease-out' }}
                    onMouseEnter={(e) => handleHover(e, id, `Window: ${formatFeetInches(windowItem.width_ft)} wide`)}
                    onMouseLeave={handleHoverEnd}
                    onClick={() => setSelectedObject({ type: 'window', data: windowItem, label: 'Window' })}
                  />
                  <line
                    x1={screen.x - w / 2}
                    y1={screen.y + 3}
                    x2={screen.x + w / 2}
                    y2={screen.y + 3}
                    stroke={windowColor}
                    strokeWidth={isSelected ? 4 : isHovered ? 3.5 : 3}
                    className="cursor-pointer"
                    style={{ transition: 'all 0.2s ease-out' }}
                    onMouseEnter={(e) => handleHover(e, id, `Window: ${formatFeetInches(windowItem.width_ft)} wide`)}
                    onMouseLeave={handleHoverEnd}
                    onClick={() => setSelectedObject({ type: 'window', data: windowItem, label: 'Window' })}
                  />
                </g>
              )
            })}

            {/* Doors */}
            {doors.map((door, idx) => {
              const id = `door-${idx}`
              const isHovered = hoveredObject === id
              const isSelected = selectedObject?.data?.id === door.id
              const screen = toScreen(door.position.x, door.position.z)
              const w = door.width_ft * viewConfig.scale
              const doorColor = isSelected ? '#374151' : isHovered ? '#6b7280' : '#4b5563'

              const nearestWall = findNearestWall(door.position)
              let wallAngle = 0

              if (nearestWall && nearestWall.start && nearestWall.end) {
                const wallDx = nearestWall.end.x - nearestWall.start.x
                const wallDz = nearestWall.end.z - nearestWall.start.z
                wallAngle = Math.atan2(wallDz, wallDx)
              }

              const totalAngle = (wallAngle * 180 / Math.PI) + rotation

              return (
                <g key={id} transform={`rotate(${totalAngle}, ${screen.x}, ${screen.y})`}>
                  {/* Gap in wall */}
                  <rect
                    x={screen.x - w / 2}
                    y={screen.y - 4}
                    width={w}
                    height={8}
                    fill="#fafafa"
                    className="pointer-events-none"
                  />
                  {/* Door leaf */}
                  <line
                    x1={screen.x - w / 2}
                    y1={screen.y}
                    x2={screen.x + w / 2 - 2}
                    y2={screen.y}
                    stroke={doorColor}
                    strokeWidth={isSelected ? 3 : isHovered ? 2.5 : 2}
                    className="cursor-pointer"
                    style={{ transition: 'all 0.2s ease-out' }}
                    onMouseEnter={(e) => handleHover(e, id, `Door: ${formatFeetInches(door.width_ft)} wide`)}
                    onMouseLeave={handleHoverEnd}
                    onClick={() => setSelectedObject({ type: 'door', data: door, label: 'Door' })}
                  />
                  {/* Swing arc */}
                  <path
                    d={`M ${screen.x + w / 2 - 2} ${screen.y} A ${w - 2} ${w - 2} 0 0 0 ${screen.x - w / 2} ${screen.y - w + 2}`}
                    fill="none"
                    stroke={doorColor}
                    strokeWidth={1}
                    strokeDasharray="3,2"
                    className="pointer-events-none"
                  />
                  <circle cx={screen.x - w / 2} cy={screen.y} r="2" fill={doorColor} />
                </g>
              )
            })}

            {/* Room info card */}
            <g filter="url(#dropShadow)">
              <rect x="12" y="12" width="110" height="50" fill="white" stroke="#e5e7eb" rx="8" />
              <text x="20" y="32" fontSize="14" fontWeight="bold" fill="#374151">Kitchen</text>
              {roomArea && (
                <text x="20" y="50" fontSize="12" fill="#6b7280">{roomArea} sq ft</text>
              )}
            </g>

            {/* Compass indicator */}
            <g transform={`translate(${viewWidth - 50}, 50)`}>
              <circle cx="0" cy="0" r="28" fill="white" stroke="#e5e7eb" strokeWidth="1" filter="url(#dropShadow)" />
              <g transform={`rotate(${-rotation})`}>
                {/* North arrow */}
                <polygon points="0,-18 -5,-8 5,-8" fill="#ef4444" />
                <polygon points="0,18 -5,8 5,8" fill="#9ca3af" />
                <text x="0" y="-7" textAnchor="middle" fontSize="8" fontWeight="bold" fill="white">N</text>
              </g>
              <circle cx="0" cy="0" r="4" fill="#374151" />
            </g>
          </svg>

          {/* Hover tooltip */}
          {tooltipData && (
            <div
              className="absolute pointer-events-none z-40 px-3 py-2 bg-gray-900 text-white text-sm rounded-lg shadow-xl animate-in fade-in-0 duration-150"
              style={{
                left: tooltipData.x,
                top: tooltipData.y,
                transform: 'translateX(-50%)'
              }}
            >
              {tooltipData.content}
              <div
                className="absolute left-1/2 -translate-x-1/2 -bottom-1.5 w-3 h-3 bg-gray-900 rotate-45"
              />
            </div>
          )}

          {renderDetailPanel()}
        </div>
      </div>
    )
  }

  return (
    <Card className={className}>
      <CardHeader className="pb-2">
        <div className="flex items-center justify-between">
          <div>
            <CardTitle className="flex items-center gap-2">
              <Square className="h-5 w-5 text-blue-600" />
              Interactive Floor Plan
            </CardTitle>
            <CardDescription>
              Drag slider to rotate | Click elements for details | Press ? for shortcuts
            </CardDescription>
          </div>
          <div className="flex items-center gap-2">
            <Button
              variant="outline"
              size="sm"
              onClick={() => setShowLabels(!showLabels)}
              className="gap-2 transition-all duration-200"
            >
              {showLabels ? (
                <>
                  <EyeOff className="h-4 w-4" />
                  <span className="hidden sm:inline">Hide Labels</span>
                </>
              ) : (
                <>
                  <Eye className="h-4 w-4" />
                  <span className="hidden sm:inline">Show Labels</span>
                </>
              )}
            </Button>
            <Button
              variant="outline"
              size="icon"
              onClick={resetView}
              title="Reset view (R)"
              className="transition-all duration-200 hover:bg-blue-50"
            >
              <RotateCcw className="h-4 w-4" />
            </Button>
            <Button
              variant="outline"
              size="icon"
              onClick={toggleFullscreen}
              title="Fullscreen (F)"
              className="transition-all duration-200 hover:bg-blue-50"
            >
              {isFullscreen ? <Minimize2 className="h-4 w-4" /> : <Maximize2 className="h-4 w-4" />}
            </Button>
          </div>
        </div>
      </CardHeader>
      <CardContent>
        {/* Controls */}
        <div className="flex items-center gap-4 mb-4 p-3 bg-gradient-to-r from-gray-50 to-gray-100/50 rounded-xl border border-gray-100">
          <div className="flex items-center gap-2 flex-1">
            <Move className="h-4 w-4 text-gray-400" />
            <span className="text-sm text-gray-600 w-16 font-medium">Rotate:</span>
            <input
              type="range"
              min={0}
              max={360}
              step={1}
              value={targetRotation}
              onChange={(e) => setTargetRotation(Number(e.target.value))}
              className="flex-1 h-2 bg-gray-200 rounded-lg appearance-none cursor-pointer accent-blue-600"
            />
            <span className="text-sm text-gray-500 w-12 font-mono">{Math.round(rotation)}deg</span>
          </div>
          <div className="flex items-center gap-1 border-l border-gray-200 pl-4">
            <Button
              variant="ghost"
              size="icon"
              onClick={() => setTargetZoom(Math.max(0.5, targetZoom - 0.1))}
              title="Zoom out (-)"
              className="h-8 w-8 hover:bg-gray-200/50 transition-colors duration-200"
            >
              <ZoomOut className="h-4 w-4" />
            </Button>
            <span className="text-sm text-gray-500 w-12 text-center font-mono">{Math.round(zoom * 100)}%</span>
            <Button
              variant="ghost"
              size="icon"
              onClick={() => setTargetZoom(Math.min(2, targetZoom + 0.1))}
              title="Zoom in (+)"
              className="h-8 w-8 hover:bg-gray-200/50 transition-colors duration-200"
            >
              <ZoomIn className="h-4 w-4" />
            </Button>
          </div>
          <div className="flex items-center gap-1 border-l border-gray-200 pl-4">
            <Button
              variant="ghost"
              size="icon"
              onClick={exportAsPNG}
              title="Export as PNG"
              className="h-8 w-8 hover:bg-gray-200/50 transition-colors duration-200"
            >
              <Download className="h-4 w-4" />
            </Button>
            <Button
              variant="ghost"
              size="icon"
              onClick={() => setShowKeyboardHints(!showKeyboardHints)}
              title="Keyboard shortcuts (?)"
              className="h-8 w-8 hover:bg-gray-200/50 transition-colors duration-200"
            >
              <Keyboard className="h-4 w-4" />
            </Button>
          </div>
        </div>

        {/* Keyboard hints panel */}
        {showKeyboardHints && (
          <div className="mb-4 p-4 bg-gray-900 text-white rounded-xl text-sm animate-in slide-in-from-top-2 duration-200">
            <div className="flex items-center justify-between mb-3">
              <span className="font-semibold">Keyboard Shortcuts</span>
              <button
                onClick={() => setShowKeyboardHints(false)}
                className="p-1 hover:bg-gray-700 rounded"
              >
                <X className="h-4 w-4" />
              </button>
            </div>
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
              <div className="flex items-center gap-2">
                <kbd className="px-2 py-1 bg-gray-700 rounded text-xs font-mono">Arrow Left/Right</kbd>
                <span className="text-gray-300">Rotate</span>
              </div>
              <div className="flex items-center gap-2">
                <kbd className="px-2 py-1 bg-gray-700 rounded text-xs font-mono">+/-</kbd>
                <span className="text-gray-300">Zoom</span>
              </div>
              <div className="flex items-center gap-2">
                <kbd className="px-2 py-1 bg-gray-700 rounded text-xs font-mono">R</kbd>
                <span className="text-gray-300">Reset view</span>
              </div>
              <div className="flex items-center gap-2">
                <kbd className="px-2 py-1 bg-gray-700 rounded text-xs font-mono">L</kbd>
                <span className="text-gray-300">Toggle labels</span>
              </div>
              <div className="flex items-center gap-2">
                <kbd className="px-2 py-1 bg-gray-700 rounded text-xs font-mono">F</kbd>
                <span className="text-gray-300">Fullscreen</span>
              </div>
              <div className="flex items-center gap-2">
                <kbd className="px-2 py-1 bg-gray-700 rounded text-xs font-mono">Esc</kbd>
                <span className="text-gray-300">Close/Exit</span>
              </div>
            </div>
            <p className="mt-3 text-gray-400 text-xs">
              On tablets: pinch to zoom, two-finger rotate to turn
            </p>
          </div>
        )}

        <div
          ref={containerRef}
          className="relative bg-white rounded-xl border border-gray-200 overflow-hidden shadow-sm"
          onTouchStart={handleTouchStart}
          onTouchMove={handleTouchMove}
          onTouchEnd={handleTouchEnd}
          style={{ touchAction: 'none' }}
        >
          <svg
            ref={svgRef}
            viewBox={`0 0 ${viewWidth} ${viewHeight}`}
            className="w-full transition-transform duration-75"
            style={{
              height: isFullscreen ? '100vh' : 'auto',
              maxHeight: isFullscreen ? '100vh' : '500px'
            }}
            role="img"
            aria-label="Interactive floor plan showing room layout with walls, cabinets, and appliances"
          >
            {/* Gradient definitions for shadows and effects */}
            <defs>
              <pattern id="grid" width="40" height="40" patternUnits="userSpaceOnUse">
                <path d="M 40 0 L 0 0 0 40" fill="none" stroke="#e5e7eb" strokeWidth="0.5" />
              </pattern>

              {/* Drop shadow filter */}
              <filter id="dropShadow" x="-20%" y="-20%" width="140%" height="140%">
                <feDropShadow dx="0" dy="2" stdDeviation="3" floodOpacity="0.15"/>
              </filter>

              {/* Glow filter for selection */}
              <filter id="glow" x="-50%" y="-50%" width="200%" height="200%">
                <feGaussianBlur stdDeviation="3" result="coloredBlur"/>
                <feMerge>
                  <feMergeNode in="coloredBlur"/>
                  <feMergeNode in="SourceGraphic"/>
                </feMerge>
              </filter>

              {/* Cabinet gradient */}
              <linearGradient id="cabinetGradient" x1="0%" y1="0%" x2="0%" y2="100%">
                <stop offset="0%" stopColor="#fafafa"/>
                <stop offset="100%" stopColor="#f0f0f0"/>
              </linearGradient>

              {/* Selected cabinet gradient */}
              <linearGradient id="cabinetSelectedGradient" x1="0%" y1="0%" x2="0%" y2="100%">
                <stop offset="0%" stopColor="#dcfce7"/>
                <stop offset="100%" stopColor="#bbf7d0"/>
              </linearGradient>
            </defs>

            {/* Background with subtle gradient */}
            <rect width="100%" height="100%" fill="#fafafa" />
            <rect width="100%" height="100%" fill="url(#grid)" />

            {/* Lower Cabinets */}
            {lowerCabinets.map((cabinet, idx) => {
              const id = `cabinet-lower-${idx}`
              const isHovered = hoveredObject === id
              const isSelected = selectedObject?.data?.id === cabinet.id

              if (cabinet.corners && cabinet.corners.length >= 4) {
                const screenCorners = cabinet.corners.map(c => toScreen(c.x, c.z))
                const points = screenCorners.map(s => `${s.x},${s.y}`).join(' ')

                const centerX = screenCorners.reduce((sum, c) => sum + c.x, 0) / screenCorners.length
                const centerY = screenCorners.reduce((sum, c) => sum + c.y, 0) / screenCorners.length

                return (
                  <g key={id} filter={isHovered || isSelected ? 'url(#dropShadow)' : undefined}>
                    <polygon
                      points={points}
                      fill={isSelected ? 'url(#cabinetSelectedGradient)' : isHovered ? '#f0fdf4' : 'url(#cabinetGradient)'}
                      stroke={isSelected ? '#16a34a' : isHovered ? '#22c55e' : '#374151'}
                      strokeWidth={isSelected ? 2.5 : isHovered ? 2 : 1.5}
                      className="cursor-pointer"
                      style={{ transition: 'all 0.2s ease-out' }}
                      onMouseEnter={(e) => handleHover(e, id, `Lower Cabinet: ${formatInches(cabinet.width_ft)} x ${formatInches(cabinet.depth_ft)}`)}
                      onMouseLeave={handleHoverEnd}
                      onClick={() => setSelectedObject({ type: 'cabinet', data: cabinet, label: 'Lower Cabinet' })}
                    />
                    {showLabels && (
                      <text
                        x={centerX}
                        y={centerY}
                        textAnchor="middle"
                        dominantBaseline="middle"
                        fontSize="9"
                        fill="#374151"
                        className="pointer-events-none font-medium"
                        style={{ transition: 'opacity 0.2s' }}
                      >
                        {formatInches(cabinet.width_ft)}
                      </text>
                    )}
                  </g>
                )
              }

              const screen = toScreen(cabinet.position.x, cabinet.position.z)
              const w = cabinet.width_ft * viewConfig.scale
              const d = cabinet.depth_ft * viewConfig.scale

              return (
                <g key={id} filter={isHovered || isSelected ? 'url(#dropShadow)' : undefined}>
                  <rect
                    x={screen.x - w / 2}
                    y={screen.y - d / 2}
                    width={w}
                    height={d}
                    fill={isSelected ? 'url(#cabinetSelectedGradient)' : isHovered ? '#f0fdf4' : 'url(#cabinetGradient)'}
                    stroke={isSelected ? '#16a34a' : isHovered ? '#22c55e' : '#374151'}
                    strokeWidth={isSelected ? 2.5 : isHovered ? 2 : 1.5}
                    rx="2"
                    className="cursor-pointer"
                    style={{ transition: 'all 0.2s ease-out' }}
                    onMouseEnter={(e) => handleHover(e, id, `Lower Cabinet: ${formatInches(cabinet.width_ft)} x ${formatInches(cabinet.depth_ft)}`)}
                    onMouseLeave={handleHoverEnd}
                    onClick={() => setSelectedObject({ type: 'cabinet', data: cabinet, label: 'Lower Cabinet' })}
                  />
                  {showLabels && (
                    <text
                      x={screen.x}
                      y={screen.y}
                      textAnchor="middle"
                      dominantBaseline="middle"
                      fontSize="9"
                      fill="#374151"
                      className="pointer-events-none font-medium"
                    >
                      {formatInches(cabinet.width_ft)}
                    </text>
                  )}
                </g>
              )
            })}

            {/* Appliances */}
            {appliances.map((appliance, idx) => {
              const id = `appliance-${idx}`
              const isHovered = hoveredObject === id
              const isSelected = selectedObject?.data?.id === appliance.id
              const applianceType = appliance.type || 'Appliance'

              if (appliance.corners && appliance.corners.length >= 4) {
                const screenCorners = appliance.corners.map(c => toScreen(c.x, c.z))
                const points = screenCorners.map(s => `${s.x},${s.y}`).join(' ')

                const centerX = screenCorners.reduce((sum, c) => sum + c.x, 0) / screenCorners.length
                const centerY = screenCorners.reduce((sum, c) => sum + c.y, 0) / screenCorners.length

                const xs = screenCorners.map(c => c.x)
                const ys = screenCorners.map(c => c.y)
                const boxWidth = Math.max(...xs) - Math.min(...xs)
                const boxHeight = Math.max(...ys) - Math.min(...ys)

                return (
                  <g key={id} filter={isHovered || isSelected ? 'url(#dropShadow)' : undefined}>
                    <polygon
                      points={points}
                      fill={isSelected ? '#fef3c7' : isHovered ? '#fffbeb' : '#fffef5'}
                      stroke={isSelected ? '#d97706' : isHovered ? '#f59e0b' : '#f59e0b'}
                      strokeWidth={isSelected ? 2.5 : isHovered ? 2 : 1.5}
                      className="cursor-pointer"
                      style={{ transition: 'all 0.2s ease-out' }}
                      onMouseEnter={(e) => handleHover(e, id, `${applianceType}: ${formatInches(appliance.width_ft)} x ${formatInches(appliance.depth_ft)}`)}
                      onMouseLeave={handleHoverEnd}
                      onClick={() => setSelectedObject({ type: 'appliance', data: appliance, label: applianceType })}
                    />
                    {renderApplianceIcon(applianceType, centerX, centerY, boxWidth, boxHeight, false)}
                  </g>
                )
              }

              const screen = toScreen(appliance.position.x, appliance.position.z)
              const w = appliance.width_ft * viewConfig.scale
              const d = appliance.depth_ft * viewConfig.scale

              return (
                <g key={id} filter={isHovered || isSelected ? 'url(#dropShadow)' : undefined}>
                  <rect
                    x={screen.x - w / 2}
                    y={screen.y - d / 2}
                    width={w}
                    height={d}
                    fill={isSelected ? '#fef3c7' : isHovered ? '#fffbeb' : '#fffef5'}
                    stroke={isSelected ? '#d97706' : isHovered ? '#f59e0b' : '#f59e0b'}
                    strokeWidth={isSelected ? 2.5 : isHovered ? 2 : 1.5}
                    rx="2"
                    className="cursor-pointer"
                    style={{ transition: 'all 0.2s ease-out' }}
                    onMouseEnter={(e) => handleHover(e, id, `${applianceType}: ${formatInches(appliance.width_ft)} x ${formatInches(appliance.depth_ft)}`)}
                    onMouseLeave={handleHoverEnd}
                    onClick={() => setSelectedObject({ type: 'appliance', data: appliance, label: applianceType })}
                  />
                  {renderApplianceIcon(applianceType, screen.x, screen.y, w, d, false)}
                </g>
              )
            })}

            {/* Walls */}
            {walls.map((wall, idx) => {
              const id = `wall-${idx}`
              const isHovered = hoveredObject === id
              const isSelected = selectedObject?.data?.id === wall.id

              if (!wall.start || !wall.end) return null

              const start = toScreen(wall.start.x, wall.start.z)
              const end = toScreen(wall.end.x, wall.end.z)
              const lengthFt = wall.width_ft || wall.linear_ft || 0

              return (
                <g key={id}>
                  {/* Wall shadow for depth */}
                  <line
                    x1={start.x + 2}
                    y1={start.y + 2}
                    x2={end.x + 2}
                    y2={end.y + 2}
                    stroke="rgba(0,0,0,0.1)"
                    strokeWidth={8}
                    strokeLinecap="round"
                    className="pointer-events-none"
                  />
                  {/* Main wall */}
                  <line
                    x1={start.x}
                    y1={start.y}
                    x2={end.x}
                    y2={end.y}
                    stroke={isSelected ? '#1e40af' : isHovered ? '#3b82f6' : '#1f2937'}
                    strokeWidth={isSelected ? 8 : isHovered ? 7 : 6}
                    strokeLinecap="round"
                    className="cursor-pointer"
                    style={{ transition: 'stroke 0.2s ease-out, stroke-width 0.2s ease-out' }}
                    onMouseEnter={(e) => handleHover(e, id, `Wall: ${formatFeetInches(lengthFt)} x ${formatFeetInches(wall.height_ft)}`)}
                    onMouseLeave={handleHoverEnd}
                    onClick={() => setSelectedObject({ type: 'wall', data: wall, label: `Wall ${idx + 1}` })}
                  />
                </g>
              )
            })}

            {/* Wall labels with collision avoidance */}
            {wallLabels.map((label) => (
              <g key={label.id}>
                <rect
                  x={label.x - label.width / 2}
                  y={label.y - label.height / 2}
                  width={label.width}
                  height={label.height}
                  fill="white"
                  fillOpacity="0.95"
                  rx="4"
                  filter="url(#dropShadow)"
                  transform={`rotate(${label.rotation}, ${label.x}, ${label.y})`}
                  className="pointer-events-none"
                />
                <text
                  x={label.x}
                  y={label.y}
                  textAnchor="middle"
                  dominantBaseline="middle"
                  fontSize="11"
                  fontWeight="600"
                  fill="#1f2937"
                  transform={`rotate(${label.rotation}, ${label.x}, ${label.y})`}
                  className="pointer-events-none"
                >
                  {label.text}
                </text>
              </g>
            ))}

            {/* Upper Cabinets (dashed purple outline with subtle fill) */}
            {upperCabinets.map((cabinet, idx) => {
              const id = `cabinet-upper-${idx}`
              const isHovered = hoveredObject === id
              const isSelected = selectedObject?.data?.id === cabinet.id

              if (cabinet.corners && cabinet.corners.length >= 4) {
                const screenCorners = cabinet.corners.map(c => toScreen(c.x, c.z))
                const points = screenCorners.map(s => `${s.x},${s.y}`).join(' ')

                const centerX = screenCorners.reduce((sum, c) => sum + c.x, 0) / screenCorners.length
                const centerY = screenCorners.reduce((sum, c) => sum + c.y, 0) / screenCorners.length

                return (
                  <g key={id} filter={isHovered || isSelected ? 'url(#dropShadow)' : undefined}>
                    <polygon
                      points={points}
                      fill={isSelected ? 'rgba(139, 92, 246, 0.15)' : isHovered ? 'rgba(139, 92, 246, 0.1)' : 'rgba(139, 92, 246, 0.05)'}
                      stroke={isSelected ? '#7c3aed' : isHovered ? '#8b5cf6' : '#a78bfa'}
                      strokeWidth={isSelected ? 2.5 : isHovered ? 2 : 1.5}
                      strokeDasharray="6,3"
                      className="cursor-pointer"
                      style={{ transition: 'all 0.2s ease-out' }}
                      onMouseEnter={(e) => handleHover(e, id, `Upper Cabinet: ${formatInches(cabinet.width_ft)} x ${formatInches(cabinet.depth_ft)}`)}
                      onMouseLeave={handleHoverEnd}
                      onClick={() => setSelectedObject({ type: 'cabinet', data: cabinet, label: 'Upper Cabinet' })}
                    />
                    {showLabels && (
                      <text
                        x={centerX}
                        y={centerY}
                        textAnchor="middle"
                        dominantBaseline="middle"
                        fontSize="8"
                        fill="#7c3aed"
                        className="pointer-events-none font-medium"
                        style={{ transition: 'opacity 0.2s' }}
                      >
                        U
                      </text>
                    )}
                  </g>
                )
              }

              const screen = toScreen(cabinet.position.x, cabinet.position.z)
              const w = cabinet.width_ft * viewConfig.scale
              const d = cabinet.depth_ft * viewConfig.scale

              return (
                <g key={id} filter={isHovered || isSelected ? 'url(#dropShadow)' : undefined}>
                  <rect
                    x={screen.x - w / 2}
                    y={screen.y - d / 2}
                    width={w}
                    height={d}
                    fill={isSelected ? 'rgba(139, 92, 246, 0.15)' : isHovered ? 'rgba(139, 92, 246, 0.1)' : 'rgba(139, 92, 246, 0.05)'}
                    stroke={isSelected ? '#7c3aed' : isHovered ? '#8b5cf6' : '#a78bfa'}
                    strokeWidth={isSelected ? 2.5 : isHovered ? 2 : 1.5}
                    strokeDasharray="6,3"
                    rx="2"
                    className="cursor-pointer"
                    style={{ transition: 'all 0.2s ease-out' }}
                    onMouseEnter={(e) => handleHover(e, id, `Upper Cabinet: ${formatInches(cabinet.width_ft)} x ${formatInches(cabinet.depth_ft)}`)}
                    onMouseLeave={handleHoverEnd}
                    onClick={() => setSelectedObject({ type: 'cabinet', data: cabinet, label: 'Upper Cabinet' })}
                  />
                  {showLabels && (
                    <text
                      x={screen.x}
                      y={screen.y}
                      textAnchor="middle"
                      dominantBaseline="middle"
                      fontSize="8"
                      fill="#7c3aed"
                      className="pointer-events-none font-medium"
                    >
                      U
                    </text>
                  )}
                </g>
              )
            })}

            {/* Windows */}
            {windows.map((windowItem, idx) => {
              const id = `window-${idx}`
              const isHovered = hoveredObject === id
              const isSelected = selectedObject?.data?.id === windowItem.id
              const screen = toScreen(windowItem.position.x, windowItem.position.z)
              const w = windowItem.width_ft * viewConfig.scale
              const windowColor = isSelected ? '#0284c7' : isHovered ? '#0ea5e9' : '#38bdf8'

              const nearestWall = findNearestWall(windowItem.position)
              let wallAngle = 0

              if (nearestWall && nearestWall.start && nearestWall.end) {
                const wallDx = nearestWall.end.x - nearestWall.start.x
                const wallDz = nearestWall.end.z - nearestWall.start.z
                wallAngle = Math.atan2(wallDz, wallDx)
              }

              const totalAngle = (wallAngle * 180 / Math.PI) + rotation

              return (
                <g key={id} transform={`rotate(${totalAngle}, ${screen.x}, ${screen.y})`}>
                  <line
                    x1={screen.x - w / 2}
                    y1={screen.y - 3}
                    x2={screen.x + w / 2}
                    y2={screen.y - 3}
                    stroke={windowColor}
                    strokeWidth={isSelected ? 4 : isHovered ? 3.5 : 3}
                    className="cursor-pointer"
                    style={{ transition: 'all 0.2s ease-out' }}
                    onMouseEnter={(e) => handleHover(e, id, `Window: ${formatFeetInches(windowItem.width_ft)} wide`)}
                    onMouseLeave={handleHoverEnd}
                    onClick={() => setSelectedObject({ type: 'window', data: windowItem, label: 'Window' })}
                  />
                  <line
                    x1={screen.x - w / 2}
                    y1={screen.y + 3}
                    x2={screen.x + w / 2}
                    y2={screen.y + 3}
                    stroke={windowColor}
                    strokeWidth={isSelected ? 4 : isHovered ? 3.5 : 3}
                    className="cursor-pointer"
                    style={{ transition: 'all 0.2s ease-out' }}
                    onMouseEnter={(e) => handleHover(e, id, `Window: ${formatFeetInches(windowItem.width_ft)} wide`)}
                    onMouseLeave={handleHoverEnd}
                    onClick={() => setSelectedObject({ type: 'window', data: windowItem, label: 'Window' })}
                  />
                </g>
              )
            })}

            {/* Doors */}
            {doors.map((door, idx) => {
              const id = `door-${idx}`
              const isHovered = hoveredObject === id
              const isSelected = selectedObject?.data?.id === door.id
              const screen = toScreen(door.position.x, door.position.z)
              const w = door.width_ft * viewConfig.scale
              const doorColor = isSelected ? '#374151' : isHovered ? '#6b7280' : '#4b5563'

              const nearestWall = findNearestWall(door.position)
              let wallAngle = 0

              if (nearestWall && nearestWall.start && nearestWall.end) {
                const wallDx = nearestWall.end.x - nearestWall.start.x
                const wallDz = nearestWall.end.z - nearestWall.start.z
                wallAngle = Math.atan2(wallDz, wallDx)
              }

              const totalAngle = (wallAngle * 180 / Math.PI) + rotation

              return (
                <g key={id} transform={`rotate(${totalAngle}, ${screen.x}, ${screen.y})`}>
                  {/* Gap in wall */}
                  <rect
                    x={screen.x - w / 2}
                    y={screen.y - 4}
                    width={w}
                    height={8}
                    fill="#fafafa"
                    className="pointer-events-none"
                  />
                  {/* Door leaf */}
                  <line
                    x1={screen.x - w / 2}
                    y1={screen.y}
                    x2={screen.x + w / 2 - 2}
                    y2={screen.y}
                    stroke={doorColor}
                    strokeWidth={isSelected ? 3 : isHovered ? 2.5 : 2}
                    className="cursor-pointer"
                    style={{ transition: 'all 0.2s ease-out' }}
                    onMouseEnter={(e) => handleHover(e, id, `Door: ${formatFeetInches(door.width_ft)} wide`)}
                    onMouseLeave={handleHoverEnd}
                    onClick={() => setSelectedObject({ type: 'door', data: door, label: 'Door' })}
                  />
                  {/* Swing arc */}
                  <path
                    d={`M ${screen.x + w / 2 - 2} ${screen.y} A ${w - 2} ${w - 2} 0 0 0 ${screen.x - w / 2} ${screen.y - w + 2}`}
                    fill="none"
                    stroke={doorColor}
                    strokeWidth={1}
                    strokeDasharray="3,2"
                    className="pointer-events-none"
                  />
                  <circle cx={screen.x - w / 2} cy={screen.y} r="2" fill={doorColor} />
                </g>
              )
            })}

            {/* Room info card */}
            <g filter="url(#dropShadow)">
              <rect x="12" y="12" width="110" height="50" fill="white" stroke="#e5e7eb" rx="8" />
              <text x="20" y="32" fontSize="14" fontWeight="bold" fill="#374151">Kitchen</text>
              {roomArea && (
                <text x="20" y="50" fontSize="12" fill="#6b7280">{roomArea} sq ft</text>
              )}
            </g>

            {/* Compass indicator */}
            <g transform={`translate(${viewWidth - 50}, 50)`}>
              <circle cx="0" cy="0" r="28" fill="white" stroke="#e5e7eb" strokeWidth="1" filter="url(#dropShadow)" />
              <g transform={`rotate(${-rotation})`}>
                {/* North arrow */}
                <polygon points="0,-18 -5,-8 5,-8" fill="#ef4444" />
                <polygon points="0,18 -5,8 5,8" fill="#9ca3af" />
                <text x="0" y="-7" textAnchor="middle" fontSize="8" fontWeight="bold" fill="white">N</text>
              </g>
              <circle cx="0" cy="0" r="4" fill="#374151" />
            </g>

            {/* Compact Legend */}
            <g transform={`translate(${viewWidth - 120}, ${viewHeight - 125})`} filter="url(#dropShadow)">
              <rect x="0" y="0" width="110" height="115" fill="white" stroke="#e5e7eb" rx="8" />
              <text x="10" y="18" fontSize="11" fontWeight="600" fill="#374151">Legend</text>

              <line x1="10" y1="32" x2="32" y2="32" stroke="#1f2937" strokeWidth="4" strokeLinecap="round" />
              <text x="38" y="36" fontSize="10" fill="#6b7280">Wall</text>

              <rect x="10" y="44" width="22" height="12" fill="url(#cabinetGradient)" stroke="#374151" strokeWidth="1" rx="2" />
              <text x="38" y="53" fontSize="10" fill="#6b7280">Lower Cab</text>

              <rect x="10" y="62" width="22" height="12" fill="rgba(139,92,246,0.1)" stroke="#a78bfa" strokeWidth="1" strokeDasharray="4,2" rx="2" />
              <text x="38" y="71" fontSize="10" fill="#6b7280">Upper Cab</text>

              <rect x="10" y="80" width="22" height="12" fill="white" stroke="#f59e0b" strokeWidth="1" rx="2" />
              <text x="38" y="89" fontSize="10" fill="#6b7280">Appliance</text>

              <line x1="10" y1="102" x2="32" y2="102" stroke="#38bdf8" strokeWidth="2" />
              <text x="38" y="106" fontSize="10" fill="#6b7280">Window</text>
            </g>
          </svg>

          {/* Hover tooltip */}
          {tooltipData && (
            <div
              className="absolute pointer-events-none z-40 px-3 py-2 bg-gray-900 text-white text-sm rounded-lg shadow-xl animate-in fade-in-0 duration-150"
              style={{
                left: tooltipData.x,
                top: tooltipData.y,
                transform: 'translateX(-50%)'
              }}
            >
              {tooltipData.content}
              <div
                className="absolute left-1/2 -translate-x-1/2 -bottom-1.5 w-3 h-3 bg-gray-900 rotate-45"
              />
            </div>
          )}

          {renderDetailPanel()}
        </div>

        {/* Bottom status bar - moved outside SVG container */}
        <div className="flex items-center justify-between text-xs bg-gray-50 px-4 py-2 rounded-lg mt-2 border border-gray-100">
          <span className="text-gray-500">
            <span className="hidden sm:inline">Click elements for details</span>
            <span className="sm:hidden">Tap for details</span>
          </span>
          <div className="flex items-center gap-3">
            <span className="text-gray-500 font-medium">
              {walls.length} walls
            </span>
            <span className="text-gray-300">|</span>
            <span className="text-gray-500 font-medium">
              {lowerCabinets.length} lower + {upperCabinets.length} upper cabinets
            </span>
            {appliances.length > 0 && (
              <>
                <span className="text-gray-300">|</span>
                <span className="text-gray-500 font-medium">
                  {appliances.length} appliances
                </span>
              </>
            )}
          </div>
        </div>

        {/* Export options dropdown */}
        <div className="mt-3 flex items-center justify-end gap-2">
          <span className="text-xs text-gray-400 mr-2">Export:</span>
          <Button
            variant="outline"
            size="sm"
            onClick={exportAsPNG}
            className="text-xs h-7 gap-1.5"
          >
            <Download className="h-3 w-3" />
            PNG
          </Button>
          <Button
            variant="outline"
            size="sm"
            onClick={exportAsSVG}
            className="text-xs h-7 gap-1.5"
          >
            <Download className="h-3 w-3" />
            SVG
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}
