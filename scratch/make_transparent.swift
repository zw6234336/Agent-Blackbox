import Foundation
import Cocoa
import CoreGraphics

let imagePath = "/Users/zhangwei/.gemini/antigravity/brain/6afc0854-9617-4a2d-8b89-985467783535/agent_blackbox_icon_v2_1779699223499.png"
let outputPath = "/Users/zhangwei/work/github/Agent-Blackbox/scratch/transparent_icon.png"

guard let image = NSImage(contentsOfFile: imagePath),
      let tiffData = image.tiffRepresentation,
      let imageSource = CGImageSourceCreateWithData(tiffData as CFData, nil),
      let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
    print("Error loading image")
    exit(1)
}

let width = cgImage.width
let height = cgImage.height
let colorSpace = CGColorSpaceCreateDeviceRGB()

var rawData = [UInt8](repeating: 0, count: width * height * 4)
let bytesPerPixel = 4
let bytesPerRow = bytesPerPixel * width
let bitsPerComponent = 8

guard let context = CGContext(
    data: &rawData,
    width: width,
    height: height,
    bitsPerComponent: bitsPerComponent,
    bytesPerRow: bytesPerRow,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
) else {
    print("Error creating context")
    exit(1)
}

context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

// Scan pixels and make white background transparent.
// We also perform simple anti-aliasing: if a pixel is near-white, we blend its alpha.
for y in 0..<height {
    for x in 0..<width {
        let offset = (y * width + x) * 4
        let r = Double(rawData[offset])
        let g = Double(rawData[offset + 1])
        let b = Double(rawData[offset + 2])
        
        // Calculate closeness to white (255, 255, 255)
        let diff = sqrt((255 - r) * (255 - r) + (255 - g) * (255 - g) + (255 - b) * (255 - b))
        
        // If it is very close to white, make it fully transparent.
        if diff < 15 {
            rawData[offset] = 0
            rawData[offset + 1] = 0
            rawData[offset + 2] = 0
            rawData[offset + 3] = 0
        } else if diff < 45 {
            // Anti-alias edge: scale the alpha based on distance
            let factor = (diff - 15) / (45 - 15)
            let alpha = UInt8(factor * 255)
            rawData[offset + 3] = alpha
        }
    }
}

guard let newCGImage = context.makeImage() else {
    print("Error making new image")
    exit(1)
}

let newImage = NSImage(cgImage: newCGImage, size: NSSize(width: width, height: height))
guard let tiffRepresentation = newImage.tiffRepresentation,
      let bitmapImage = NSBitmapImageRep(data: tiffRepresentation),
      let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
    print("Error saving PNG")
    exit(1)
}

try pngData.write(to: URL(fileURLWithPath: outputPath))
print("Success: Saved transparent PNG")
