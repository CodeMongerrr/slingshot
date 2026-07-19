import AppKit
import AVFoundation
import SoundAnalysis

// MARK: - Screenshot

func takeScreenshot() -> URL? {
    try? FileManager.default.createDirectory(at: shotsDir, withIntermediateDirectories: true)
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd-HHmmss"
    let url = shotsDir.appendingPathComponent("grab-\(df.string(from: Date())).png")

    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", url.path]
    let errPipe = Pipe()
    p.standardError = errPipe
    do {
        try p.run()
        p.waitUntilExit()
    } catch {
        log("❌ screencapture failed to launch: \(error)")
        return nil
    }
    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
    if let err = String(data: errData, encoding: .utf8), !err.isEmpty {
        log("   · screencapture stderr: \(err.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
    if p.terminationStatus != 0 {
        log("   · screencapture exit code: \(p.terminationStatus)")
    }
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
}

/// Full-screen grab straight to the clipboard, paste with Cmd-V. Blocking; call off the main thread.
@discardableResult
func copyScreenshotToClipboard() -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-c", "-x"]
    do {
        try p.run()
        p.waitUntilExit()
    } catch {
        log("❌ screencapture (clipboard) failed to launch: \(error)")
        return false
    }
    return p.terminationStatus == 0
}

// MARK: - Finger-snap listener

/// Fires onSnap when Apple's on-device sound classifier hears a finger snap.
/// All analysis is local; no audio leaves the Mac. Debounced so one snap fires once.
final class SnapListener: NSObject, SNResultsObserving {
    var onSnap: () -> Void = {}
    var onClap: () -> Void = {}
    var confidenceThreshold: Double = 0.5
    var debounce: TimeInterval = 1.2

    private let audio = AVAudioEngine()
    private var analyzer: SNAudioStreamAnalyzer?
    private let queue = DispatchQueue(label: "slingshot.snap")
    private var lastFire = Date.distantPast

    func start() throws {
        guard !audio.isRunning else { return }
        let input = audio.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw RuntimeError("Microphone input unavailable")
        }

        let analyzer = SNAudioStreamAnalyzer(format: format)
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        guard request.knownClassifications.contains("finger_snapping") else {
            throw RuntimeError("Sound classifier has no finger_snapping class")
        }
        // High overlap trades a little CPU for catching a snap anywhere in the window.
        request.overlapFactor = 0.75
        try analyzer.add(request, withObserver: self)
        self.analyzer = analyzer

        input.installTap(onBus: 0, bufferSize: 8192, format: format) { [weak self] buffer, when in
            self?.queue.async {
                self?.analyzer?.analyze(buffer, atAudioFramePosition: when.sampleTime)
            }
        }
        audio.prepare()
        try audio.start()
        let action = snapToClipboardEnabled ? "copies a screenshot to the clipboard" : "wakes the camera"
        log("🫰 Listening. A snap \(action); a clap puts the camera to sleep")
    }

    func stop() {
        guard audio.isRunning else { return }
        audio.inputNode.removeTap(onBus: 0)
        audio.stop()
        analyzer?.removeAllRequests()
        analyzer = nil
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let snap = result.classification(forIdentifier: "finger_snapping")?.confidence ?? 0
        let clap = result.classification(forIdentifier: "clapping")?.confidence ?? 0
        guard max(snap, clap) >= confidenceThreshold else { return }
        let now = Date()
        // One debounce for both sounds, so a snap's tail can never read as a clap.
        guard now.timeIntervalSince(lastFire) >= debounce else { return }
        lastFire = now
        if snap >= clap {
            DispatchQueue.main.async { [weak self] in self?.onSnap() }
        } else {
            DispatchQueue.main.async { [weak self] in self?.onClap() }
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        log("❌ Snap listener failed: \(error.localizedDescription)")
    }
}

// MARK: - Camera

final class Camera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "slingshot.camera")
    private let onFrame: (CVPixelBuffer) -> Void
    private var frameCount = 0

    init(onFrame: @escaping (CVPixelBuffer) -> Void) {
        self.onFrame = onFrame
        super.init()
    }

    private var configured = false
    private var deviceName = "camera"

    var isRunning: Bool { session.isRunning }

    func stop() {
        guard session.isRunning else { return }
        session.stopRunning()
    }

    func start() throws {
        if configured {
            guard !session.isRunning else { return }
            session.startRunning()
            log("🎥 Camera awake (\(deviceName))")
            return
        }
        guard let device = AVCaptureDevice.default(for: .video) else {
            throw RuntimeError("No camera found")
        }
        deviceName = device.localizedName
        session.sessionPreset = .vga640x480
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw RuntimeError("Cannot use camera input") }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw RuntimeError("Cannot attach video output") }
        session.addOutput(output)

        configured = true
        session.startRunning()
        log("🎥 Camera running (\(device.localizedName))")
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        frameCount += 1
        guard frameCount % 2 == 0, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame(pb)
    }
}

