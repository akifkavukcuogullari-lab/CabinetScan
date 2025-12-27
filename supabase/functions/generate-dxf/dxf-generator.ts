/**
 * DXF Generator for Floor Plans
 * Generates AutoCAD DXF format (R2007/AC1021) compatible with 2020 Design and ProKitchen
 *
 * DXF Format Reference: https://images.autodesk.com/adsk/files/autocad_2012_pdf_dxf-reference_enu.pdf
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
  { name: 'CABINETS_LOWER', color: ACI.BLUE },
  { name: 'CABINETS_UPPER', color: ACI.MAGENTA, lineType: 'DASHED' },
  { name: 'APPLIANCES', color: ACI.RED },
  { name: 'SINKS', color: ACI.YELLOW },
  { name: 'COUNTERTOPS', color: ACI.GRAY },
  { name: 'TEXT', color: ACI.WHITE },
]

interface Point2D {
  x: number
  y: number
}

/**
 * DXF Generator Class
 * Creates ASCII DXF files compatible with AutoCAD and cabinet design software
 */
export class DXFGenerator {
  private entities: string[] = []
  private layers: LayerDef[] = []
  private handleCounter = 100

  constructor() {
    // Add default layers
    this.layers = [...FLOOR_PLAN_LAYERS]
  }

  private nextHandle(): string {
    return (this.handleCounter++).toString(16).toUpperCase()
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
    const handle = this.nextHandle()
    this.entities.push(`0
LINE
5
${handle}
8
${layer}
10
${start.x.toFixed(4)}
20
${start.y.toFixed(4)}
30
0.0000
11
${end.x.toFixed(4)}
21
${end.y.toFixed(4)}
31
0.0000`)
  }

  /**
   * Add a LWPOLYLINE (lightweight polyline) entity
   * @param points Array of points (inches)
   * @param layer Layer name
   * @param closed Whether the polyline is closed
   */
  addLwPolyline(points: Point2D[], layer: string, closed = false): void {
    if (points.length < 2) return

    const handle = this.nextHandle()
    const flags = closed ? 1 : 0

    let polyline = `0
LWPOLYLINE
5
${handle}
8
${layer}
90
${points.length}
70
${flags}`

    for (const pt of points) {
      polyline += `
10
${pt.x.toFixed(4)}
20
${pt.y.toFixed(4)}`
    }

    this.entities.push(polyline)
  }

  /**
   * Add a closed rectangle
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
    this.addLwPolyline(points, layer, true)
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
    const handle = this.nextHandle()
    this.entities.push(`0
ARC
5
${handle}
8
${layer}
10
${center.x.toFixed(4)}
20
${center.y.toFixed(4)}
30
0.0000
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
    const handle = this.nextHandle()
    this.entities.push(`0
CIRCLE
5
${handle}
8
${layer}
10
${center.x.toFixed(4)}
20
${center.y.toFixed(4)}
30
0.0000
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
    const handle = this.nextHandle()
    this.entities.push(`0
TEXT
5
${handle}
8
${layer}
10
${position.x.toFixed(4)}
20
${position.y.toFixed(4)}
30
0.0000
40
${height.toFixed(4)}
1
${text}
50
${rotation.toFixed(4)}`)
  }

  /**
   * Generate the complete DXF file content
   */
  generate(): string {
    const sections: string[] = []

    // HEADER section
    sections.push(this.generateHeader())

    // TABLES section (includes layers)
    sections.push(this.generateTables())

    // ENTITIES section
    sections.push(this.generateEntities())

    // EOF
    sections.push(`0
EOF`)

    return sections.join('\n')
  }

  private generateHeader(): string {
    return `0
SECTION
2
HEADER
9
$ACADVER
1
AC1021
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
$MEASUREMENT
70
0
0
ENDSEC`
  }

  private generateTables(): string {
    const layerEntries = this.layers.map((layer) => {
      const lineType = layer.lineType || 'CONTINUOUS'
      return `0
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

    // Add DASHED linetype definition
    const linetypes = `0
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
Dashed line
72
65
73
2
40
0.75
49
0.5
49
-0.25`

    return `0
SECTION
2
TABLES
0
TABLE
2
LTYPE
70
2
${linetypes}
0
ENDTAB
0
TABLE
2
LAYER
70
${this.layers.length}
${layerEntries}
0
ENDTAB
0
ENDSEC`
  }

  private generateEntities(): string {
    if (this.entities.length === 0) {
      return `0
SECTION
2
ENTITIES
0
ENDSEC`
    }

    return `0
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
