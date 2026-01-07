/**
 * DXF Generator for Floor Plan Export
 * Converts floor plan measurements to AutoCAD DXF format (R12/AC1009)
 * Using R12 format for maximum compatibility with ProKitchen, 2020 Design, and AutoCAD
 */

interface Point2D {
  x: number
  z: number
}

interface Wall {
  id: string
  start: Point2D
  end: Point2D
  width_ft: number
  height_ft: number
  thickness_ft?: number
}

interface Door {
  id: string
  position: Point2D
  width_ft: number
  height_ft: number
}

interface Window {
  id: string
  position: Point2D
  width_ft: number
  height_ft: number
}

interface Cabinet {
  id: string
  position: { x: number; z: number; y: number }
  width_ft: number
  depth_ft: number
  type?: string
}

interface Appliance {
  id: string
  position: { x: number; z: number; y: number }
  width_ft: number
  depth_ft: number
  type?: string
}

interface Countertop {
  id: string
  position: { x: number; z: number; y: number }
  width_ft: number
  depth_ft: number
  area_sqft?: number
}

interface Sink {
  id: string
  position: { x: number; z: number; y: number }
  width_ft: number
  depth_ft: number
  type?: string
}

interface FloorPlanMeasurements {
  room: {
    min_x: number
    max_x: number
    min_z: number
    max_z: number
    ceiling_height_ft?: number
  }
  walls: Wall[]
  doors: Door[]
  windows: Window[]
  cabinets: {
    upper: Cabinet[]
    lower: Cabinet[]
    wall_oven?: Cabinet[]
    pantry?: Cabinet[]
    upper_small?: Cabinet[]
  }
  appliances: Appliance[]
  sinks?: Sink[]
  countertops?: Countertop[]
}

export class DXFGenerator {
  private dxf: string[] = []

  constructor() {
    this.initializeDXF()
  }

  private initializeDXF() {
    // HEADER section - R12 format (AC1009) for maximum compatibility
    this.dxf.push('  0')
    this.dxf.push('SECTION')
    this.dxf.push('  2')
    this.dxf.push('HEADER')
    this.dxf.push('  9')
    this.dxf.push('$ACADVER')
    this.dxf.push('  1')
    this.dxf.push('AC1009')
    this.dxf.push('  9')
    this.dxf.push('$INSUNITS')
    this.dxf.push(' 70')
    this.dxf.push('1') // Inches
    this.dxf.push('  9')
    this.dxf.push('$LUNITS')
    this.dxf.push(' 70')
    this.dxf.push('2') // Decimal
    this.dxf.push('  9')
    this.dxf.push('$LUPREC')
    this.dxf.push(' 70')
    this.dxf.push('4') // 4 decimal places
    this.dxf.push('  9')
    this.dxf.push('$EXTMIN')
    this.dxf.push(' 10')
    this.dxf.push('0.0')
    this.dxf.push(' 20')
    this.dxf.push('0.0')
    this.dxf.push(' 30')
    this.dxf.push('0.0')
    this.dxf.push('  9')
    this.dxf.push('$EXTMAX')
    this.dxf.push(' 10')
    this.dxf.push('1000.0')
    this.dxf.push(' 20')
    this.dxf.push('1000.0')
    this.dxf.push(' 30')
    this.dxf.push('0.0')
    this.dxf.push('  0')
    this.dxf.push('ENDSEC')

    // TABLES section
    this.dxf.push('  0')
    this.dxf.push('SECTION')
    this.dxf.push('  2')
    this.dxf.push('TABLES')
    this.addLinetypeTable()
    this.addLayerTable()
    this.addStyleTable()
    this.dxf.push('  0')
    this.dxf.push('ENDSEC')

    // BLOCKS section (required for R12)
    this.dxf.push('  0')
    this.dxf.push('SECTION')
    this.dxf.push('  2')
    this.dxf.push('BLOCKS')
    this.dxf.push('  0')
    this.dxf.push('ENDSEC')

    // ENTITIES section start
    this.dxf.push('  0')
    this.dxf.push('SECTION')
    this.dxf.push('  2')
    this.dxf.push('ENTITIES')
  }

  private addLinetypeTable() {
    this.dxf.push('  0')
    this.dxf.push('TABLE')
    this.dxf.push('  2')
    this.dxf.push('LTYPE')
    this.dxf.push(' 70')
    this.dxf.push('2')

    // CONTINUOUS linetype
    this.dxf.push('  0')
    this.dxf.push('LTYPE')
    this.dxf.push('  2')
    this.dxf.push('CONTINUOUS')
    this.dxf.push(' 70')
    this.dxf.push('0')
    this.dxf.push('  3')
    this.dxf.push('Solid line')
    this.dxf.push(' 72')
    this.dxf.push('65')
    this.dxf.push(' 73')
    this.dxf.push('0')
    this.dxf.push(' 40')
    this.dxf.push('0.0')

    // DASHED linetype
    this.dxf.push('  0')
    this.dxf.push('LTYPE')
    this.dxf.push('  2')
    this.dxf.push('DASHED')
    this.dxf.push(' 70')
    this.dxf.push('0')
    this.dxf.push('  3')
    this.dxf.push('Dashed __ __ __ __')
    this.dxf.push(' 72')
    this.dxf.push('65')
    this.dxf.push(' 73')
    this.dxf.push('2')
    this.dxf.push(' 40')
    this.dxf.push('0.75')
    this.dxf.push(' 49')
    this.dxf.push('0.5')
    this.dxf.push(' 49')
    this.dxf.push('-0.25')

    this.dxf.push('  0')
    this.dxf.push('ENDTAB')
  }

  private addLayerTable() {
    this.dxf.push('  0')
    this.dxf.push('TABLE')
    this.dxf.push('  2')
    this.dxf.push('LAYER')
    this.dxf.push(' 70')
    this.dxf.push('12')

    // Walls Layer
    this.addLayer('WALLS', 7, 'CONTINUOUS')
    // Doors Layer
    this.addLayer('DOORS', 3, 'CONTINUOUS')
    // Windows Layer
    this.addLayer('WINDOWS', 4, 'CONTINUOUS')
    // Cabinets Lower Layer
    this.addLayer('CABINETS_LOWER', 5, 'CONTINUOUS')
    // Cabinets Upper Layer
    this.addLayer('CABINETS_UPPER', 6, 'DASHED')
    // Wall Oven Cabinets Layer
    this.addLayer('CABINETS_WALL_OVEN', 30, 'CONTINUOUS')
    // Pantry Cabinets Layer
    this.addLayer('CABINETS_PANTRY', 92, 'CONTINUOUS')
    // Upper Small Cabinets Layer
    this.addLayer('CABINETS_UPPER_SMALL', 200, 'DASHED')
    // Countertops Layer
    this.addLayer('COUNTERTOPS', 8, 'CONTINUOUS')
    // Appliances Layer
    this.addLayer('APPLIANCES', 1, 'CONTINUOUS')
    // Sinks Layer
    this.addLayer('SINKS', 2, 'CONTINUOUS')
    // Dimensions Layer
    this.addLayer('DIMENSIONS', 7, 'CONTINUOUS')

    this.dxf.push('  0')
    this.dxf.push('ENDTAB')
  }

  private addStyleTable() {
    this.dxf.push('  0')
    this.dxf.push('TABLE')
    this.dxf.push('  2')
    this.dxf.push('STYLE')
    this.dxf.push(' 70')
    this.dxf.push('1')

    this.dxf.push('  0')
    this.dxf.push('STYLE')
    this.dxf.push('  2')
    this.dxf.push('STANDARD')
    this.dxf.push(' 70')
    this.dxf.push('0')
    this.dxf.push(' 40')
    this.dxf.push('0.0')
    this.dxf.push(' 41')
    this.dxf.push('1.0')
    this.dxf.push(' 50')
    this.dxf.push('0.0')
    this.dxf.push(' 71')
    this.dxf.push('0')
    this.dxf.push(' 42')
    this.dxf.push('0.2')
    this.dxf.push('  3')
    this.dxf.push('txt')
    this.dxf.push('  4')
    this.dxf.push('')

    this.dxf.push('  0')
    this.dxf.push('ENDTAB')
  }

  private addLayer(name: string, color: number, lineType: string) {
    this.dxf.push('  0')
    this.dxf.push('LAYER')
    this.dxf.push('  2')
    this.dxf.push(name)
    this.dxf.push(' 70')
    this.dxf.push('0')
    this.dxf.push(' 62')
    this.dxf.push(color.toString())
    this.dxf.push('  6')
    this.dxf.push(lineType)
  }

  private addLine(x1: number, y1: number, x2: number, y2: number, layer: string) {
    this.dxf.push('  0')
    this.dxf.push('LINE')
    this.dxf.push('  8')
    this.dxf.push(layer)
    this.dxf.push(' 10')
    this.dxf.push(x1.toFixed(4))
    this.dxf.push(' 20')
    this.dxf.push(y1.toFixed(4))
    this.dxf.push(' 30')
    this.dxf.push('0.0')
    this.dxf.push(' 11')
    this.dxf.push(x2.toFixed(4))
    this.dxf.push(' 21')
    this.dxf.push(y2.toFixed(4))
    this.dxf.push(' 31')
    this.dxf.push('0.0')
  }

  private addPolyline(points: { x: number; y: number }[], layer: string, closed = true) {
    const flags = closed ? 1 : 0

    // Start POLYLINE (R12 format)
    this.dxf.push('  0')
    this.dxf.push('POLYLINE')
    this.dxf.push('  8')
    this.dxf.push(layer)
    this.dxf.push(' 66')
    this.dxf.push('1')
    this.dxf.push(' 70')
    this.dxf.push(flags.toString())

    // Add VERTEX entries
    points.forEach((point) => {
      this.dxf.push('  0')
      this.dxf.push('VERTEX')
      this.dxf.push('  8')
      this.dxf.push(layer)
      this.dxf.push(' 10')
      this.dxf.push(point.x.toFixed(4))
      this.dxf.push(' 20')
      this.dxf.push(point.y.toFixed(4))
      this.dxf.push(' 30')
      this.dxf.push('0.0')
    })

    // End with SEQEND
    this.dxf.push('  0')
    this.dxf.push('SEQEND')
    this.dxf.push('  8')
    this.dxf.push(layer)
  }

  private addText(x: number, y: number, text: string, height: number, layer: string) {
    this.dxf.push('  0')
    this.dxf.push('TEXT')
    this.dxf.push('  8')
    this.dxf.push(layer)
    this.dxf.push(' 10')
    this.dxf.push(x.toFixed(4))
    this.dxf.push(' 20')
    this.dxf.push(y.toFixed(4))
    this.dxf.push(' 30')
    this.dxf.push('0.0')
    this.dxf.push(' 40')
    this.dxf.push(height.toFixed(4))
    this.dxf.push('  1')
    this.dxf.push(text)
    this.dxf.push(' 50')
    this.dxf.push('0.0')
  }

  public generateFromMeasurements(measurements: FloorPlanMeasurements): string {
    // Add Walls
    measurements.walls.forEach((wall) => {
      this.addLine(wall.start.x, wall.start.z, wall.end.x, wall.end.z, 'WALLS')

      // Add dimension text
      const midX = (wall.start.x + wall.end.x) / 2
      const midY = (wall.start.z + wall.end.z) / 2
      this.addText(midX, midY, `${wall.width_ft.toFixed(2)}'`, 0.5, 'DIMENSIONS')
    })

    // Add Doors
    measurements.doors.forEach((door) => {
      const halfWidth = door.width_ft / 2
      const doorPoints = [
        { x: door.position.x - halfWidth, y: door.position.z },
        { x: door.position.x + halfWidth, y: door.position.z },
      ]
      this.addLine(doorPoints[0].x, doorPoints[0].y, doorPoints[1].x, doorPoints[1].y, 'DOORS')

      // Add door swing arc (simplified as line)
      this.addLine(
        door.position.x - halfWidth,
        door.position.z,
        door.position.x,
        door.position.z - halfWidth,
        'DOORS'
      )

      // Add label
      this.addText(
        door.position.x,
        door.position.z - halfWidth - 0.5,
        `D: ${door.width_ft.toFixed(1)}'x${door.height_ft.toFixed(1)}'`,
        0.3,
        'DIMENSIONS'
      )
    })

    // Add Windows
    measurements.windows.forEach((window) => {
      const halfWidth = window.width_ft / 2
      const windowPoints = [
        { x: window.position.x - halfWidth, y: window.position.z },
        { x: window.position.x + halfWidth, y: window.position.z },
      ]
      this.addLine(windowPoints[0].x, windowPoints[0].y, windowPoints[1].x, windowPoints[1].y, 'WINDOWS')

      // Add label
      this.addText(
        window.position.x,
        window.position.z + 0.5,
        `W: ${window.width_ft.toFixed(1)}'x${window.height_ft.toFixed(1)}'`,
        0.3,
        'DIMENSIONS'
      )
    })

    // Add Lower Cabinets
    measurements.cabinets.lower.forEach((cabinet) => {
      const halfWidth = cabinet.width_ft / 2
      const halfDepth = cabinet.depth_ft / 2
      const points = [
        { x: cabinet.position.x - halfWidth, y: cabinet.position.z - halfDepth },
        { x: cabinet.position.x + halfWidth, y: cabinet.position.z - halfDepth },
        { x: cabinet.position.x + halfWidth, y: cabinet.position.z + halfDepth },
        { x: cabinet.position.x - halfWidth, y: cabinet.position.z + halfDepth },
      ]
      this.addPolyline(points, 'CABINETS_LOWER')

      // Add label
      this.addText(cabinet.position.x, cabinet.position.z, cabinet.id, 0.25, 'DIMENSIONS')
    })

    // Add Upper Cabinets
    measurements.cabinets.upper.forEach((cabinet) => {
      const halfWidth = cabinet.width_ft / 2
      const halfDepth = cabinet.depth_ft / 2
      const points = [
        { x: cabinet.position.x - halfWidth, y: cabinet.position.z - halfDepth },
        { x: cabinet.position.x + halfWidth, y: cabinet.position.z - halfDepth },
        { x: cabinet.position.x + halfWidth, y: cabinet.position.z + halfDepth },
        { x: cabinet.position.x - halfWidth, y: cabinet.position.z + halfDepth },
      ]
      this.addPolyline(points, 'CABINETS_UPPER')

      // Add label
      this.addText(cabinet.position.x, cabinet.position.z, cabinet.id, 0.25, 'DIMENSIONS')
    })

    // Add Wall Oven Cabinets
    if (measurements.cabinets.wall_oven) {
      measurements.cabinets.wall_oven.forEach((cabinet) => {
        const halfWidth = cabinet.width_ft / 2
        const halfDepth = cabinet.depth_ft / 2
        const points = [
          { x: cabinet.position.x - halfWidth, y: cabinet.position.z - halfDepth },
          { x: cabinet.position.x + halfWidth, y: cabinet.position.z - halfDepth },
          { x: cabinet.position.x + halfWidth, y: cabinet.position.z + halfDepth },
          { x: cabinet.position.x - halfWidth, y: cabinet.position.z + halfDepth },
        ]
        this.addPolyline(points, 'CABINETS_WALL_OVEN')
        this.addText(cabinet.position.x, cabinet.position.z, 'WALL OVEN', 0.25, 'DIMENSIONS')
      })
    }

    // Add Pantry Cabinets
    if (measurements.cabinets.pantry) {
      measurements.cabinets.pantry.forEach((cabinet) => {
        const halfWidth = cabinet.width_ft / 2
        const halfDepth = cabinet.depth_ft / 2
        const points = [
          { x: cabinet.position.x - halfWidth, y: cabinet.position.z - halfDepth },
          { x: cabinet.position.x + halfWidth, y: cabinet.position.z - halfDepth },
          { x: cabinet.position.x + halfWidth, y: cabinet.position.z + halfDepth },
          { x: cabinet.position.x - halfWidth, y: cabinet.position.z + halfDepth },
        ]
        this.addPolyline(points, 'CABINETS_PANTRY')
        this.addText(cabinet.position.x, cabinet.position.z, 'PANTRY', 0.25, 'DIMENSIONS')
      })
    }

    // Add Upper Small Cabinets
    if (measurements.cabinets.upper_small) {
      measurements.cabinets.upper_small.forEach((cabinet) => {
        const halfWidth = cabinet.width_ft / 2
        const halfDepth = cabinet.depth_ft / 2
        const points = [
          { x: cabinet.position.x - halfWidth, y: cabinet.position.z - halfDepth },
          { x: cabinet.position.x + halfWidth, y: cabinet.position.z - halfDepth },
          { x: cabinet.position.x + halfWidth, y: cabinet.position.z + halfDepth },
          { x: cabinet.position.x - halfWidth, y: cabinet.position.z + halfDepth },
        ]
        this.addPolyline(points, 'CABINETS_UPPER_SMALL')
        this.addText(cabinet.position.x, cabinet.position.z, cabinet.id, 0.2, 'DIMENSIONS')
      })
    }

    // Add Appliances
    measurements.appliances.forEach((appliance) => {
      const halfWidth = appliance.width_ft / 2
      const halfDepth = appliance.depth_ft / 2
      const points = [
        { x: appliance.position.x - halfWidth, y: appliance.position.z - halfDepth },
        { x: appliance.position.x + halfWidth, y: appliance.position.z - halfDepth },
        { x: appliance.position.x + halfWidth, y: appliance.position.z + halfDepth },
        { x: appliance.position.x - halfWidth, y: appliance.position.z + halfDepth },
      ]
      this.addPolyline(points, 'APPLIANCES')

      // Add label
      this.addText(appliance.position.x, appliance.position.z, appliance.type || 'Appliance', 0.25, 'DIMENSIONS')
    })

    // Add Sinks
    if (measurements.sinks) {
      measurements.sinks.forEach((sink) => {
        const halfWidth = sink.width_ft / 2
        const halfDepth = sink.depth_ft / 2
        const points = [
          { x: sink.position.x - halfWidth, y: sink.position.z - halfDepth },
          { x: sink.position.x + halfWidth, y: sink.position.z - halfDepth },
          { x: sink.position.x + halfWidth, y: sink.position.z + halfDepth },
          { x: sink.position.x - halfWidth, y: sink.position.z + halfDepth },
        ]
        this.addPolyline(points, 'SINKS')

        // Add label
        this.addText(sink.position.x, sink.position.z, 'SINK', 0.25, 'DIMENSIONS')
      })
    }

    // Add Countertops
    if (measurements.countertops) {
      measurements.countertops.forEach((countertop) => {
        const halfWidth = countertop.width_ft / 2
        const halfDepth = countertop.depth_ft / 2
        const points = [
          { x: countertop.position.x - halfWidth, y: countertop.position.z - halfDepth },
          { x: countertop.position.x + halfWidth, y: countertop.position.z - halfDepth },
          { x: countertop.position.x + halfWidth, y: countertop.position.z + halfDepth },
          { x: countertop.position.x - halfWidth, y: countertop.position.z + halfDepth },
        ]
        this.addPolyline(points, 'COUNTERTOPS')

        // Add label
        if (countertop.area_sqft) {
          this.addText(
            countertop.position.x,
            countertop.position.z,
            `CT: ${countertop.area_sqft.toFixed(1)} sq ft`,
            0.25,
            'DIMENSIONS'
          )
        } else {
          this.addText(countertop.position.x, countertop.position.z, 'Countertop', 0.25, 'DIMENSIONS')
        }
      })
    }

    // Close ENTITIES section
    this.dxf.push('  0')
    this.dxf.push('ENDSEC')

    // End of file
    this.dxf.push('  0')
    this.dxf.push('EOF')

    return this.dxf.join('\n')
  }
}

// Export utility function
export function exportFloorPlanToDXF(measurements: FloorPlanMeasurements, projectName: string) {
  const generator = new DXFGenerator()
  const dxfContent = generator.generateFromMeasurements(measurements)

  // Create blob and download
  const blob = new Blob([dxfContent], { type: 'application/dxf' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = `${projectName.replace(/\s+/g, '_')}_FloorPlan.dxf`
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  URL.revokeObjectURL(url)
}
