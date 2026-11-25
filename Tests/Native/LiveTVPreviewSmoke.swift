#if os(macOS) && FLUX_LIVE_PREVIEW_TESTING
import AppKit
import AVFoundation
import CoreVideo
import Darwin
import Foundation

private enum LiveSmokeFailure: Error, CustomStringConvertible {
    case assertion(String)
    var description: String {switch self {case .assertion(let message):return message}}
}

/// Real AVPlayer lifecycle with a locally written video. No provider account or
/// network stream is used; selection, timing and decoder disposal are exercised.
@main private struct LiveTVPreviewSmoke {
    @MainActor static func main() {
        let application=NSApplication.shared
        application.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                try await run()
                print("PASS: TV preview delay, stable selection, cancellation, URL fallback, mute and single-decoder cleanup.")
                print("Local AVFoundation video fixture only; no remote IPTV stream was tested.")
                exit(0)
            } catch {
                fputs("FAIL: \(error)\n",stderr);exit(1)
            }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds:90_000_000_000)
            fputs("FAIL: TV preview smoke exceeded its 90-second deadline.\n",stderr);exit(1)
        }
        application.run()
    }

    @MainActor private static func run() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("flux-live-smoke-\(UUID().uuidString)",isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let firstURL=root.appendingPathComponent("first.mp4")
        let secondURL=root.appendingPathComponent("second.mp4")
        try await writeFixture(to:firstURL)
        try FileManager.default.copyItem(at:firstURL,to:secondURL)
        let missing=root.appendingPathComponent("missing.mp4")

        let preview=LiveTVPreviewController()
        defer {preview.stop()}
        preview.schedule(id:"first",urls:[firstURL],delay:.one)
        try require(preview.phase == .waiting && preview.player == nil,"The TV decoder started before its delay.")
        try require(preview.previewedItemID == "first","The waiting preview is not associated with its channel.")
        try await wait(0.30)
        preview.schedule(id:"second",urls:[secondURL],delay:.one)
        try require(preview.previewedItemID == "second","Changing selection retained the previous channel identity.")
        try await wait(0.78)
        try require(preview.player == nil && preview.phase == .waiting,"A cancelled first selection still started its decoder.")
        // Same selection must neither restart its timer nor replace its player.
        preview.schedule(id:"second",urls:[secondURL],delay:.one)
        try await eventually("The stable second channel did not start.") {preview.phase == .playing}
        guard let firstPlayer=preview.player else {throw LiveSmokeFailure.assertion("PLAYING without an AVPlayer.")}
        try require((firstPlayer.currentItem?.asset as? AVURLAsset)?.url == secondURL,"The old selected URL reached playback.")
        try require(preview.isMuted && firstPlayer.isMuted,"TV previews must start muted.")
        let initialTime=firstPlayer.currentTime().seconds
        preview.schedule(id:"second",urls:[secondURL],delay:.one)
        try await wait(0.35)
        try require(preview.player === firstPlayer,"Re-rendering the same selection replaced its decoder.")
        try require(firstPlayer.currentTime().seconds>initialTime,"The native fixture is not advancing.")
        preview.toggleMuted()
        try require(!preview.isMuted && !firstPlayer.isMuted,"Sound control did not reach the actual AVPlayer.")

        // A cancelled catalogue task must not replace the active channel or
        // turn a stale URL-resolution failure into the new selection's error.
        let cancelledSelection = Task { @MainActor in
            preview.schedule(id:"cancelled",urls:[firstURL],delay:.one)
            preview.markUnavailable(id:"cancelled")
        }
        cancelledSelection.cancel()
        await cancelledSelection.value
        try require(preview.previewedItemID == "second" && preview.player === firstPlayer && preview.phase == .playing,
                    "A cancelled selection changed the active preview or its identity.")

        preview.schedule(id:"third",urls:[firstURL],delay:.three)
        try require(preview.player == nil && firstPlayer.currentItem == nil && firstPlayer.rate == 0,"Changing selection left the previous decoder active.")
        try require(preview.isMuted,"A new channel inherited the previous sound setting.")
        preview.stop()
        try require(preview.previewedItemID == nil,"Stopping the preview retained the previous channel identity.")
        try await wait(3.2)
        try require(preview.player == nil && preview.phase == .idle,"Stopping the TV preview did not cancel its timer.")
        preview.schedule(id:"disabled",urls:[firstURL],delay:.one,enabled:false)
        try await wait(1.1)
        try require(preview.player == nil && preview.phase == .idle,"An explicitly disabled preview started.")

        preview.schedule(id:"fallback",urls:[missing,secondURL],delay:.one)
        try await eventually("A valid fallback URL did not recover the selected channel.") {preview.phase == .playing}
        try require((preview.player?.currentItem?.asset as? AVURLAsset)?.url == secondURL,"Fallback did not select the working local URL.")
        let fallbackPlayer=preview.player
        _ = await fallbackPlayer?.seek(to:CMTime(seconds:11.8,preferredTimescale:600))
        try await eventually("The end of a live preview remained labelled as playing.") {preview.phase == .failed && preview.player == nil}
        try require(fallbackPlayer?.currentItem == nil,"An ended preview retained its decoder.")
        preview.markUnavailable(id:"unavailable")
        try require(preview.phase == .failed && preview.player == nil,"Unavailable state retained a decoder.")
        try require(preview.previewedItemID == "unavailable","A URL-resolution failure lost its channel identity and would be hidden by the view.")
        preview.schedule(id:"empty",urls:[],delay:.one)
        try require(preview.phase == .failed && preview.player == nil,"An empty URL list should fail without allocating a decoder.")
        try require(preview.previewedItemID == "empty","An empty URL failure retained another channel's identity.")

        var disposable:LiveTVPreviewController?=LiveTVPreviewController()
        disposable?.schedule(id:"deinit",urls:[firstURL],delay:.one)
        try await eventually("The disposable preview did not start.") {disposable?.phase == .playing}
        let retainedPlayer=disposable?.player
        disposable=nil
        try await eventually("Deinitializing the controller retained its current item.") {retainedPlayer?.currentItem == nil}
    }

    @MainActor private static func writeFixture(to url:URL) async throws {
        let width=160,height=90
        let writer=try AVAssetWriter(outputURL:url,fileType:.mp4)
        let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:width,AVVideoHeightKey:height])
        let attributes:[String:Any]=[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB,kCVPixelBufferWidthKey as String:width,kCVPixelBufferHeightKey as String:height,kCVPixelBufferCGImageCompatibilityKey as String:true,kCVPixelBufferCGBitmapContextCompatibilityKey as String:true]
        let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:attributes)
        writer.add(input)
        try require(writer.startWriting(),"Cannot write the native video fixture: \(writer.error?.localizedDescription ?? "unknown")")
        writer.startSession(atSourceTime:.zero)
        for frame in 0..<144 {
            while !input.isReadyForMoreMediaData {
                try require(writer.status == .writing,"Fixture writer failed.")
                try await wait(0.01)
            }
            var buffer:CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault,width,height,kCVPixelFormatType_32ARGB,attributes as CFDictionary,&buffer)
            guard let buffer else {throw LiveSmokeFailure.assertion("Cannot allocate a fixture frame.")}
            CVPixelBufferLockBaseAddress(buffer,[])
            if let context=CGContext(data:CVPixelBufferGetBaseAddress(buffer),width:width,height:height,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(buffer),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipFirst.rawValue) {
                context.setFillColor(red:CGFloat(frame%24)/24,green:0.25,blue:0.7,alpha:1)
                context.fill(CGRect(x:0,y:0,width:CGFloat(width),height:CGFloat(height)))
            }
            CVPixelBufferUnlockBaseAddress(buffer,[])
            try require(adaptor.append(buffer,withPresentationTime:CMTime(value:Int64(frame),timescale:12)),"Cannot append the native fixture frame.")
        }
        input.markAsFinished()
        await writer.finishWriting()
        try require(writer.status == .completed,"The fixture writer did not finish: \(writer.error?.localizedDescription ?? "unknown")")
    }

    private static func require(_ condition:Bool,_ message:String)throws {
        if !condition {throw LiveSmokeFailure.assertion(message)}
    }
    private static func wait(_ seconds:Double)async throws {try await Task.sleep(nanoseconds:UInt64(seconds*1_000_000_000))}
    @MainActor private static func eventually(_ message:String,_ predicate:()->Bool)async throws {
        let deadline=Date().addingTimeInterval(12)
        while !predicate() {
            if Date()>deadline {throw LiveSmokeFailure.assertion(message)}
            try await wait(0.05)
        }
    }
}
#endif
