'use client'

import { useState, useMemo } from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Separator } from '@/components/ui/separator'
import { ZoomIn, ZoomOut, Maximize2, Layers, Download, Info } from 'lucide-react'
import { exportFloorPlanToDXF } from '@/lib/export/dxf-generator'

interface FloorPlanViewerProps {
  measurements: any
}

// Layer visibility state type
interface LayerVisibility {
  walls: boolean
  doors: boolean
  windows: boolean
  lowerCabinets: boolean
  upperCabinets: boolean
  appliances: boolean
  countertops: boolean
}

export function FloorPlanViewer({ measurements }: FloorPlanViewerProps) {
  const [selectedObject, setSelectedObject] = useState<any>(null)
  const [hoveredObject, setHoveredObject] = useState<any>(null)
  const [zoom, setZoom] = useState(1)
  const [showGrid, setShowGrid] = useState(true)
  const [showLabels, setShowLabels] = useState(true)

  // Layer visibility controls
  const [layers, setLayers] = useState<LayerVisibility>({
    walls: true,
    doors: true,
    windows: true,
    lowerCabinets: true,
    upperCabinets: true,
    appliances: true,
    countertops: true,
  })

  if (!measurements || !measurements.room) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>2D Floor Plan</CardTitle>
          <CardDescription>No detailed measurements available</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex flex-col items-center justify-center py-8 text-center">
            <div className="w-16 h-16 rounded-full bg-gray-100 flex items-center justify-center mb-4">
              <Layers className="h-8 w-8 text-gray-400" />
            </div>
            <h3 className="text-lg font-medium text-gray-900 mb-2">No Floor Plan Data</h3>
            <p className="text-gray-500 max-w-md">
              This scan does not contain detailed spatial data. Please rescan the room with the latest app version.
            </p>
          </div>
        </CardContent>
      </Card>
    )
  }

  const {
    room,
    walls = [],
    doors = [],
    windows = [],
    cabinets = { upper: [], lower: [] },
    appliances = [],
    countertops = [],
    countertop_summary = { total_area_sqft: 0, total_linear_ft: 0, count: 0 }
  } = measurements

  // Calculate element counts for legend
  const elementCounts = useMemo(() => ({
    walls: walls.length,
    doors: doors.length,
    windows: windows.length,
    lowerCabinets: cabinets.lower?.length || 0,
    upperCabinets: cabinets.upper?.length || 0,
    appliances: appliances.length,
    countertops: countertops.length,
  }), [walls, doors, windows, cabinets, appliances, countertops])

  // Calculate scale factor to fit room in viewport
  const roomWidth = room.max_x - room.min_x
  const roomDepth = room.max_z - room.min_z
  const viewportWidth = 800
  const viewportHeight = 600
  const padding = 50

  const scaleX = (viewportWidth - padding * 2) / roomWidth
  const scaleZ = (viewportHeight - padding * 2) / roomDepth
  const baseScale = Math.min(scaleX, scaleZ)
  const scale = baseScale * zoom

  // Transform world coordinates to SVG coordinates
  const toSVG = (x: number, z: number) => {
    const svgX = (x - room.min_x) * scale + padding
    const svgZ = (z - room.min_z) * scale + padding
    return { x: svgX, y: svgZ }
  }

  // Handle zoom
  const handleZoomIn = () => setZoom(Math.min(zoom * 1.2, 3))
  const handleZoomOut = () => setZoom(Math.max(zoom / 1.2, 0.5))
  const handleFit = () => setZoom(1)

  // Handle export to DXF
  const handleExportDXF = () => {
    try {
      exportFloorPlanToDXF(measurements, 'Floor_Plan')
    } catch (error) {
      console.error('Error exporting DXF:', error)
      alert('Failed to export DXF file. Please try again.')
    }
  }

  // Toggle layer visibility
  const toggleLayer = (layer: keyof LayerVisibility) => {
    setLayers(prev => ({ ...prev, [layer]: !prev[layer] }))
  }

  // Format dimensions
  const formatDimension = (ft: number) => {
    const wholeFeet = Math.floor(ft)
    const inches = Math.round((ft - wholeFeet) * 12)
    return `${wholeFeet}' ${inches}"`
  }

  // Check if an object is hovered or selected
  const isHighlighted = (obj: any) =>
    selectedObject?.id === obj.id || hoveredObject?.id === obj.id

  return (
    <div className="space-y-4">
      {/* Toolbar */}
      <div className="flex items-center justify-between flex-wrap gap-2">
        <div className="flex items-center gap-2">
          <Button variant="outline" size="sm" onClick={handleZoomOut}>
            <ZoomOut className="h-4 w-4" />
          </Button>
          <Button variant="outline" size="sm" onClick={handleZoomIn}>
            <ZoomIn className="h-4 w-4" />
          </Button>
          <Button variant="outline" size="sm" onClick={handleFit}>
            <Maximize2 className="h-4 w-4" />
            <span className="ml-2">Fit</span>
          </Button>
          <Separator orientation="vertical" className="h-6" />
          <Button
            variant={showGrid ? 'default' : 'outline'}
            size="sm"
            onClick={() => setShowGrid(!showGrid)}
          >
            <Layers className="h-4 w-4" />
            <span className="ml-2">Grid</span>
          </Button>
          <Button
            variant={showLabels ? 'default' : 'outline'}
            size="sm"
            onClick={() => setShowLabels(!showLabels)}
          >
            Labels
          </Button>
        </div>
        <div className="flex items-center gap-2">
          <div className="text-sm text-gray-500">
            Room: {roomWidth.toFixed(1)}' x {roomDepth.toFixed(1)}' | Ceiling: {room.ceiling_height_ft?.toFixed(1)}'
            {countertop_summary.total_area_sqft > 0 && (
              <> | Countertop: {countertop_summary.total_area_sqft.toFixed(1)} sq ft</>
            )}
          </div>
          <Separator orientation="vertical" className="h-6" />
          <Button variant="outline" size="sm" onClick={handleExportDXF}>
            <Download className="h-4 w-4" />
            <span className="ml-2">Export DXF</span>
          </Button>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-[1fr_300px] gap-4">
        {/* Floor Plan Canvas */}
        <Card>
          <CardContent className="p-4">
            <svg
              viewBox={`0 0 ${viewportWidth} ${viewportHeight}`}
              className="w-full h-auto border border-gray-200 rounded bg-white"
              style={{ minHeight: '600px' }}
            >
              {/* Grid Background */}
              {showGrid && (
                <g className="grid-lines" opacity="0.08">
                  {Array.from({ length: 20 }).map((_, i) => (
                    <line
                      key={`h-${i}`}
                      x1="0"
                      y1={i * 30}
                      x2={viewportWidth}
                      y2={i * 30}
                      stroke="#9CA3AF"
                      strokeWidth="1"
                    />
                  ))}
                  {Array.from({ length: 20 }).map((_, i) => (
                    <line
                      key={`v-${i}`}
                      x1={i * 40}
                      y1="0"
                      x2={i * 40}
                      y2={viewportHeight}
                      stroke="#9CA3AF"
                      strokeWidth="1"
                    />
                  ))}
                </g>
              )}

              {/* Countertops - Rendered first (bottom layer) with reduced opacity */}
              {layers.countertops && countertops.map((countertop: any) => {
                const pos = toSVG(countertop.position.x, countertop.position.z)
                const width = countertop.width_ft * scale
                const depth = countertop.depth_ft * scale
                const highlighted = isHighlighted(countertop)

                return (
                  <g
                    key={countertop.id}
                    className="countertop-group cursor-pointer"
                    onClick={() => setSelectedObject(countertop)}
                    onMouseEnter={() => setHoveredObject(countertop)}
                    onMouseLeave={() => setHoveredObject(null)}
                  >
                    <rect
                      x={pos.x - width / 2}
                      y={pos.y - depth / 2}
                      width={width}
                      height={depth}
                      fill={highlighted ? '#A7F3D0' : '#D1FAE5'}
                      stroke={highlighted ? '#059669' : '#34D399'}
                      strokeWidth={highlighted ? 2 : 1}
                      opacity={highlighted ? 0.7 : 0.35}
                      className="transition-all duration-150"
                    />
                    {/* Only show CT label on hover/selection, not always */}
                    {highlighted && showLabels && (
                      <text
                        x={pos.x}
                        y={pos.y + 4}
                        textAnchor="middle"
                        className="text-xs fill-emerald-800 font-semibold pointer-events-none"
                        style={{ fontSize: '10px' }}
                      >
                        CT
                      </text>
                    )}
                  </g>
                )
              })}

              {/* Lower Cabinets - With subtle pattern fill */}
              {layers.lowerCabinets && cabinets.lower?.map((cabinet: any) => {
                const pos = toSVG(cabinet.position.x, cabinet.position.z)
                const width = cabinet.width_ft * scale
                const depth = cabinet.depth_ft * scale
                const highlighted = isHighlighted(cabinet)

                return (
                  <g
                    key={cabinet.id}
                    className="cabinet-group cursor-pointer"
                    onClick={() => setSelectedObject(cabinet)}
                    onMouseEnter={() => setHoveredObject(cabinet)}
                    onMouseLeave={() => setHoveredObject(null)}
                  >
                    <rect
                      x={pos.x - width / 2}
                      y={pos.y - depth / 2}
                      width={width}
                      height={depth}
                      fill={highlighted ? '#BFDBFE' : '#D1D5DB'}
                      stroke={highlighted ? '#2563EB' : '#4B5563'}
                      strokeWidth={highlighted ? 2 : 1.5}
                      className="transition-all duration-150"
                    />
                    {showLabels && (
                      <text
                        x={pos.x}
                        y={pos.y + 4}
                        textAnchor="middle"
                        className="text-xs fill-gray-700 font-semibold pointer-events-none"
                        style={{ fontSize: '10px' }}
                      >
                        L
                      </text>
                    )}
                  </g>
                )
              })}

              {/* Upper Cabinets - Dashed outline */}
              {layers.upperCabinets && cabinets.upper?.map((cabinet: any) => {
                const pos = toSVG(cabinet.position.x, cabinet.position.z)
                const width = cabinet.width_ft * scale
                const depth = cabinet.depth_ft * scale
                const highlighted = isHighlighted(cabinet)

                return (
                  <g
                    key={cabinet.id}
                    className="cabinet-group cursor-pointer"
                    onClick={() => setSelectedObject(cabinet)}
                    onMouseEnter={() => setHoveredObject(cabinet)}
                    onMouseLeave={() => setHoveredObject(null)}
                  >
                    <rect
                      x={pos.x - width / 2}
                      y={pos.y - depth / 2}
                      width={width}
                      height={depth}
                      fill="none"
                      stroke={highlighted ? '#2563EB' : '#9CA3AF'}
                      strokeWidth={highlighted ? 2 : 1.5}
                      strokeDasharray="5,3"
                      className="transition-all duration-150"
                    />
                    {showLabels && (
                      <text
                        x={pos.x}
                        y={pos.y + 4}
                        textAnchor="middle"
                        className="text-xs fill-gray-500 font-semibold pointer-events-none"
                        style={{ fontSize: '10px' }}
                      >
                        U
                      </text>
                    )}
                  </g>
                )
              })}

              {/* Appliances - Distinct orange/coral color */}
              {layers.appliances && appliances.map((appliance: any) => {
                const pos = toSVG(appliance.position.x, appliance.position.z)
                const width = appliance.width_ft * scale
                const depth = appliance.depth_ft * scale
                const highlighted = isHighlighted(appliance)

                return (
                  <g
                    key={appliance.id}
                    className="appliance-group cursor-pointer"
                    onClick={() => setSelectedObject(appliance)}
                    onMouseEnter={() => setHoveredObject(appliance)}
                    onMouseLeave={() => setHoveredObject(null)}
                  >
                    <rect
                      x={pos.x - width / 2}
                      y={pos.y - depth / 2}
                      width={width}
                      height={depth}
                      fill={highlighted ? '#FFEDD5' : '#FED7AA'}
                      stroke={highlighted ? '#C2410C' : '#EA580C'}
                      strokeWidth={highlighted ? 2 : 1.5}
                      className="transition-all duration-150"
                    />
                    {showLabels && (
                      <text
                        x={pos.x}
                        y={pos.y + 4}
                        textAnchor="middle"
                        className="text-xs fill-orange-900 font-semibold pointer-events-none"
                        style={{ fontSize: '10px' }}
                      >
                        A
                      </text>
                    )}
                  </g>
                )
              })}

              {/* Walls - Thicker and darker for visual hierarchy */}
              {layers.walls && walls.map((wall: any) => {
                const start = toSVG(wall.start.x, wall.start.z)
                const end = toSVG(wall.end.x, wall.end.z)
                const midX = (start.x + end.x) / 2
                const midY = (start.y + end.y) / 2
                const highlighted = isHighlighted(wall)

                return (
                  <g
                    key={wall.id}
                    className="wall-group cursor-pointer"
                    onClick={() => setSelectedObject(wall)}
                    onMouseEnter={() => setHoveredObject(wall)}
                    onMouseLeave={() => setHoveredObject(null)}
                  >
                    {/* Wall shadow for depth */}
                    <line
                      x1={start.x + 2}
                      y1={start.y + 2}
                      x2={end.x + 2}
                      y2={end.y + 2}
                      stroke="#00000010"
                      strokeWidth={wall.thickness_ft ? wall.thickness_ft * scale + 2 : 10}
                      strokeLinecap="round"
                    />
                    {/* Main wall line */}
                    <line
                      x1={start.x}
                      y1={start.y}
                      x2={end.x}
                      y2={end.y}
                      stroke={highlighted ? '#1D4ED8' : '#111827'}
                      strokeWidth={wall.thickness_ft ? wall.thickness_ft * scale : 8}
                      strokeLinecap="round"
                      className="transition-colors duration-150"
                    />
                    {showLabels && (
                      <text
                        x={midX}
                        y={midY - 12}
                        textAnchor="middle"
                        className="text-xs fill-blue-700 font-semibold pointer-events-none"
                        style={{ fontSize: '11px' }}
                      >
                        {wall.width_ft.toFixed(1)}'
                      </text>
                    )}
                  </g>
                )
              })}

              {/* Doors */}
              {layers.doors && doors.map((door: any) => {
                const pos = toSVG(door.position.x, door.position.z)
                const doorWidth = door.width_ft * scale
                const highlighted = isHighlighted(door)

                return (
                  <g
                    key={door.id}
                    className="door-group cursor-pointer"
                    onClick={() => setSelectedObject(door)}
                    onMouseEnter={() => setHoveredObject(door)}
                    onMouseLeave={() => setHoveredObject(null)}
                  >
                    {/* Door opening */}
                    <rect
                      x={pos.x - doorWidth / 2}
                      y={pos.y - 4}
                      width={doorWidth}
                      height={8}
                      fill="white"
                      stroke={highlighted ? '#1D4ED8' : '#60A5FA'}
                      strokeWidth={highlighted ? 2.5 : 2}
                      className="transition-all duration-150"
                    />
                    {/* Door swing arc */}
                    <path
                      d={`M ${pos.x - doorWidth / 2} ${pos.y} Q ${pos.x} ${pos.y - doorWidth / 2} ${pos.x + doorWidth / 2} ${pos.y}`}
                      stroke={highlighted ? '#1D4ED8' : '#60A5FA'}
                      strokeWidth="1.5"
                      fill="none"
                      strokeDasharray="4,2"
                    />
                    {showLabels && (
                      <text
                        x={pos.x}
                        y={pos.y - doorWidth / 2 - 8}
                        textAnchor="middle"
                        className="text-xs fill-blue-700 font-medium pointer-events-none"
                        style={{ fontSize: '10px' }}
                      >
                        D: {door.width_inches}"
                      </text>
                    )}
                  </g>
                )
              })}

              {/* Windows */}
              {layers.windows && windows.map((window: any) => {
                const pos = toSVG(window.position.x, window.position.z)
                const windowWidth = window.width_ft * scale
                const highlighted = isHighlighted(window)

                return (
                  <g
                    key={window.id}
                    className="window-group cursor-pointer"
                    onClick={() => setSelectedObject(window)}
                    onMouseEnter={() => setHoveredObject(window)}
                    onMouseLeave={() => setHoveredObject(null)}
                  >
                    <rect
                      x={pos.x - windowWidth / 2}
                      y={pos.y - 4}
                      width={windowWidth}
                      height={8}
                      fill={highlighted ? '#BFDBFE' : '#93C5FD'}
                      stroke={highlighted ? '#1D4ED8' : '#3B82F6'}
                      strokeWidth={highlighted ? 2.5 : 2}
                      className="transition-all duration-150"
                    />
                    {/* Window divider lines */}
                    <line
                      x1={pos.x}
                      y1={pos.y - 4}
                      x2={pos.x}
                      y2={pos.y + 4}
                      stroke={highlighted ? '#1D4ED8' : '#3B82F6'}
                      strokeWidth="1"
                    />
                    {showLabels && (
                      <text
                        x={pos.x}
                        y={pos.y + 20}
                        textAnchor="middle"
                        className="text-xs fill-blue-700 font-medium pointer-events-none"
                        style={{ fontSize: '10px' }}
                      >
                        W: {window.width_inches}"
                      </text>
                    )}
                  </g>
                )
              })}
            </svg>

            {/* Interactive Legend with Toggles */}
            <div className="mt-4 p-3 bg-gray-50 rounded-lg border border-gray-200">
              <div className="flex items-center justify-between mb-3">
                <h4 className="text-sm font-semibold text-gray-700">Layers</h4>
                <button
                  className="h-6 w-6 p-0 flex items-center justify-center rounded hover:bg-gray-200 transition-colors"
                  title="Click layer buttons to toggle visibility"
                >
                  <Info className="h-3.5 w-3.5 text-gray-400" />
                </button>
              </div>
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                {/* Walls */}
                <button
                  onClick={() => toggleLayer('walls')}
                  className={`flex items-center gap-2 p-2 rounded-md transition-all ${
                    layers.walls
                      ? 'bg-white border border-gray-300 shadow-sm'
                      : 'bg-gray-100 border border-transparent opacity-60'
                  }`}
                >
                  <div className={`w-6 h-1.5 rounded ${layers.walls ? 'bg-gray-800' : 'bg-gray-400'}`} />
                  <span className="text-xs font-medium text-gray-700">
                    Walls ({elementCounts.walls})
                  </span>
                </button>

                {/* Doors */}
                <button
                  onClick={() => toggleLayer('doors')}
                  className={`flex items-center gap-2 p-2 rounded-md transition-all ${
                    layers.doors
                      ? 'bg-white border border-gray-300 shadow-sm'
                      : 'bg-gray-100 border border-transparent opacity-60'
                  }`}
                >
                  <div className={`w-5 h-3 border-2 rounded-sm ${layers.doors ? 'border-blue-400 bg-white' : 'border-gray-400 bg-gray-200'}`} />
                  <span className="text-xs font-medium text-gray-700">
                    Doors ({elementCounts.doors})
                  </span>
                </button>

                {/* Windows */}
                <button
                  onClick={() => toggleLayer('windows')}
                  className={`flex items-center gap-2 p-2 rounded-md transition-all ${
                    layers.windows
                      ? 'bg-white border border-gray-300 shadow-sm'
                      : 'bg-gray-100 border border-transparent opacity-60'
                  }`}
                >
                  <div className={`w-5 h-3 rounded-sm ${layers.windows ? 'bg-blue-300 border-2 border-blue-500' : 'bg-gray-300 border-2 border-gray-400'}`} />
                  <span className="text-xs font-medium text-gray-700">
                    Windows ({elementCounts.windows})
                  </span>
                </button>

                {/* Lower Cabinets */}
                <button
                  onClick={() => toggleLayer('lowerCabinets')}
                  className={`flex items-center gap-2 p-2 rounded-md transition-all ${
                    layers.lowerCabinets
                      ? 'bg-white border border-gray-300 shadow-sm'
                      : 'bg-gray-100 border border-transparent opacity-60'
                  }`}
                >
                  <div className={`w-5 h-5 rounded-sm flex items-center justify-center text-[8px] font-bold ${
                    layers.lowerCabinets
                      ? 'bg-gray-300 border-2 border-gray-600 text-gray-700'
                      : 'bg-gray-200 border-2 border-gray-400 text-gray-500'
                  }`}>L</div>
                  <span className="text-xs font-medium text-gray-700">
                    Lower ({elementCounts.lowerCabinets})
                  </span>
                </button>

                {/* Upper Cabinets */}
                <button
                  onClick={() => toggleLayer('upperCabinets')}
                  className={`flex items-center gap-2 p-2 rounded-md transition-all ${
                    layers.upperCabinets
                      ? 'bg-white border border-gray-300 shadow-sm'
                      : 'bg-gray-100 border border-transparent opacity-60'
                  }`}
                >
                  <div className={`w-5 h-5 rounded-sm flex items-center justify-center text-[8px] font-bold border-2 border-dashed ${
                    layers.upperCabinets
                      ? 'border-gray-500 text-gray-600'
                      : 'border-gray-400 text-gray-400'
                  }`}>U</div>
                  <span className="text-xs font-medium text-gray-700">
                    Upper ({elementCounts.upperCabinets})
                  </span>
                </button>

                {/* Countertops */}
                <button
                  onClick={() => toggleLayer('countertops')}
                  className={`flex items-center gap-2 p-2 rounded-md transition-all ${
                    layers.countertops
                      ? 'bg-white border border-gray-300 shadow-sm'
                      : 'bg-gray-100 border border-transparent opacity-60'
                  }`}
                >
                  <div className={`w-5 h-5 rounded-sm ${
                    layers.countertops
                      ? 'bg-emerald-200 border-2 border-emerald-400'
                      : 'bg-gray-200 border-2 border-gray-400'
                  }`} style={{ opacity: layers.countertops ? 0.6 : 1 }} />
                  <span className="text-xs font-medium text-gray-700">
                    Countertops ({elementCounts.countertops})
                  </span>
                </button>

                {/* Appliances */}
                <button
                  onClick={() => toggleLayer('appliances')}
                  className={`flex items-center gap-2 p-2 rounded-md transition-all ${
                    layers.appliances
                      ? 'bg-white border border-gray-300 shadow-sm'
                      : 'bg-gray-100 border border-transparent opacity-60'
                  }`}
                >
                  <div className={`w-5 h-5 rounded-sm flex items-center justify-center text-[8px] font-bold ${
                    layers.appliances
                      ? 'bg-orange-200 border-2 border-orange-500 text-orange-900'
                      : 'bg-gray-200 border-2 border-gray-400 text-gray-500'
                  }`}>A</div>
                  <span className="text-xs font-medium text-gray-700">
                    Appliances ({elementCounts.appliances})
                  </span>
                </button>
              </div>

              {/* Countertop note */}
              {elementCounts.countertops > 5 && (
                <div className="mt-3 p-2 bg-amber-50 border border-amber-200 rounded text-xs text-amber-800">
                  <strong>Tip:</strong> Multiple countertop segments detected. Hover over the floor plan to highlight individual sections, or toggle off countertops for a cleaner view.
                </div>
              )}
            </div>
          </CardContent>
        </Card>

        {/* Detail Panel */}
        <Card>
          <CardHeader>
            <CardTitle className="text-lg">Details</CardTitle>
            <CardDescription>
              {selectedObject ? 'Selected element details' : 'Click or hover over any element'}
            </CardDescription>
          </CardHeader>
          <CardContent>
            {selectedObject || hoveredObject ? (
              <div className="space-y-4">
                <div>
                  <div className="flex items-center gap-2">
                    <h3 className="font-semibold text-lg">
                      {(selectedObject || hoveredObject).id}
                    </h3>
                    {hoveredObject && !selectedObject && (
                      <Badge variant="outline" className="text-xs">Hovering</Badge>
                    )}
                  </div>
                  <Badge variant="secondary" className="mt-1">
                    {(selectedObject || hoveredObject).type || 'Wall'}
                  </Badge>
                </div>

                <Separator />

                <div className="space-y-2">
                  <h4 className="font-medium text-sm text-gray-700">Dimensions</h4>
                  {(selectedObject || hoveredObject).width_ft && (
                    <div className="flex justify-between text-sm">
                      <span className="text-gray-600">Width:</span>
                      <span className="font-mono font-medium">
                        {formatDimension((selectedObject || hoveredObject).width_ft)}
                      </span>
                    </div>
                  )}
                  {(selectedObject || hoveredObject).height_ft && (
                    <div className="flex justify-between text-sm">
                      <span className="text-gray-600">Height:</span>
                      <span className="font-mono font-medium">
                        {formatDimension((selectedObject || hoveredObject).height_ft)}
                      </span>
                    </div>
                  )}
                  {(selectedObject || hoveredObject).depth_ft && (
                    <div className="flex justify-between text-sm">
                      <span className="text-gray-600">Depth:</span>
                      <span className="font-mono font-medium">
                        {formatDimension((selectedObject || hoveredObject).depth_ft)}
                      </span>
                    </div>
                  )}
                  {(selectedObject || hoveredObject).linear_ft && (
                    <div className="flex justify-between text-sm">
                      <span className="text-gray-600">Linear Ft:</span>
                      <span className="font-mono font-medium">
                        {(selectedObject || hoveredObject).linear_ft.toFixed(2)} ft
                      </span>
                    </div>
                  )}
                  {(selectedObject || hoveredObject).area_sqft && (
                    <div className="flex justify-between text-sm">
                      <span className="text-gray-600">Area:</span>
                      <span className="font-mono font-medium">
                        {(selectedObject || hoveredObject).area_sqft.toFixed(2)} sq ft
                      </span>
                    </div>
                  )}
                </div>

                {(selectedObject || hoveredObject).position && (
                  <div className="pt-2 border-t">
                    <div className="text-xs text-gray-500">
                      Position: ({(selectedObject || hoveredObject).position.x.toFixed(1)}, {(selectedObject || hoveredObject).position.z.toFixed(1)})
                    </div>
                  </div>
                )}

                {selectedObject && (
                  <Button
                    variant="outline"
                    size="sm"
                    className="w-full mt-2"
                    onClick={() => setSelectedObject(null)}
                  >
                    Clear Selection
                  </Button>
                )}
              </div>
            ) : (
              <div className="text-center py-6">
                <div className="w-12 h-12 rounded-full bg-gray-100 flex items-center justify-center mx-auto mb-3">
                  <Layers className="h-6 w-6 text-gray-400" />
                </div>
                <p className="text-sm text-gray-500">
                  Click or hover over any wall, door, window, cabinet, countertop, or appliance to view its detailed measurements.
                </p>
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
