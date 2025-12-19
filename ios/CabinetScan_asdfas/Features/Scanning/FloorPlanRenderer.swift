import SwiftUI
import RoomPlan
import simd

/// Renders a 2D floor plan image from RoomPlan's CapturedRoom data
struct FloorPlanRenderer {

    /// Render a 2D floor plan image from CapturedRoom
    /// - Parameters:
    ///   - room: The captured room data from RoomPlan
    ///   - size: The size of the output image
    /// - Returns: A UIImage of the floor plan
    static func renderFloorPlan(from room: CapturedRoom, size: CGSize = CGSize(width: 800, height: 800)) -> UIImage? {
        // Calculate room bounds
        var minX: Float = .infinity, maxX: Float = -.infinity
        var minZ: Float = .infinity, maxZ: Float = -.infinity

        // Collect all wall endpoints
        var wallSegments: [(start: CGPoint, end: CGPoint, thickness: Float)] = []

        for wall in room.walls {
            let transform = wall.transform
            let dimensions = wall.dimensions
            let halfWidth = dimensions.x / 2.0

            // Transform local endpoints to world coordinates
            let startLocal = SIMD4<Float>(-halfWidth, 0, 0, 1)
            let endLocal = SIMD4<Float>(halfWidth, 0, 0, 1)
            let startWorld = simd_mul(transform, startLocal)
            let endWorld = simd_mul(transform, endLocal)

            // Update bounds
            minX = min(minX, min(startWorld.x, endWorld.x))
            maxX = max(maxX, max(startWorld.x, endWorld.x))
            minZ = min(minZ, min(startWorld.z, endWorld.z))
            maxZ = max(maxZ, max(startWorld.z, endWorld.z))

            wallSegments.append((
                start: CGPoint(x: Double(startWorld.x), y: Double(startWorld.z)),
                end: CGPoint(x: Double(endWorld.x), y: Double(endWorld.z)),
                thickness: dimensions.z
            ))
        }

        // Add padding to bounds
        let padding: Float = 0.5 // meters
        minX -= padding
        maxX += padding
        minZ -= padding
        maxZ += padding

        let roomWidth = maxX - minX
        let roomDepth = maxZ - minZ

        // Calculate scale to fit in image
        let scaleX = Float(size.width - 100) / roomWidth
        let scaleZ = Float(size.height - 100) / roomDepth
        let scale = min(scaleX, scaleZ)

        // Transform function: world coords to image coords
        func toImage(_ point: CGPoint) -> CGPoint {
            let x = (Float(point.x) - minX) * scale + 50
            let y = (Float(point.y) - minZ) * scale + 50
            return CGPoint(x: Double(x), y: Double(y))
        }

        // Create image renderer
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let ctx = context.cgContext

            // White background
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))

            // Draw grid (subtle)
            ctx.setStrokeColor(UIColor.systemGray5.cgColor)
            ctx.setLineWidth(0.5)
            let gridSpacing: CGFloat = 40
            for x in stride(from: CGFloat(0), to: size.width, by: gridSpacing) {
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: CGFloat(0), to: size.height, by: gridSpacing) {
                ctx.move(to: CGPoint(x: 0, y: y))
                ctx.addLine(to: CGPoint(x: size.width, y: y))
            }
            ctx.strokePath()

            // Find floor level from storage objects (minimum Y is floor level)
            let storageObjects = room.objects.filter { $0.category == .storage }
            let floorLevel = storageObjects.map { $0.transform.columns.3.y }.min() ?? 0

            print("=== FloorPlanRenderer Debug ===")
            print("Floor level detected: \(floorLevel)m")
            print("Storage objects count: \(storageObjects.count)")

            var lowerCount = 0
            var upperCount = 0

            // Draw cabinets (lower) - white fill with black outline
            for object in room.objects where object.category == .storage {
                let position = object.transform.columns.3
                let heightAboveFloor = position.y - floorLevel

                // Lower cabinet: less than 1.0m above floor level
                if heightAboveFloor <= 1.0 {
                    lowerCount += 1
                    print("Drawing LOWER cabinet: y=\(position.y)m, heightAboveFloor=\(heightAboveFloor)m")
                    drawObject(ctx: ctx, object: object, scale: scale, minX: minX, minZ: minZ,
                              fillColor: UIColor.white, strokeColor: UIColor.darkGray, strokeWidth: 1.5)
                }
            }

            // Draw appliances and sinks - white fill with icon
            for object in room.objects {
                switch object.category {
                case .refrigerator, .stove, .oven, .dishwasher, .washerDryer, .sink:
                    print("Drawing appliance: \(object.category)")
                    drawAppliance(ctx: ctx, object: object, scale: scale, minX: minX, minZ: minZ)
                default:
                    break
                }
            }

            // Draw upper cabinets - dashed outline (drawn on top)
            // Upper cabinets are more than 1.0m above floor level
            for object in room.objects where object.category == .storage {
                let position = object.transform.columns.3
                let heightAboveFloor = position.y - floorLevel

                if heightAboveFloor > 1.0 {
                    upperCount += 1
                    print("Drawing UPPER cabinet: y=\(position.y)m, heightAboveFloor=\(heightAboveFloor)m")
                    drawObject(ctx: ctx, object: object, scale: scale, minX: minX, minZ: minZ,
                              fillColor: UIColor.systemGray5, strokeColor: UIColor.blue, strokeWidth: 2.0, dashed: true)
                }
            }

            print("Lower cabinets drawn: \(lowerCount), Upper cabinets drawn: \(upperCount)")
            print("=== End FloorPlanRenderer Debug ===")

            // Draw walls - thick black lines
            ctx.setStrokeColor(UIColor.black.cgColor)
            ctx.setLineWidth(8)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            for segment in wallSegments {
                let start = toImage(segment.start)
                let end = toImage(segment.end)
                ctx.move(to: start)
                ctx.addLine(to: end)
            }
            ctx.strokePath()

            // Draw doors - white gap with arc
            for door in room.doors {
                let position = door.transform.columns.3
                let pos = toImage(CGPoint(x: Double(position.x), y: Double(position.z)))
                let doorWidth = Double(door.dimensions.x) * Double(scale)

                // White rectangle for door opening
                ctx.setFillColor(UIColor.white.cgColor)
                ctx.fill(CGRect(x: pos.x - doorWidth/2, y: pos.y - 5, width: doorWidth, height: 10))

                // Door swing arc
                ctx.setStrokeColor(UIColor.systemBlue.cgColor)
                ctx.setLineWidth(1.5)
                ctx.setLineDash(phase: 0, lengths: [4, 3])
                ctx.addArc(center: CGPoint(x: pos.x - doorWidth/2, y: pos.y),
                          radius: doorWidth,
                          startAngle: -.pi/2,
                          endAngle: 0,
                          clockwise: false)
                ctx.strokePath()
                ctx.setLineDash(phase: 0, lengths: [])
            }

            // Draw windows - blue rectangles
            for window in room.windows {
                let position = window.transform.columns.3
                let pos = toImage(CGPoint(x: Double(position.x), y: Double(position.z)))
                let windowWidth = Double(window.dimensions.x) * Double(scale)

                ctx.setFillColor(UIColor.systemBlue.withAlphaComponent(0.3).cgColor)
                ctx.setStrokeColor(UIColor.systemBlue.cgColor)
                ctx.setLineWidth(2)
                let windowRect = CGRect(x: pos.x - windowWidth/2, y: pos.y - 4, width: windowWidth, height: 8)
                ctx.fill(windowRect)
                ctx.stroke(windowRect)
            }

            // Draw room label
            let roomArea = roomWidth * roomDepth * 10.7639 // sq meters to sq feet
            let centerX = size.width / 2
            let centerY = size.height / 2

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 20),
                .foregroundColor: UIColor.darkGray,
                .paragraphStyle: paragraphStyle
            ]
            let areaAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16),
                .foregroundColor: UIColor.gray,
                .paragraphStyle: paragraphStyle
            ]

            let titleString = "Kitchen"
            let areaString = String(format: "%.0f sq ft", roomArea)

            titleString.draw(in: CGRect(x: centerX - 100, y: centerY - 20, width: 200, height: 30), withAttributes: titleAttrs)
            areaString.draw(in: CGRect(x: centerX - 100, y: centerY + 5, width: 200, height: 25), withAttributes: areaAttrs)
        }
    }

    // MARK: - Helper Drawing Functions

    private static func drawObject(ctx: CGContext, object: CapturedRoom.Object, scale: Float, minX: Float, minZ: Float,
                                   fillColor: UIColor?, strokeColor: UIColor, strokeWidth: CGFloat, dashed: Bool = false) {
        let transform = object.transform
        let dimensions = object.dimensions
        let halfWidth = dimensions.x / 2.0
        let halfDepth = dimensions.z / 2.0

        // Calculate corners in world space
        let corners = [
            SIMD4<Float>(-halfWidth, 0, -halfDepth, 1),
            SIMD4<Float>(halfWidth, 0, -halfDepth, 1),
            SIMD4<Float>(halfWidth, 0, halfDepth, 1),
            SIMD4<Float>(-halfWidth, 0, halfDepth, 1)
        ].map { simd_mul(transform, $0) }

        // Transform to image coordinates
        let imageCorners = corners.map { corner -> CGPoint in
            let x = (corner.x - minX) * scale + 50
            let y = (corner.z - minZ) * scale + 50
            return CGPoint(x: Double(x), y: Double(y))
        }

        // Draw polygon
        ctx.beginPath()
        ctx.move(to: imageCorners[0])
        for i in 1..<4 {
            ctx.addLine(to: imageCorners[i])
        }
        ctx.closePath()

        if let fill = fillColor {
            ctx.setFillColor(fill.cgColor)
            ctx.fillPath()

            // Redraw path for stroke
            ctx.beginPath()
            ctx.move(to: imageCorners[0])
            for i in 1..<4 {
                ctx.addLine(to: imageCorners[i])
            }
            ctx.closePath()
        }

        ctx.setStrokeColor(strokeColor.cgColor)
        ctx.setLineWidth(strokeWidth)
        if dashed {
            ctx.setLineDash(phase: 0, lengths: [5, 3])
        } else {
            ctx.setLineDash(phase: 0, lengths: [])
        }
        ctx.strokePath()
    }

    private static func drawAppliance(ctx: CGContext, object: CapturedRoom.Object, scale: Float, minX: Float, minZ: Float) {
        let transform = object.transform
        let dimensions = object.dimensions
        let halfWidth = dimensions.x / 2.0
        let halfDepth = dimensions.z / 2.0

        let corners = [
            SIMD4<Float>(-halfWidth, 0, -halfDepth, 1),
            SIMD4<Float>(halfWidth, 0, -halfDepth, 1),
            SIMD4<Float>(halfWidth, 0, halfDepth, 1),
            SIMD4<Float>(-halfWidth, 0, halfDepth, 1)
        ].map { simd_mul(transform, $0) }

        let imageCorners = corners.map { corner -> CGPoint in
            let x = (corner.x - minX) * scale + 50
            let y = (corner.z - minZ) * scale + 50
            return CGPoint(x: Double(x), y: Double(y))
        }

        // Draw white rectangle
        ctx.beginPath()
        ctx.move(to: imageCorners[0])
        for i in 1..<4 {
            ctx.addLine(to: imageCorners[i])
        }
        ctx.closePath()
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fillPath()

        ctx.beginPath()
        ctx.move(to: imageCorners[0])
        for i in 1..<4 {
            ctx.addLine(to: imageCorners[i])
        }
        ctx.closePath()
        ctx.setStrokeColor(UIColor.darkGray.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.strokePath()

        // Draw appliance icon based on type
        let centerX = (imageCorners[0].x + imageCorners[2].x) / 2
        let centerY = (imageCorners[0].y + imageCorners[2].y) / 2
        let boxWidth = sqrt(pow(imageCorners[1].x - imageCorners[0].x, 2) + pow(imageCorners[1].y - imageCorners[0].y, 2))
        let boxHeight = sqrt(pow(imageCorners[3].x - imageCorners[0].x, 2) + pow(imageCorners[3].y - imageCorners[0].y, 2))

        ctx.setStrokeColor(UIColor.darkGray.cgColor)
        ctx.setLineWidth(1.5)

        switch object.category {
        case .stove, .oven:
            // Draw 4 burner circles
            let burnerR = min(boxWidth, boxHeight) * 0.12
            let offsetX = boxWidth * 0.2
            let offsetY = boxHeight * 0.2

            for dx in [-offsetX, offsetX] {
                for dy in [-offsetY, offsetY] {
                    ctx.strokeEllipse(in: CGRect(
                        x: centerX + dx - burnerR,
                        y: centerY + dy - burnerR,
                        width: burnerR * 2,
                        height: burnerR * 2
                    ))
                }
            }

        case .refrigerator:
            // Horizontal line
            ctx.move(to: CGPoint(x: centerX - boxWidth * 0.35, y: centerY - boxHeight * 0.15))
            ctx.addLine(to: CGPoint(x: centerX + boxWidth * 0.35, y: centerY - boxHeight * 0.15))
            ctx.strokePath()

        case .dishwasher:
            // X pattern
            ctx.move(to: CGPoint(x: centerX - boxWidth * 0.25, y: centerY - boxHeight * 0.25))
            ctx.addLine(to: CGPoint(x: centerX + boxWidth * 0.25, y: centerY + boxHeight * 0.25))
            ctx.move(to: CGPoint(x: centerX + boxWidth * 0.25, y: centerY - boxHeight * 0.25))
            ctx.addLine(to: CGPoint(x: centerX - boxWidth * 0.25, y: centerY + boxHeight * 0.25))
            ctx.strokePath()

        case .sink:
            // Oval for sink basin
            let basinWidth = boxWidth * 0.6
            let basinHeight = boxHeight * 0.5
            ctx.strokeEllipse(in: CGRect(
                x: centerX - basinWidth/2,
                y: centerY - basinHeight/2,
                width: basinWidth,
                height: basinHeight
            ))
            // Small circle for drain
            let drainR = min(boxWidth, boxHeight) * 0.06
            ctx.fillEllipse(in: CGRect(
                x: centerX - drainR,
                y: centerY - drainR,
                width: drainR * 2,
                height: drainR * 2
            ))
            // Faucet indicator (small rectangle at top)
            ctx.fill(CGRect(
                x: centerX - boxWidth * 0.05,
                y: centerY - boxHeight * 0.35,
                width: boxWidth * 0.1,
                height: boxHeight * 0.1
            ))

        default:
            break
        }
    }
}
