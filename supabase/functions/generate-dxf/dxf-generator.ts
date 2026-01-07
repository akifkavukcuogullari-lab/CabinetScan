/**
 * DXF Generator for Floor Plans
 * Generates ASCII DXF format (R12/AC1009) for maximum compatibility with ProKitchen, 2020 Design, and AutoCAD
 *
 * Using R12 format for best compatibility - most kitchen design software supports this format
 */

// AutoCAD Color Index (ACI) standard colors
export const ACI = {
  RED: 1,
  YELLOW: 2,
  GREEN: 3,
  CYAN: 4,
  BLUE: 5,
  MAGENTA: 6,
  WHITE: 7,
  GRAY: 8,
  LIGHT_GRAY: 9,
} as const

// Layer definitions for cabinet floor plans
export interface LayerDef {
  name: string
  color: number
  lineType?: string
}

export const FLOOR_PLAN_LAYERS: LayerDef[] = [
  { name: 'WALLS', color: ACI.WHITE },
  { name: 'DOORS', color: ACI.GREEN },
  { name: 'WINDOWS', color: ACI.CYAN },
  { name: 'APPLIANCES', color: ACI.RED },
]

interface Point2D {
  x: number
  y: number
}

/**
 * DXF Generator Class
 * Creates ASCII DXF files in R12 format for maximum compatibility
 */
export class DXFGenerator {
  private entities: string[] = []
  private layers: LayerDef[] = []

  constructor() {
    // Add default layers
    this.layers = [...FLOOR_PLAN_LAYERS]
  }

  /**
   * Add a custom layer
   */
  addLayer(name: string, color: number, lineType = 'CONTINUOUS'): void {
    this.layers.push({ name, color, lineType })
  }

  /**
   * Add a LINE entity
   * @param start Start point (inches)
   * @param end End point (inches)
   * @param layer Layer name
   */
  addLine(start: Point2D, end: Point2D, layer: string): void {
    this.entities.push(`  0
LINE
  8
${layer}
 10
${start.x.toFixed(4)}
 20
${start.y.toFixed(4)}
 30
0.0
 11
${end.x.toFixed(4)}
 21
${end.y.toFixed(4)}
 31
0.0`)
  }

  /**
   * Add a POLYLINE entity (R12 format - more compatible than LWPOLYLINE)
   * @param points Array of points (inches)
   * @param layer Layer name
   * @param closed Whether the polyline is closed
   */
  addPolyline(points: Point2D[], layer: string, closed = false): void {
    if (points.length < 2) return

    const flags = closed ? 1 : 0

    // Start POLYLINE
    let polyline = `  0
POLYLINE
  8
${layer}
 66
1
 70
${flags}`

    // Add VERTEX entries
    for (const pt of points) {
      polyline += `
  0
VERTEX
  8
${layer}
 10
${pt.x.toFixed(4)}
 20
${pt.y.toFixed(4)}
 30
0.0`
    }

    // End POLYLINE with SEQEND
    polyline += `
  0
SEQEND
  8
${layer}`

    this.entities.push(polyline)
  }

  /**
   * Add a closed rectangle using POLYLINE
   * @param x X coordinate of bottom-left corner (inches)
   * @param y Y coordinate of bottom-left corner (inches)
   * @param width Width (inches)
   * @param height Height/Depth (inches)
   * @param layer Layer name
   */
  addRectangle(x: number, y: number, width: number, height: number, layer: string): void {
    const points: Point2D[] = [
      { x, y },
      { x: x + width, y },
      { x: x + width, y: y + height },
      { x, y: y + height },
    ]
    this.addPolyline(points, layer, true)
  }

  /**
   * Add an ARC entity (for door swings)
   * @param center Center point (inches)
   * @param radius Radius (inches)
   * @param startAngle Start angle (degrees)
   * @param endAngle End angle (degrees)
   * @param layer Layer name
   */
  addArc(center: Point2D, radius: number, startAngle: number, endAngle: number, layer: string): void {
    this.entities.push(`  0
ARC
  8
${layer}
 10
${center.x.toFixed(4)}
 20
${center.y.toFixed(4)}
 30
0.0
 40
${radius.toFixed(4)}
 50
${startAngle.toFixed(4)}
 51
${endAngle.toFixed(4)}`)
  }

  /**
   * Add a CIRCLE entity
   * @param center Center point (inches)
   * @param radius Radius (inches)
   * @param layer Layer name
   */
  addCircle(center: Point2D, radius: number, layer: string): void {
    this.entities.push(`  0
CIRCLE
  8
${layer}
 10
${center.x.toFixed(4)}
 20
${center.y.toFixed(4)}
 30
0.0
 40
${radius.toFixed(4)}`)
  }

  /**
   * Add a TEXT entity
   * @param position Text position (inches)
   * @param height Text height (inches)
   * @param text Text content
   * @param layer Layer name
   * @param rotation Rotation angle (degrees)
   */
  addText(position: Point2D, height: number, text: string, layer: string, rotation = 0): void {
    this.entities.push(`  0
TEXT
  8
${layer}
 10
${position.x.toFixed(4)}
 20
${position.y.toFixed(4)}
 30
0.0
 40
${height.toFixed(4)}
  1
${text}
 50
${rotation.toFixed(4)}`)
  }

  /**
   * Generate the complete DXF file content in R12 format
   */
  generate(): string {
    const sections: string[] = []

    // HEADER section
    sections.push(this.generateHeader())

    // TABLES section (includes linetypes and layers)
    sections.push(this.generateTables())

    // BLOCKS section (required, even if empty)
    sections.push(this.generateBlocks())

    // ENTITIES section
    sections.push(this.generateEntities())

    // EOF
    sections.push(`  0
EOF`)

    return sections.join('\n')
  }

  private generateHeader(): string {
    return `  0
SECTION
  2
HEADER
  9
$ACADVER
  1
AC1009
  9
$INSUNITS
 70
1
  9
$LUNITS
 70
2
  9
$LUPREC
 70
4
  9
$EXTMIN
 10
0.0
 20
0.0
 30
0.0
  9
$EXTMAX
 10
1000.0
 20
1000.0
 30
0.0
  0
ENDSEC`
  }

  private generateTables(): string {
    // Build LTYPE table
    const linetypeTable = `  0
TABLE
  2
LTYPE
 70
2
  0
LTYPE
  2
CONTINUOUS
 70
0
  3
Solid line
 72
65
 73
0
 40
0.0
  0
LTYPE
  2
DASHED
 70
0
  3
Dashed __ __ __ __
 72
65
 73
2
 40
0.75
 49
0.5
 49
-0.25
  0
ENDTAB`

    // Build LAYER table
    const layerEntries = this.layers.map((layer) => {
      const lineType = layer.lineType || 'CONTINUOUS'
      return `  0
LAYER
  2
${layer.name}
 70
0
 62
${layer.color}
  6
${lineType}`
    }).join('\n')

    const layerTable = `  0
TABLE
  2
LAYER
 70
${this.layers.length}
${layerEntries}
  0
ENDTAB`

    // Build STYLE table (required for TEXT entities)
    const styleTable = `  0
TABLE
  2
STYLE
 70
1
  0
STYLE
  2
STANDARD
 70
0
 40
0.0
 41
1.0
 50
0.0
 71
0
 42
0.2
  3
txt
  4

  0
ENDTAB`

    return `  0
SECTION
  2
TABLES
${linetypeTable}
${layerTable}
${styleTable}
  0
ENDSEC`
  }

  private generateBlocks(): string {
    // Minimal BLOCKS section - required for R12 compatibility
    return `  0
SECTION
  2
BLOCKS
  0
ENDSEC`
  }

  private generateEntities(): string {
    if (this.entities.length === 0) {
      return `  0
SECTION
  2
ENTITIES
  0
ENDSEC`
    }

    return `  0
SECTION
  2
ENTITIES
${this.entities.join('\n')}
  0
ENDSEC`
  }
}

// Utility function to convert feet to inches
export function feetToInches(feet: number): number {
  return feet * 12
}

// Utility function to convert RoomPlan coordinates (X, Z in feet) to DXF coordinates (X, Y in inches)
export function toDxfCoords(x: number, z: number): Point2D {
  return {
    x: feetToInches(x),
    y: feetToInches(z),
  }
}
