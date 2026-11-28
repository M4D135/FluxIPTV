// The pictures behind the screens of the Apple TV, from those of the Mac.
//
//     xcrun swift scripts/make-tv-backdrops.swift
//
// Run from the root of the repository after a picture of
// FluxIPTVMac/Backdrops is added, changed or removed:
// scripts/generate-xcodeproj.py stops while the two folders differ.
//
// The Apple TV decodes a picture of the screens at 1920 pixels at most
// (StageRaster.pixelBudget). Each picture is written at that size, as
// ImageIO decodes it there, in JPEG of quality 0.9: in 0.9.10 the sixteen
// pictures weighed 5.9 MB instead of 14.5. Decoded as the Apple TV decodes
// them, the two sets differ by 42.7 dB of PSNR on average, 39.2 at worst.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let source = "FluxIPTVMac/Backdrops", target = "FluxIPTVMac/BackdropsTV/Backdrops"
let quality = 0.9, maxPixels = 1920
let files = FileManager.default
guard files.fileExists(atPath: source) else { fatalError("Run from the root of the repository: \(source) is missing.") }
try? files.removeItem(atPath: target)
try files.createDirectory(atPath: target, withIntermediateDirectories: true)
for name in try files.contentsOfDirectory(atPath: source).filter({ $0.hasSuffix(".jpg") }).sorted() {
    let input = URL(fileURLWithPath: source).appendingPathComponent(name)
    guard let picture = CGImageSourceCreateWithURL(input as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
          let image = CGImageSourceCreateThumbnailAtIndex(picture, 0, [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceCreateThumbnailWithTransform: true,
              kCGImageSourceThumbnailMaxPixelSize: maxPixels,
              kCGImageSourceShouldCacheImmediately: true,
          ] as CFDictionary) else { fatalError("\(name) cannot be read.") }
    let output = URL(fileURLWithPath: target).appendingPathComponent(name)
    guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
        fatalError("\(output.path) cannot be written.")
    }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { fatalError("\(output.path) cannot be written.") }
    let size = (try? files.attributesOfItem(atPath: output.path)[.size] as? Int) ?? 0
    print("\(name): \(image.width) × \(image.height), \(size / 1024) KB")
}
