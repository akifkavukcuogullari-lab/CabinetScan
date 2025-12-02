import Foundation
import SceneKit
import ModelIO
import SceneKit.ModelIO

/// Exports 3D models to GLB format for web viewing
struct GLBExporter {

    /// Convert a USDZ file to GLB format
    /// - Parameter usdzURL: URL to the source USDZ file
    /// - Returns: URL to the exported GLB file, or nil if conversion failed
    static func convertUSDZToGLB(usdzURL: URL) async -> URL? {
        // Load the USDZ file as a SceneKit scene
        guard let scene = try? SCNScene(url: usdzURL, options: [
            .checkConsistency: true,
            .flattenScene: true
        ]) else {
            print("GLBExporter: Failed to load USDZ file")
            return nil
        }

        // Create output URL for GLB file
        let tempDir = FileManager.default.temporaryDirectory
        let glbFilename = usdzURL.deletingPathExtension().lastPathComponent + ".glb"
        let glbURL = tempDir.appendingPathComponent(glbFilename)

        // Remove existing file if present
        try? FileManager.default.removeItem(at: glbURL)

        // Create MDLAsset from SCNScene
        let mdlAsset = MDLAsset(scnScene: scene)

        // Export to GLB format
        do {
            // Check if GLB export is supported
            let supportedExtensions = MDLAsset.canExportFileExtension("glb")
            if supportedExtensions {
                try mdlAsset.export(to: glbURL)

                // Verify the file was created
                if FileManager.default.fileExists(atPath: glbURL.path) {
                    let fileSize = try FileManager.default.attributesOfItem(atPath: glbURL.path)[.size] as? Int64 ?? 0
                    let fileSizeMB = Double(fileSize) / (1024 * 1024)
                    print("GLBExporter: Successfully exported GLB (\(String(format: "%.2f", fileSizeMB)) MB)")
                    return glbURL
                }
            } else {
                // Fallback: Try exporting to GLTF and then convert
                print("GLBExporter: GLB export not directly supported, trying GLTF...")
                return await exportAsGLTF(mdlAsset: mdlAsset, originalURL: usdzURL)
            }
        } catch {
            print("GLBExporter: Export failed - \(error.localizedDescription)")
            // Try fallback method
            return await exportAsGLTF(mdlAsset: mdlAsset, originalURL: usdzURL)
        }

        return nil
    }

    /// Fallback: Export to GLTF format (which model-viewer also supports)
    private static func exportAsGLTF(mdlAsset: MDLAsset, originalURL: URL) async -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let gltfFilename = originalURL.deletingPathExtension().lastPathComponent + ".gltf"
        let gltfURL = tempDir.appendingPathComponent(gltfFilename)

        try? FileManager.default.removeItem(at: gltfURL)

        do {
            if MDLAsset.canExportFileExtension("gltf") {
                try mdlAsset.export(to: gltfURL)

                if FileManager.default.fileExists(atPath: gltfURL.path) {
                    print("GLBExporter: Exported as GLTF instead")
                    return gltfURL
                }
            }
        } catch {
            print("GLBExporter: GLTF export also failed - \(error.localizedDescription)")
        }

        // Final fallback: Export as OBJ (widely supported)
        return await exportAsOBJ(mdlAsset: mdlAsset, originalURL: originalURL)
    }

    /// Final fallback: Export to OBJ format
    private static func exportAsOBJ(mdlAsset: MDLAsset, originalURL: URL) async -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let objFilename = originalURL.deletingPathExtension().lastPathComponent + ".obj"
        let objURL = tempDir.appendingPathComponent(objFilename)

        try? FileManager.default.removeItem(at: objURL)

        do {
            if MDLAsset.canExportFileExtension("obj") {
                try mdlAsset.export(to: objURL)

                if FileManager.default.fileExists(atPath: objURL.path) {
                    print("GLBExporter: Exported as OBJ as final fallback")
                    return objURL
                }
            }
        } catch {
            print("GLBExporter: OBJ export also failed - \(error.localizedDescription)")
        }

        return nil
    }

    /// Get the appropriate content type for the exported file
    static func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "glb":
            return "model/gltf-binary"
        case "gltf":
            return "model/gltf+json"
        case "obj":
            return "model/obj"
        default:
            return "application/octet-stream"
        }
    }
}
