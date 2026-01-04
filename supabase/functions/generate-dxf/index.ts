import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'
import { DXFGenerator, toDxfCoords, feetToInches } from './dxf-generator.ts'

interface Point2D {
  x: number
  z: number
}

interface Point3D extends Point2D {
  y?: number
}

interface WallData {
  id: string
  start: Point2D
  end: Point2D
  width_ft: number
  height_ft: number
  thickness_ft?: number
}

interface DoorData {
  id: string
  position: Point2D
  width_ft: number
  height_ft: number
}

interface WindowData {
  id: string
  position: Point2D
  width_ft: number
  height_ft: number
}

interface CabinetData {
  id: string
  type?: string
  position: Point3D
  width_ft: number
  height_ft: number
  depth_ft: number
  corners?: Point2D[]
}

interface ApplianceData {
  id: string
  type?: string
  position: Point3D
  width_ft: number
  height_ft: number
  depth_ft: number
  corners?: Point2D[]
}

interface SinkData {
  id: string
  position: Point3D
  width_ft: number
  height_ft?: number
  depth_ft: number
  corners?: Point2D[]
}

interface CountertopData {
  id: string
  position: Point3D
  width_ft: number
  depth_ft: number
  area_sqft?: number
}

interface Measurements {
  room?: {
    min_x: number
    max_x: number
    min_z: number
    max_z: number
    ceiling_height_ft?: number
  }
  walls?: WallData[]
  doors?: DoorData[]
  windows?: WindowData[]
  cabinets?: {
    upper?: CabinetData[]
    lower?: CabinetData[]
    wall_oven?: CabinetData[]
    pantry?: CabinetData[]
    upper_small?: CabinetData[]
  }
  appliances?: ApplianceData[]
  sinks?: SinkData[]
  countertops?: CountertopData[]
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { project_id } = await req.json()

    if (!project_id) {
      return new Response(
        JSON.stringify({ error: 'project_id is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Fetch project measurements from database
    const { data: projectMeasurement, error: fetchError } = await supabaseAdmin
      .from('project_measurements')
      .select(`
        measurements,
        room_name,
        projects!inner(
          id,
          reference_number,
          showroom_id
        )
      `)
      .eq('project_id', project_id)
      .single()

    if (fetchError || !projectMeasurement) {
      console.error('Error fetching project measurements:', fetchError)
      return new Response(
        JSON.stringify({ error: 'Project measurements not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const measurements = projectMeasurement.measurements as Measurements
    if (!measurements) {
      return new Response(
        JSON.stringify({ error: 'No measurement data available for this project' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Generate DXF
    const dxf = new DXFGenerator()

    // Add walls
    if (measurements.walls && measurements.walls.length > 0) {
      for (const wall of measurements.walls) {
        if (wall.start && wall.end) {
          const start = toDxfCoords(wall.start.x, wall.start.z)
          const end = toDxfCoords(wall.end.x, wall.end.z)
          dxf.addLine(start, end, 'WALLS')
        }
      }
    }

    // Add doors with swing arc
    if (measurements.doors && measurements.doors.length > 0) {
      for (const door of measurements.doors) {
        if (door.position && door.width_ft) {
          const pos = toDxfCoords(door.position.x, door.position.z)
          const widthInches = feetToInches(door.width_ft)

          // Draw door opening as a gap indicator
          const halfWidth = widthInches / 2

          // Draw door leaf (closed position - line)
          dxf.addLine(
            { x: pos.x - halfWidth, y: pos.y },
            { x: pos.x + halfWidth, y: pos.y },
            'DOORS'
          )

          // Draw 90-degree swing arc
          dxf.addArc(
            { x: pos.x - halfWidth, y: pos.y },
            widthInches,
            0,
            90,
            'DOORS'
          )
        }
      }
    }

    // Add windows
    if (measurements.windows && measurements.windows.length > 0) {
      for (const window of measurements.windows) {
        if (window.position && window.width_ft) {
          const pos = toDxfCoords(window.position.x, window.position.z)
          const widthInches = feetToInches(window.width_ft)
          const halfWidth = widthInches / 2

          // Draw window as double lines (standard CAD representation)
          const lineOffset = 2 // 2 inches apart

          dxf.addLine(
            { x: pos.x - halfWidth, y: pos.y - lineOffset },
            { x: pos.x + halfWidth, y: pos.y - lineOffset },
            'WINDOWS'
          )
          dxf.addLine(
            { x: pos.x - halfWidth, y: pos.y + lineOffset },
            { x: pos.x + halfWidth, y: pos.y + lineOffset },
            'WINDOWS'
          )
        }
      }
    }

    // Add lower cabinets
    if (measurements.cabinets?.lower && measurements.cabinets.lower.length > 0) {
      for (const cabinet of measurements.cabinets.lower) {
        if (cabinet.corners && cabinet.corners.length === 4) {
          // Use corner points if available
          const points = cabinet.corners.map(c => toDxfCoords(c.x, c.z))
          dxf.addLwPolyline(points, 'CABINETS_LOWER', true)
        } else if (cabinet.position && cabinet.width_ft && cabinet.depth_ft) {
          // Fall back to position + dimensions
          const pos = toDxfCoords(cabinet.position.x, cabinet.position.z)
          const width = feetToInches(cabinet.width_ft)
          const depth = feetToInches(cabinet.depth_ft)
          dxf.addRectangle(pos.x - width/2, pos.y - depth/2, width, depth, 'CABINETS_LOWER')
        }
      }
    }

    // Add upper cabinets (dashed lines)
    if (measurements.cabinets?.upper && measurements.cabinets.upper.length > 0) {
      for (const cabinet of measurements.cabinets.upper) {
        if (cabinet.corners && cabinet.corners.length === 4) {
          const points = cabinet.corners.map(c => toDxfCoords(c.x, c.z))
          dxf.addLwPolyline(points, 'CABINETS_UPPER', true)
        } else if (cabinet.position && cabinet.width_ft && cabinet.depth_ft) {
          const pos = toDxfCoords(cabinet.position.x, cabinet.position.z)
          const width = feetToInches(cabinet.width_ft)
          const depth = feetToInches(cabinet.depth_ft)
          dxf.addRectangle(pos.x - width/2, pos.y - depth/2, width, depth, 'CABINETS_UPPER')
        }
      }
    }

    // Add wall oven cabinets
    if (measurements.cabinets?.wall_oven && measurements.cabinets.wall_oven.length > 0) {
      for (const cabinet of measurements.cabinets.wall_oven) {
        if (cabinet.corners && cabinet.corners.length === 4) {
          const points = cabinet.corners.map(c => toDxfCoords(c.x, c.z))
          dxf.addLwPolyline(points, 'CABINETS_WALL_OVEN', true)
          // Add label
          const centerX = points.reduce((sum, p) => sum + p.x, 0) / 4
          const centerY = points.reduce((sum, p) => sum + p.y, 0) / 4
          dxf.addText({ x: centerX, y: centerY }, 3, 'WALL OVEN', 'TEXT')
        } else if (cabinet.position && cabinet.width_ft && cabinet.depth_ft) {
          const pos = toDxfCoords(cabinet.position.x, cabinet.position.z)
          const width = feetToInches(cabinet.width_ft)
          const depth = feetToInches(cabinet.depth_ft)
          dxf.addRectangle(pos.x - width/2, pos.y - depth/2, width, depth, 'CABINETS_WALL_OVEN')
          dxf.addText({ x: pos.x, y: pos.y }, 3, 'WALL OVEN', 'TEXT')
        }
      }
    }

    // Add pantry cabinets
    if (measurements.cabinets?.pantry && measurements.cabinets.pantry.length > 0) {
      for (const cabinet of measurements.cabinets.pantry) {
        if (cabinet.corners && cabinet.corners.length === 4) {
          const points = cabinet.corners.map(c => toDxfCoords(c.x, c.z))
          dxf.addLwPolyline(points, 'CABINETS_PANTRY', true)
          // Add label
          const centerX = points.reduce((sum, p) => sum + p.x, 0) / 4
          const centerY = points.reduce((sum, p) => sum + p.y, 0) / 4
          dxf.addText({ x: centerX, y: centerY }, 3, 'PANTRY', 'TEXT')
        } else if (cabinet.position && cabinet.width_ft && cabinet.depth_ft) {
          const pos = toDxfCoords(cabinet.position.x, cabinet.position.z)
          const width = feetToInches(cabinet.width_ft)
          const depth = feetToInches(cabinet.depth_ft)
          dxf.addRectangle(pos.x - width/2, pos.y - depth/2, width, depth, 'CABINETS_PANTRY')
          dxf.addText({ x: pos.x, y: pos.y }, 3, 'PANTRY', 'TEXT')
        }
      }
    }

    // Add upper small cabinets (above fridge/stove/sink - dashed lines)
    if (measurements.cabinets?.upper_small && measurements.cabinets.upper_small.length > 0) {
      for (const cabinet of measurements.cabinets.upper_small) {
        if (cabinet.corners && cabinet.corners.length === 4) {
          const points = cabinet.corners.map(c => toDxfCoords(c.x, c.z))
          dxf.addLwPolyline(points, 'CABINETS_UPPER_SMALL', true)
        } else if (cabinet.position && cabinet.width_ft && cabinet.depth_ft) {
          const pos = toDxfCoords(cabinet.position.x, cabinet.position.z)
          const width = feetToInches(cabinet.width_ft)
          const depth = feetToInches(cabinet.depth_ft)
          dxf.addRectangle(pos.x - width/2, pos.y - depth/2, width, depth, 'CABINETS_UPPER_SMALL')
        }
      }
    }

    // Add appliances with type labels
    if (measurements.appliances && measurements.appliances.length > 0) {
      for (const appliance of measurements.appliances) {
        if (appliance.corners && appliance.corners.length === 4) {
          const points = appliance.corners.map(c => toDxfCoords(c.x, c.z))
          dxf.addLwPolyline(points, 'APPLIANCES', true)

          // Add type label in center
          if (appliance.type) {
            const centerX = points.reduce((sum, p) => sum + p.x, 0) / 4
            const centerY = points.reduce((sum, p) => sum + p.y, 0) / 4
            dxf.addText({ x: centerX, y: centerY }, 3, appliance.type.toUpperCase(), 'TEXT')
          }
        } else if (appliance.position && appliance.width_ft && appliance.depth_ft) {
          const pos = toDxfCoords(appliance.position.x, appliance.position.z)
          const width = feetToInches(appliance.width_ft)
          const depth = feetToInches(appliance.depth_ft)
          dxf.addRectangle(pos.x - width/2, pos.y - depth/2, width, depth, 'APPLIANCES')

          if (appliance.type) {
            dxf.addText({ x: pos.x, y: pos.y }, 3, appliance.type.toUpperCase(), 'TEXT')
          }
        }
      }
    }

    // Add sinks
    if (measurements.sinks && measurements.sinks.length > 0) {
      for (const sink of measurements.sinks) {
        if (sink.corners && sink.corners.length === 4) {
          const points = sink.corners.map(c => toDxfCoords(c.x, c.z))
          dxf.addLwPolyline(points, 'SINKS', true)

          // Add sink symbol (oval/circle in center)
          const centerX = points.reduce((sum, p) => sum + p.x, 0) / 4
          const centerY = points.reduce((sum, p) => sum + p.y, 0) / 4
          dxf.addCircle({ x: centerX, y: centerY }, 6, 'SINKS') // 6" radius circle
        } else if (sink.position && sink.width_ft && sink.depth_ft) {
          const pos = toDxfCoords(sink.position.x, sink.position.z)
          const width = feetToInches(sink.width_ft)
          const depth = feetToInches(sink.depth_ft)
          dxf.addRectangle(pos.x - width/2, pos.y - depth/2, width, depth, 'SINKS')
          dxf.addCircle({ x: pos.x, y: pos.y }, 6, 'SINKS')
        }
      }
    }

    // Add countertops
    if (measurements.countertops && measurements.countertops.length > 0) {
      for (const countertop of measurements.countertops) {
        if (countertop.position && countertop.width_ft && countertop.depth_ft) {
          const pos = toDxfCoords(countertop.position.x, countertop.position.z)
          const width = feetToInches(countertop.width_ft)
          const depth = feetToInches(countertop.depth_ft)
          dxf.addRectangle(pos.x - width/2, pos.y - depth/2, width, depth, 'COUNTERTOPS')
        }
      }
    }

    // Generate DXF content
    const dxfContent = dxf.generate()

    // Create filename
    const refNumber = projectMeasurement.projects?.reference_number || project_id.slice(0, 8)
    const roomName = projectMeasurement.room_name || 'floor-plan'
    const filename = `${refNumber}-${roomName.replace(/\s+/g, '-').toLowerCase()}.dxf`

    // Return DXF file
    return new Response(dxfContent, {
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/dxf',
        'Content-Disposition': `attachment; filename="${filename}"`,
      },
    })
  } catch (error) {
    console.error('Error generating DXF:', error)
    return new Response(
      JSON.stringify({ error: 'Failed to generate DXF file', details: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
