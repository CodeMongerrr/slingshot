import AppKit
import AVFoundation
import SlingshotCore

// MARK: - Control panel

/// A round lamp with a live confidence meter. Glows dimly with the level and
/// flashes bright when its sound is registered.
final class LampView: NSView {
    private let bulb = NSView()
    private let meterFill = NSView()
    private let tint: NSColor
    private var flashUntil = Date.distantPast

    init(emoji: String, title: String, tint: NSColor) {
        self.tint = tint
        super.init(frame: NSRect(x: 0, y: 0, width: 150, height: 130))
        wantsLayer = true

        bulb.frame = NSRect(x: 39, y: 46, width: 72, height: 72)
        bulb.wantsLayer = true
        bulb.layer?.cornerRadius = 36
        bulb.layer?.backgroundColor = tint.withAlphaComponent(0.12).cgColor
        addSubview(bulb)

        let face = NSTextField(labelWithString: emoji)
        face.font = .systemFont(ofSize: 34)
        face.alignment = .center
        face.frame = NSRect(x: 0, y: 60, width: 150, height: 44)
        addSubview(face)

        let name = NSTextField(labelWithString: title)
        name.alignment = .center
        name.font = .systemFont(ofSize: 12, weight: .semibold)
        name.textColor = .secondaryLabelColor
        name.frame = NSRect(x: 0, y: 24, width: 150, height: 16)
        addSubview(name)

        let track = NSView(frame: NSRect(x: 20, y: 12, width: 110, height: 6))
        track.wantsLayer = true
        track.layer?.cornerRadius = 3
        track.layer?.backgroundColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.25).cgColor
        addSubview(track)
        meterFill.frame = NSRect(x: 0, y: 0, width: 0, height: 6)
        meterFill.wantsLayer = true
        meterFill.layer?.cornerRadius = 3
        meterFill.layer?.backgroundColor = tint.cgColor
        track.addSubview(meterFill)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func level(_ v: Double) {
        let clamped = CGFloat(max(0, min(1, v)))
        meterFill.frame.size.width = clamped * 110
        if Date() >= flashUntil {
            bulb.layer?.backgroundColor = tint.withAlphaComponent(0.12 + 0.4 * clamped).cgColor
        }
    }

    func flash() {
        flashUntil = Date().addingTimeInterval(0.8)
        bulb.layer?.backgroundColor = tint.cgColor
        bulb.layer?.shadowColor = tint.cgColor
        bulb.layer?.shadowOffset = .zero
        bulb.layer?.shadowRadius = 18
        bulb.layer?.shadowOpacity = 0.9
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, Date() >= self.flashUntil else { return }
            self.bulb.layer?.backgroundColor = self.tint.withAlphaComponent(0.12).cgColor
            self.bulb.layer?.shadowOpacity = 0
        }
    }
}

/// Local-only control window: a toggle for every sound feature and two lamps
/// that glow the moment the live recorder registers a snap or a clap. It exists
/// from launch, permission prompts included, so there is always a place that
/// shows WHY something is not happening. Main thread only.
final class ControlPanel: NSObject {
    enum Lamp { case snap, clap }

    private let panel: NSPanel
    private let snapLamp = LampView(emoji: "🫰", title: "SNAP",
                                    tint: NSColor(calibratedRed: 0.35, green: 0.85, blue: 1.00, alpha: 1))
    private let clapLamp = LampView(emoji: "👏", title: "CLAP",
                                    tint: NSColor(calibratedRed: 0.30, green: 0.90, blue: 0.55, alpha: 1))
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private var boxes: [(box: NSButton, isOn: () -> Bool)] = []
    private var refreshTimer: Timer?
    private var lastSnapLevel = 0.0
    private var lastClapLevel = 0.0

    override init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 384),
                        styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        super.init()
        panel.title = "Slingshot Control"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let content = panel.contentView!
        snapLamp.setFrameOrigin(NSPoint(x: 20, y: 234))
        clapLamp.setFrameOrigin(NSPoint(x: 210, y: 234))
        content.addSubview(snapLamp)
        content.addSubview(clapLamp)

        let toggleSpecs: [(String, () -> Bool, Selector)] = [
            ("Snap wakes the camera", { snapWakeEnabled }, #selector(hitSnapWake(_:))),
            ("Snap copies a screenshot to the clipboard", { snapToClipboardEnabled }, #selector(hitSnapClip(_:))),
            ("Clap mutes or unmutes the Mac", { clapMuteEnabled }, #selector(hitClapMute(_:))),
            ("Quit after \(Int(idleQuitAfter)) idle seconds", { idleQuitEnabled }, #selector(hitIdleQuit(_:))),
            ("Three quick snaps quit Slingshot", { quitSnapsEnabled }, #selector(hitQuitSnaps(_:))),
        ]
        var y: CGFloat = 202
        for (title, isOn, action) in toggleSpecs {
            let box = NSButton(checkboxWithTitle: title, target: self, action: action)
            box.frame = NSRect(x: 24, y: y, width: 332, height: 20)
            box.state = isOn() ? .on : .off
            content.addSubview(box)
            boxes.append((box, isOn))
            y -= 26
        }

        statusLabel.frame = NSRect(x: 24, y: 12, width: 332, height: 62)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        content.addSubview(statusLabel)

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
        refreshStatus()
    }

    func show() {
        if panel.frame.origin == .zero { panel.center() }
        panel.orderFront(nil)
    }

    /// Live classifier levels: drive the meters, and flash on each new crossing
    /// of a class's confidence bar — even when that feature's action is off.
    func levels(snap: Double, clap: Double) {
        snapLamp.level(snap)
        clapLamp.level(clap)
        if snap >= snapConfidenceThreshold, lastSnapLevel < snapConfidenceThreshold { snapLamp.flash() }
        if clap >= clapConfidenceThreshold, lastClapLevel < clapConfidenceThreshold { clapLamp.flash() }
        lastSnapLevel = snap
        lastClapLevel = clap
    }

    func flash(_ lamp: Lamp) {
        (lamp == .snap ? snapLamp : clapLamp).flash()
    }

    func refreshStatus() {
        for entry in boxes { entry.box.state = entry.isOn() ? .on : .off }
        var lines: [String] = []
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            lines.append((camera?.isRunning ?? false) ? "🎥 Camera awake" : "😴 Camera asleep — snap to wake")
        case .notDetermined:
            lines.append("⏳ Camera permission not answered yet")
        default:
            lines.append("⛔️ Camera denied — System Settings → Privacy & Security → Camera")
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            lines.append(snapListener != nil ? "🎙️ Mic listening" : "🔇 Mic idle — sound features are off")
        case .notDetermined:
            lines.append("⏳ Microphone permission not answered yet")
        default:
            lines.append("⛔️ Microphone denied — no snaps, no claps")
        }
        if !CGPreflightScreenCaptureAccess() {
            lines.append("⛔️ Screen Recording missing — grant it, then relaunch")
        }
        let peers = link.session.connectedPeers.count
        lines.append(peers == 0 ? "📡 No Macs connected" : "🤝 \(peers) Mac(s) connected")
        statusLabel.stringValue = lines.joined(separator: "\n")
    }

    @objc private func hitSnapWake(_ sender: NSButton) { setSnapWake(sender.state == .on) }
    @objc private func hitSnapClip(_ sender: NSButton) { setSnapClipboard(sender.state == .on) }
    @objc private func hitClapMute(_ sender: NSButton) { setClapMute(sender.state == .on) }
    @objc private func hitIdleQuit(_ sender: NSButton) { setIdleQuit(sender.state == .on) }
    @objc private func hitQuitSnaps(_ sender: NSButton) { setQuitSnaps(sender.state == .on) }
}
