'use client'

import { useState } from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Separator } from '@/components/ui/separator'
import { ZoomIn, ZoomOut, Maximize2, Layers } from 'lucide-react'

interface FloorPlanViewerProps {
  measurements: any
}

export function FloorPlanViewer({ measurements }: FloorPlanViewerProps) {
  const [selectedObject, setSelectedObject] = useState<any>(null)
  const [zoom, setZoom] = useState(1)
  const [showGrid, setShowGrid] = useState(true)
  const [showLabels, setShowLabels] = useState(true)

  if (!measurements || !measurements.room) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>2D Floor Plan</CardTitle>
          <CardDescription>No detailed measurements available</CardDescription>
        </CardHeader>
        <CardContent>
          <p className="text-gray-500">
            This scan doesn't contain detailed spatial data. Please rescan the room with the latest app version.
          </p>
        </CardContent>
      </Card>
    )
  }

  const { room, walls = [], doors = [], windows = [], cabinets = { upper: [], lower: [] }, appliances = [] } = measurements

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

  // Format dimensions
  const formatDimension = (ft: number) => {
    const wholeFeet = Math.floor(ft)
    const inches = Math.round((ft - wholeFeet) * 12)
    return `${wholeFeet}' ${inches}"`
  }

  return (
    <div className="space-y-4">
      {/* Toolbar */}
      <div className="flex items-center justify-between">
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
        <div className="text-sm text-gray-500">
          Room: {roomWidth.toFixed(1)}' × {roomDepth.toFixed(1)}' | Ceiling: {room.ceiling_height_ft?.toFixed(1)}'
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
                <g className="grid-lines" opacity="0.1">
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

              {/* Walls */}
              {walls.map((wall: any) => {
                const start = toSVG(wall.start.x, wall.start.z)
                const end = toSVG(wall.end.x, wall.end.z)
                const midX = (start.x + end.x) / 2
                const midY = (start.y + end.y) / 2

                return (
                  <g
                    key={wall.id}
                    className="wall-group cursor-pointer"
                    onClick={() => setSelectedObject(wall)}
                  >
                    <line
                      x1={start.x}
                      y1={start.y}
                      x2={end.x}
                      y2={end.y}
                      stroke={selectedObject?.id === wall.id ? '#3B82F6' : '#1F2937'}
                      strokeWidth={wall.thickness_ft ? wall.thickness_ft * scale : 6}
                      className="hover:stroke-blue-500 transition-colors"
                    />
                    {showLabels && (
                      <text
                        x={midX}
                        y={midY - 10}
                        textAnchor="middle"
                        className="text-xs fill-blue-600 font-medium"
                        style={{ fontSize: '12px' }}
                      >
                        {wall.width_ft.toFixed(1)}'
                      </text>
                    )}
                  </g>
                )
              })}

              {/* Doors */}
              {doors.map((door: any) => {
                const pos = toSVG(door.position.x, door.position.z)
                const doorWidth = door.width_ft * scale

                return (
                  <g
                    key={door.id}
                    className="door-group cursor-pointer"
                    onClick={() => setSelectedObject(door)}
                  >
                    {/* Door opening */}
                    <rect
                      x={pos.x - doorWidth / 2}
                      y={pos.y - 3}
                      width={doorWidth}
                      height={6}
                      fill="white"
                      stroke="#60A5FA"
                      strokeWidth="2"
                      className="hover:fill-blue-50"
                    />
                    {/* Door swing arc */}
                    <path
                      d={`M ${pos.x - doorWidth / 2} ${pos.y} Q ${pos.x} ${pos.y - doorWidth / 2} ${pos.x + doorWidth / 2} ${pos.y}`}
                      stroke="#60A5FA"
                      strokeWidth="1"
                      fill="none"
                      strokeDasharray="3"
                    />
                    {showLabels && (
                      <text
                        x={pos.x}
                        y={pos.y - doorWidth / 2 - 5}
                        textAnchor="middle"
                        className="text-xs fill-blue-600"
                        style={{ fontSize: '10px' }}
                      >
                        D: {door.width_inches}
                      </text>
                    )}
                  </g>
                )
              })}

              {/* Windows */}
              {windows.map((window: any) => {
                const pos = toSVG(window.position.x, window.position.z)
                const windowWidth = window.width_ft * scale

                return (
                  <g
                    key={window.id}
                    className="window-group cursor-pointer"
                    onClick={() => setSelectedObject(window)}
                  >
                    <rect
                      x={pos.x - windowWidth / 2}
                      y={pos.y - 3}
                      width={windowWidth}
                      height={6}
                      fill="#93C5FD"
                      stroke="#3B82F6"
                      strokeWidth="2"
                      className="hover:fill-blue-200"
                    />
                    {showLabels && (
                      <text
                        x={pos.x}
                        y={pos.y + 20}
                        textAnchor="middle"
                        className="text-xs fill-blue-700"
                        style={{ fontSize: '10px' }}
                      >
                        W: {window.width_inches}
                      </text>
                    )}
                  </g>
                )
              })}

              {/* Lower Cabinets */}
              {cabinets.lower?.map((cabinet: any) => {
                const pos = toSVG(cabinet.position.x, cabinet.position.z)
                const width = cabinet.width_ft * scale
                const depth = cabinet.depth_ft * scale

                return (
                  <g
                    key={cabinet.id}
                    className="cabinet-group cursor-pointer"
                    onClick={() => setSelectedObject(cabinet)}
                  >
                    <rect
                      x={pos.x - width / 2}
                      y={pos.y - depth / 2}
                      width={width}
                      height={depth}
                      fill={selectedObject?.id === cabinet.id ? '#DBEAFE' : '#E5E7EB'}
                      stroke="#6B7280"
                      strokeWidth="2"
                      className="hover:fill-gray-300 transition-colors"
                    />
                    <text
                      x={pos.x}
                      y={pos.y + 4}
                      textAnchor="middle"
                      className="text-xs fill-gray-700 font-medium"
                      style={{ fontSize: '11px' }}
                    >
                      L
                    </text>
                  </g>
                )
              })}

              {/* Upper Cabinets */}
              {cabinets.upper?.map((cabinet: any) => {
                const pos = toSVG(cabinet.position.x, cabinet.position.z)
                const width = cabinet.width_ft * scale
                const depth = cabinet.depth_ft * scale

                return (
                  <g
                    key={cabinet.id}
                    className="cabinet-group cursor-pointer"
                    onClick={() => setSelectedObject(cabinet)}
                  >
                    <rect
                      x={pos.x - width / 2}
                      y={pos.y - depth / 2}
                      width={width}
                      height={depth}
                      fill="none"
                      stroke={selectedObject?.id === cabinet.id ? '#3B82F6' : '#9CA3AF'}
                      strokeWidth="2"
                      strokeDasharray="4"
                      className="hover:stroke-gray-600 transition-colors"
                    />
                    <text
                      x={pos.x}
                      y={pos.y + 4}
                      textAnchor="middle"
                      className="text-xs fill-gray-500 font-medium"
                      style={{ fontSize: '11px' }}
                    >
                      U
                    </text>
                  </g>
                )
              })}

              {/* Appliances */}
              {appliances.map((appliance: any) => {
                const pos = toSVG(appliance.position.x, appliance.position.z)
                const width = appliance.width_ft * scale
                const depth = appliance.depth_ft * scale

                return (
                  <g
                    key={appliance.id}
                    className="appliance-group cursor-pointer"
                    onClick={() => setSelectedObject(appliance)}
                  >
                    <rect
                      x={pos.x - width / 2}
                      y={pos.y - depth / 2}
                      width={width}
                      height={depth}
                      fill={selectedObject?.id === appliance.id ? '#FEE2E2' : '#FCA5A5'}
                      stroke="#DC2626"
                      strokeWidth="2"
                      className="hover:fill-red-300 transition-colors"
                    />
                    <text
                      x={pos.x}
                      y={pos.y + 4}
                      textAnchor="middle"
                      className="text-xs fill-red-900 font-medium"
                      style={{ fontSize: '10px' }}
                    >
                      A
                    </text>
                  </g>
                )
              })}
            </svg>

            {/* Legend */}
            <div className="mt-4 flex flex-wrap gap-4 text-sm">
              <div className="flex items-center gap-2">
                <div className="w-8 h-1 bg-gray-800"></div>
                <span>Wall</span>
              </div>
              <div className="flex items-center gap-2">
                <div className="w-8 h-3 border-2 border-blue-400 bg-white"></div>
                <span>Door</span>
              </div>
              <div className="flex items-center gap-2">
                <div className="w-8 h-3 bg-blue-300 border-2 border-blue-500"></div>
                <span>Window</span>
              </div>
              <div className="flex items-center gap-2">
                <div className="w-8 h-8 bg-gray-300 border-2 border-gray-600"></div>
                <span>Lower Cabinet (L)</span>
              </div>
              <div className="flex items-center gap-2">
                <div className="w-8 h-8 border-2 border-gray-400 border-dashed"></div>
                <span>Upper Cabinet (U)</span>
              </div>
              <div className="flex items-center gap-2">
                <div className="w-8 h-8 bg-red-300 border-2 border-red-600"></div>
                <span>Appliance (A)</span>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Detail Panel */}
        <Card>
          <CardHeader>
            <CardTitle className="text-lg">Details</CardTitle>
            <CardDescription>Click any object to see measurements</CardDescription>
          </CardHeader>
          <CardContent>
            {selectedObject ? (
              <div className="space-y-4">
                <div>
                  <h3 className="font-semibold text-lg">{selectedObject.id}</h3>
                  <Badge variant="secondary" className="mt-1">
                    {selectedObject.type || 'Wall'}
                  </Badge>
                </div>

                <Separator />

                <div className="space-y-2">
                  <h4 className="font-medium text-sm text-gray-700">Dimensions</h4>
                  {selectedObject.width_ft && (
                    <div className="flex justify-between text-sm">
                      <span className="text-gray-600">Width:</span>
                      <span className="font-mono font-medium">
                        {formatDimension(selectedObject.width_ft)}
                      </span>
                    </div>
                  )}
                  {selectedObject.height_ft && (
                    <div className="flex justify-between text-sm">
                      <span className="text-gray-600">Height:</span>
                      <span className="font-mono font-medium">
                        {formatDimension(selectedObject.height_ft)}
                      </span>
                    </div>
                  )}
                  {selectedObject.depth_ft && (
                    <div className="flex justify-between text-sm">
                      <span className="text-gray-600">Depth:</span>
                      <span className="font-mono font-medium">
                        {formatDimension(selectedObject.depth_ft)}
                      </span>
                    </div>
                  )}
                  {selectedObject.linear_ft && (
                    <div className="flex justify-between text-sm">
                      <span className="text-gray-600">Linear Ft:</span>
                      <span className="font-mono font-medium">
                        {selectedObject.linear_ft.toFixed(2)} ft
                      </span>
                    </div>
                  )}
                  {selectedObject.area_sqft && (
                    <div className="flex justify-between text-sm">
                      <span className="text-gray-600">Area:</span>
                      <span className="font-mono font-medium">
                        {selectedObject.area_sqft.toFixed(2)} sq ft
                      </span>
                    </div>
                  )}
                </div>

                {selectedObject.position && (
                  <div className="pt-2 border-t">
                    <div className="text-xs text-gray-500">
                      Position: ({selectedObject.position.x.toFixed(1)}, {selectedObject.position.z.toFixed(1)})
                    </div>
                  </div>
                )}
              </div>
            ) : (
              <p className="text-sm text-gray-500">
                Click on any wall, door, window, cabinet, or appliance to view its detailed measurements.
              </p>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
