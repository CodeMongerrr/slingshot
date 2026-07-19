import AppKit
import AVFoundation

/// First-run window: what Slingshot is, the four permissions, one Done button.
/// Programmatic AppKit in the island's obsidian look.
final class OnboardingWindow: NSObject {
    static let shared = OnboardingWindow()
    private var window: NSWindow?
    private var onDone: () -> Void = {}

    func showIfNeeded(completion: @escaping () -> Void) {
        guard !UserDefaults.standard.bool(forKey: "onboarded") else {
            completion()
            return
        }
        onDone = completion
        present()
    }

    private func present() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 460),
                         styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 1)
        w.center()

        let content = NSView(frame: w.contentLayoutRect)
        content.autoresizingMask = [.width, .height]

        func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat, height: CGFloat = 20) -> NSTextField {
            let l = NSTextField(wrappingLabelWithString: text)
            l.font = .systemFont(ofSize: size, weight: weight)
            l.textColor = color
            l.frame = NSRect(x: 36, y: y, width: 388, height: height)
            content.addSubview(l)
            return l
        }

        _ = label("Slingshot", size: 26, weight: .bold, color: .white, y: 396, height: 34)
        _ = label("Grab your screen with a fist. Snap to wake the camera. Files cross the room by hand.",
                  size: 13, weight: .regular, color: NSColor(white: 0.6, alpha: 1), y: 356, height: 36)

        var y: CGFloat = 296
        func permissionRow(_ title: String, _ detail: String, buttonTitle: String, action: Selector) {
            _ = label(title, size: 13, weight: .semibold, color: .white, y: y + 18)
            _ = label(detail, size: 11, weight: .regular, color: NSColor(white: 0.55, alpha: 1), y: y, height: 16)
            let button = NSButton(title: buttonTitle, target: self, action: action)
            button.bezelStyle = .rounded
            button.frame = NSRect(x: 350, y: y + 8, width: 84, height: 26)
            content.addSubview(button)
            y -= 62
        }

        permissionRow("Camera", "Reads your hand gestures. Frames never leave the Mac.",
                      buttonTitle: "Grant", action: #selector(grantCamera))
        permissionRow("Microphone", "Hears the finger snap that wakes the camera. On-device only.",
                      buttonTitle: "Grant", action: #selector(grantMic))
        permissionRow("Screen Recording", "Lets the grab gesture take the screenshot. Needs a relaunch after granting.",
                      buttonTitle: "Open", action: #selector(grantScreen))
        permissionRow("Local Network", "Finds nearby Macs. macOS asks by itself on first connection.",
                      buttonTitle: "Info", action: #selector(networkInfo))

        let done = NSButton(title: "Done", target: self, action: #selector(finish))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        done.frame = NSRect(x: 340, y: 24, width: 94, height: 30)
        content.addSubview(done)

        _ = label("Palm 2 seconds to arm, fist 1 second to grab. Fist then open hand at another Mac to catch.",
                  size: 11, weight: .regular, color: NSColor(white: 0.45, alpha: 1), y: 28, height: 30)

        w.contentView = content
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    @objc private func grantCamera() {
        AVCaptureDevice.requestAccess(for: .video) { _ in }
    }

    @objc private func grantMic() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    @objc private func grantScreen() {
        CGRequestScreenCaptureAccess()
    }

    @objc private func networkInfo() {
        let alert = NSAlert()
        alert.messageText = "Local Network"
        alert.informativeText = "macOS shows its own prompt the first time Slingshot looks for nearby Macs. Approve it when it appears."
        alert.runModal()
    }

    @objc private func finish() {
        UserDefaults.standard.set(true, forKey: "onboarded")
        window?.orderOut(nil)
        window = nil
        onDone()
    }
}
