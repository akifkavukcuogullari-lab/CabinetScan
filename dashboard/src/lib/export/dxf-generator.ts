/**
 * DXF Generator for Floor Plan Export
 * Converts floor plan measurements to AutoCAD DXF format
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
  }
  appliances: Appliance[]
}

export class DXFGenerator {
  private dxf: string[] = []
  private handle = 100 // Starting handle for entities

  constructor() {
    this.initializeDXF()
  }

  private initializeDXF() {
    // DXF Header
    this.dxf.push('0')
    this.dxf.push('SECTION')
    this.dxf.push('2')
    this.dxf.push('HEADER')
    this.dxf.push('9')
    this.dxf.push('$ACADVER')
    this.dxf.push('1')
    this.dxf.push('AC1015') // AutoCAD 2000 format
    this.dxf.push('9')
    this.dxf.push('$INSUNITS')
    this.dxf.push('70')
    this.dxf.push('1') // Inches
    this.dxf.push('0')
    this.dxf.push('ENDSEC')

    // Tables Section
    this.dxf.push('0')
    this.dxf.push('SECTION')
    this.dxf.push('2')
    this.dxf.push('TABLES')
    this.addLayerTable()
    this.dxf.push('0')
    this.dxf.push('ENDSEC')

    // Entities Section Start
    this.dxf.push('0')
    this.dxf.push('SECTION')
    this.dxf.push('2')
    this.dxf.push('ENTITIES')
  }

  private addLayerTable() {
    this.dxf.push('0')
    this.dxf.push('TABLE')
    this.dxf.push('2')
    this.dxf.push('LAYER')
    this.dxf.push('70')
    this.dxf.push('7') // Number of layers

    // Walls Layer
    this.addLayer('WALLS', 7, 'Continuous')
    // Doors Layer
    this.addLayer('DOORS', 4, 'Continuous')
    // Windows Layer
    this.addLayer('WINDOWS', 5, 'Continuous')
    // Cabinets Lower Layer
    this.addLayer('CABINETS_LOWER', 8, 'Continuous')
    // Cabinets Upper Layer
    this.addLayer('CABINETS_UPPER', 9, 'DASHED')
    // Appliances Layer
    this.addLayer('APPLIANCES', 1, 'Continuous')
    // Dimensions Layer
    this.addLayer('DIMENSIONS', 6, 'Continuous')

    this.dxf.push('0')
    this.dxf.push('ENDTAB')
  }

  private addLayer(name: string, color: number, lineType: string) {
    this.dxf.push('0')
    this.dxf.push('LAYER')
    this.dxf.push('2')
    this.dxf.push(name)
    this.dxf.push('70')
    this.dxf.push('0')
    this.dxf.push('62')
    this.dxf.push(color.toString())
    this.dxf.push('6')
    this.dxf.push(lineType)
  }

  private addLine(x1: number, y1: number, x2: number, y2: number, layer: string) {
    this.dxf.push('0')
    this.dxf.push('LINE')
    this.dxf.push('5')
    this.dxf.push((this.handle++).toString(16))
    this.dxf.push('8')
    this.dxf.push(layer)
    this.dxf.push('10')
    this.dxf.push(x1.toFixed(6))
    this.dxf.push('20')
    this.dxf.push(y1.toFixed(6))
    this.dxf.push('11')
    this.dxf.push(x2.toFixed(6))
    this.dxf.push('21')
    this.dxf.push(y2.toFixed(6))
  }

  private addPolyline(points: { x: number; y: number }[], layer: string, closed = true) {
    this.dxf.push('0')
    this.dxf.push('LWPOLYLINE')
    this.dxf.push('5')
    this.dxf.push((this.handle++).toString(16))
    this.dxf.push('8')
    this.dxf.push(layer)
    this.dxf.push('90')
    this.dxf.push(points.length.toString())
    this.dxf.push('70')
    this.dxf.push(closed ? '1' : '0')

    points.forEach((point) => {
      this.dxf.push('10')
      this.dxf.push(point.x.toFixed(6))
      this.dxf.push('20')
      this.dxf.push(point.y.toFixed(6))
    })
  }

  private addText(x: number, y: number, text: string, height: number, layer: string) {
    this.dxf.push('0')
    this.dxf.push('TEXT')
    this.dxf.push('5')
    this.dxf.push((this.handle++).toString(16))
    this.dxf.push('8')
    this.dxf.push(layer)
    this.dxf.push('10')
    this.dxf.push(x.toFixed(6))
    this.dxf.push('20')
    this.dxf.push(y.toFixed(6))
    this.dxf.push('40')
    this.dxf.push(height.toFixed(6))
    this.dxf.push('1')
    this.dxf.push(text)
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

    // Close Entities Section
    this.dxf.push('0')
    this.dxf.push('ENDSEC')

    // End of File
    this.dxf.push('0')
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
