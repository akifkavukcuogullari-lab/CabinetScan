'use client'

import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/ui/accordion'
import { Ruler, Box, Square, DoorOpen, Maximize2, ArrowUp } from 'lucide-react'

interface MeasurementsData {
  room?: {
    min_x: number
    max_x: number
    min_z: number
    max_z: number
    ceiling_height_ft: number
  }
  walls?: any[]
  cabinets?: {
    upper?: any[]
    lower?: any[]
    wall_oven?: any[]
    pantry?: any[]
  }
  appliances?: any[]
  sinks?: any[]
  doors?: any[]
  windows?: any[]
  countertop_summary?: {
    total_area_sqft: number
  }
}

interface Measurement {
  id: string
  total_linear_ft?: number
  total_sq_ft?: number
  wall_count?: number
  door_count?: number
  measurements?: MeasurementsData
}

interface RoomMeasurementsSectionProps {
  measurement?: Measurement | null
  defaultOpen?: boolean
}

export function RoomMeasurementsSection({
  measurement,
  defaultOpen = true
}: RoomMeasurementsSectionProps) {
  if (!measurement) {
    return null
  }

  const measurements = measurement.measurements
  const wallCount = measurement.wall_count || measurements?.walls?.length || 0
  const lowerCabinetCount = measurements?.cabinets?.lower?.length || 0
  const upperCabinetCount = measurements?.cabinets?.upper?.length || 0
  const wallOvenCabinetCount = measurements?.cabinets?.wall_oven?.length || 0
  const pantryCabinetCount = measurements?.cabinets?.pantry?.length || 0
  const applianceCount = measurements?.appliances?.length || 0
  const sinkCount = measurements?.sinks?.length || 0
  const doorCount = measurement.door_count || measurements?.doors?.length || 0
  const windowCount = measurements?.windows?.length || 0
  const countertopArea = measurements?.countertop_summary?.total_area_sqft || 0
  const ceilingHeight = measurements?.room?.ceiling_height_ft || 0

  // Calculate room dimensions
  const roomWidth = measurements?.room
    ? Math.abs(measurements.room.max_x - measurements.room.min_x)
    : 0
  const roomDepth = measurements?.room
    ? Math.abs(measurements.room.max_z - measurements.room.min_z)
    : 0

  const totalCabinets = lowerCabinetCount + upperCabinetCount + wallOvenCabinetCount + pantryCabinetCount
  const summaryItems = [
    wallCount > 0 && `${wallCount} walls`,
    totalCabinets > 0 && `${totalCabinets} cabinets`,
    applianceCount > 0 && `${applianceCount} appliances`,
    sinkCount > 0 && `${sinkCount} sinks`,
  ].filter(Boolean).join(' | ')

  return (
    <Accordion type="single" collapsible defaultValue={defaultOpen ? 'measurements' : undefined}>
      <AccordionItem value="measurements" className="border rounded-lg">
        <AccordionTrigger className="px-4 py-3 hover:no-underline">
          <div className="flex items-center gap-3">
            <Ruler className="h-5 w-5 text-blue-600" />
            <div className="text-left">
              <div className="font-medium">Room Measurements</div>
              <div className="text-sm text-gray-500 font-normal">{summaryItems}</div>
            </div>
          </div>
        </AccordionTrigger>
        <AccordionContent className="px-4 pb-4">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            {measurement.total_sq_ft && (
              <div className="p-3 bg-gray-50 rounded-lg">
                <div className="flex items-center gap-2 text-gray-500 mb-1">
                  <Square className="h-4 w-4" />
                  <span className="text-xs">Square Feet</span>
                </div>
                <p className="text-xl font-bold">{measurement.total_sq_ft.toFixed(1)}</p>
              </div>
            )}
            {wallCount > 0 && (
              <div className="p-3 bg-gray-50 rounded-lg">
                <div className="flex items-center gap-2 text-gray-500 mb-1">
                  <Box className="h-4 w-4" />
                  <span className="text-xs">Walls</span>
                </div>
                <p className="text-xl font-bold">{wallCount}</p>
              </div>
            )}
            {doorCount > 0 && (
              <div className="p-3 bg-gray-50 rounded-lg">
                <div className="flex items-center gap-2 text-gray-500 mb-1">
                  <DoorOpen className="h-4 w-4" />
                  <span className="text-xs">Doors</span>
                </div>
                <p className="text-xl font-bold">{doorCount}</p>
              </div>
            )}
            {countertopArea > 0 && (
              <div className="p-3 bg-green-50 rounded-lg border border-green-200">
                <div className="flex items-center gap-2 text-green-700 mb-1">
                  <Square className="h-4 w-4" />
                  <span className="text-xs font-medium">Countertop</span>
                </div>
                <p className="text-xl font-bold text-green-900">{countertopArea.toFixed(1)}</p>
                <p className="text-xs text-green-600">sq ft</p>
              </div>
            )}
            {ceilingHeight > 0 && (
              <div className="p-3 bg-gray-50 rounded-lg">
                <div className="flex items-center gap-2 text-gray-500 mb-1">
                  <ArrowUp className="h-4 w-4" />
                  <span className="text-xs">Ceiling Height</span>
                </div>
                <p className="text-xl font-bold">{Math.round(ceilingHeight * 12)}"</p>
              </div>
            )}
            {roomWidth > 0 && roomDepth > 0 && (
              <div className="p-3 bg-gray-50 rounded-lg">
                <div className="flex items-center gap-2 text-gray-500 mb-1">
                  <Maximize2 className="h-4 w-4" />
                  <span className="text-xs">Room Size</span>
                </div>
                <p className="text-xl font-bold">{Math.round(roomWidth * 12)}" x {Math.round(roomDepth * 12)}"</p>
              </div>
            )}
          </div>

          {/* Cabinet & Appliance breakdown */}
          {(lowerCabinetCount > 0 || upperCabinetCount > 0 || wallOvenCabinetCount > 0 || pantryCabinetCount > 0 || applianceCount > 0 || sinkCount > 0 || windowCount > 0) && (
            <div className="mt-4 pt-4 border-t">
              <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
                {lowerCabinetCount > 0 && (
                  <div className="flex items-center justify-between p-2 bg-cyan-50 rounded">
                    <span className="text-cyan-700">Lower Cabinets</span>
                    <span className="font-medium text-cyan-900">{lowerCabinetCount}</span>
                  </div>
                )}
                {upperCabinetCount > 0 && (
                  <div className="flex items-center justify-between p-2 bg-purple-50 rounded">
                    <span className="text-purple-700">Upper Cabinets</span>
                    <span className="font-medium text-purple-900">{upperCabinetCount}</span>
                  </div>
                )}
                {wallOvenCabinetCount > 0 && (
                  <div className="flex items-center justify-between p-2 bg-orange-50 rounded">
                    <span className="text-orange-700">Wall Oven</span>
                    <span className="font-medium text-orange-900">{wallOvenCabinetCount}</span>
                  </div>
                )}
                {pantryCabinetCount > 0 && (
                  <div className="flex items-center justify-between p-2 bg-emerald-50 rounded">
                    <span className="text-emerald-700">Pantry</span>
                    <span className="font-medium text-emerald-900">{pantryCabinetCount}</span>
                  </div>
                )}
                {applianceCount > 0 && (
                  <div className="flex items-center justify-between p-2 bg-red-50 rounded">
                    <span className="text-red-700">Appliances</span>
                    <span className="font-medium text-red-900">{applianceCount}</span>
                  </div>
                )}
                {sinkCount > 0 && (
                  <div className="flex items-center justify-between p-2 bg-yellow-50 rounded">
                    <span className="text-yellow-700">Sinks</span>
                    <span className="font-medium text-yellow-900">{sinkCount}</span>
                  </div>
                )}
                {windowCount > 0 && (
                  <div className="flex items-center justify-between p-2 bg-blue-50 rounded">
                    <span className="text-blue-700">Windows</span>
                    <span className="font-medium text-blue-900">{windowCount}</span>
                  </div>
                )}
              </div>
            </div>
          )}
        </AccordionContent>
      </AccordionItem>
    </Accordion>
  )
}
