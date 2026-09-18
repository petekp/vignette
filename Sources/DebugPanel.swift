import AppKit
import SwiftUI

/// A floating panel of sliders bound to `settings.ui`. Every change applies to whatever is on screen
/// immediately and lands in settings.json. Preview buttons summon each UI state to tweak against.
@MainActor
final class DebugPanelController: NSObject, NSWindowDelegate {
    struct Previews {
        var thumbnail: () -> Void
        var stack: () -> Void
        var toast: () -> Void
        var annotator: () -> Void
    }

    private var panel: NSPanel?
    private let previews: Previews

    init(previews: Previews) {
        self.previews = previews
    }

    func toggle() {
        if let p = panel, p.isVisible { p.orderOut(nil); return }
        show()
    }

    func show() {
        let p = panel ?? make()
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func make() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 760),
                        styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        p.title = "Shotnote Tweaks"
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.delegate = self
        p.contentView = NSHostingView(rootView: DebugPanelView(previews: previews))
        // Left side of the screen so it never sits under the stack or the backdrop.
        if let v = NSScreen.main?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: v.minX + 40, y: v.midY - 380))
        }
        panel = p
        return p
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { FocusReturn.shared.restore(reason: "tweaks closed") }
    }
}

@MainActor
struct DebugPanelView: View {
    let previews: DebugPanelController.Previews
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Preview").font(.caption).foregroundStyle(.secondary)
                Button("Thumbnail", action: previews.thumbnail)
                Button("Stack", action: previews.stack)
                Button("Toast", action: previews.toast)
                Button("Annotator", action: previews.annotator)
            }
            .padding(10)
            // Which file the sliders write to: a test launch points at another file, and a
            // change made there never reaches the real one.
            if Settings.isOverridden {
                Text("Test settings file: \(Settings.fileURL.path). Changes here do not reach your settings.json.")
                    .font(.caption).foregroundStyle(.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.yellow)
            } else {
                Text("Writes to \((Settings.fileURL.path as NSString).abbreviatingWithTildeInPath)")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.bottom, 6)
            }
            Divider()
            Form {
                Section("Cards") {
                    Tweak("Max width", \.cardMaxWidth, 80...600)
                    Tweak("Max height", \.cardMaxHeight, 60...400)
                    Tweak("Min side", \.cardMinSide, 20...200)
                    Tweak("Spacing", \.cardSpacing, 0...40)
                    Tweak("Panel inset", \.panelInset, 0...60)
                    Tweak("Screen margin", \.screenMargin, 0...80)
                    Tweak("Corner radius", \.cardCornerRadius, 0...30)
                    Tweak("Border width", \.cardBorderWidth, 0...4, step: 0.5)
                    Tweak("Border opacity", \.cardBorderOpacity, 0...1, step: 0.05)
                    Tweak("Shadow radius", \.cardShadowRadius, 0...40)
                    Tweak("Shadow opacity", \.cardShadowOpacity, 0...1, step: 0.05)
                    Tweak("Shadow y", \.cardShadowY, -20...30)
                    Tweak("Hover scale", \.hoverScale, 0.9...1.2, step: 0.01)
                    Tweak("Press scale", \.pressScale, 0.8...1, step: 0.01)
                    Tweak("Hover dim", \.hoverDim, 0...0.8, step: 0.05)
                }
                Section("Hover buttons") {
                    Tweak("Size", \.buttonSize, 16...48)
                    Tweak("Icon size", \.buttonIconSize, 8...24)
                    Tweak("Spacing", \.buttonSpacing, 0...24)
                    Tweak("Selection circle", \.selectionCircleSize, 12...36)
                    Tweak("Selection bar height", \.selectionBarHeight, 24...60)
                    Tweak("Selection strip gap", \.selectionStripGap, 0...40)
                    Tweak("Drag-select edge band", \.autoScrollZone, 0...120, unit: "pt")
                    Tweak("Drag-select speed", \.autoScrollSpeed, 0...2000, step: 25, unit: "pt/s")
                    Text("How deep the band at each end of the column is, and how fast a drag-select scrolls at its very edge.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Timings") {
                    Tweak("Motion", \.motion, 0...1, step: 0.05)
                    Text("Scales every animation; 0 makes them instant. The system's Reduce Motion forces 0.")
                        .font(.caption).foregroundStyle(.secondary)
                    Tweak("Thumbnail stays", \.thumbnailSeconds, 1...20, step: 0.5, unit: "s")
                    Tweak("Toast stays", \.toastSeconds, 0.5...5, step: 0.1, unit: "s")
                    Tweak("Slide in", \.slideInDuration, 0...1.5, step: 0.05, unit: "s")
                    Picker("Slide in curve", selection: binding(\.slideInCurve)) {
                        ForEach(["spring", "easeOut", "easeInOut", "linear"], id: \.self) { Text($0).tag($0) }
                    }
                    Tweak("Slide out", \.slideOutDuration, 0...1.5, step: 0.05, unit: "s")
                    Tweak("Stagger per card", \.staggerDelay, 0...0.3, step: 0.01, unit: "s")
                    Tweak("Stagger total max", \.staggerTotalMax, 0...1.5, step: 0.05, unit: "s")
                    Tweak("Relayout", \.relayoutDuration, 0...1, step: 0.05, unit: "s")
                    Tweak("Hover reveal", \.hoverRevealDuration, 0...0.6, step: 0.05, unit: "s")
                }
                Section("Flights") {
                    Tweak("Expand to annotator", \.expandDuration, 0...1.5, step: 0.05, unit: "s")
                    Tweak("Arc", \.flightArc, 0...0.4, step: 0.01)
                    Tweak("Arc cap", \.flightArcMax, 0...300, step: 2, unit: "pt")
                    Tweak("Depth", \.flightDepth, 0...0.3, step: 0.01)
                    Text("How far a card bows off the straight line between its slot and the annotator, and how much it swells halfway there.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Backdrop") {
                    Tweak("Width", \.backdropWidth, 100...1000, step: 10)
                    Tweak("Blur radius", \.backdropBlurRadius, 0...120)
                    IntTweak("Bands", \.backdropBands, 1...12)
                    Tweak("Ramp power", \.backdropRampPower, 0.5...4, step: 0.1)
                    Tweak("Tint", \.backdropTint, 0...1, step: 0.05)
                    Tweak("Tint start", \.backdropTintStart, 0...1, step: 0.05)
                    Tweak("Fade in", \.backdropFadeIn, 0...1.5, step: 0.05, unit: "s")
                    Tweak("Fade out", \.backdropFadeOut, 0...1.5, step: 0.05, unit: "s")
                    Tweak("Slide in", \.backdropSlideIn, 0...1.5, step: 0.05, unit: "s")
                    Tweak("Slide out", \.backdropSlideOut, 0...1.5, step: 0.05, unit: "s")
                    Tweak("Dim behind annotator", \.dimOpacity, 0...0.9, step: 0.05)
                    Tweak("Dim blur", \.dimBlurRadius, 0...60, step: 1, unit: "pt")
                    Tweak("Dim fade", \.dimFade, 0...1, step: 0.05, unit: "s")
                }
                Section("Annotator") {
                    Tweak("Min width", \.annotationMinWidth, 200...1200, step: 10)
                    Tweak("Min height", \.annotationMinHeight, 100...900, step: 10)
                    Tweak("Screen inset", \.annotationScreenInset, 0...200, step: 5)
                    Tweak("Corner radius", \.annotationCornerRadius, 0...30)
                    Tweak("Toolbar gap", \.annotationToolbarGap, 0...40)
                }
                Section("Stitch") {
                    Tweak("Long side", \.stitchLongSide, 512...8192, step: 128, unit: "px")
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Reset UI to defaults") { settings.update { $0.ui = UITweaks() } }
                Spacer()
                Button("Reveal settings.json") { NSWorkspace.shared.activateFileViewerSelecting([Settings.fileURL]) }
            }
            .padding(10)
        }
        .frame(minWidth: 380, minHeight: 500)
    }

    private func binding<T>(_ path: WritableKeyPath<UITweaks, T>) -> Binding<T> {
        Binding(get: { settings.data.ui[keyPath: path] }, set: { v in settings.update { $0.ui[keyPath: path] = v } })
    }
}

@MainActor
private struct Tweak: View {
    let label: String
    let path: WritableKeyPath<UITweaks, Double>
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit = ""
    @ObservedObject private var settings = Settings.shared

    init(_ label: String, _ path: WritableKeyPath<UITweaks, Double>, _ range: ClosedRange<Double>, step: Double = 1, unit: String = "") {
        self.label = label; self.path = path; self.range = range; self.step = step; self.unit = unit
    }

    var body: some View {
        let value = settings.data.ui[keyPath: path]
        HStack {
            Text(label).frame(width: 140, alignment: .leading)
            Slider(value: Binding(get: { value }, set: { v in settings.update { $0.ui[keyPath: path] = v } }), in: range, step: step)
            Text(step < 1 ? String(format: "%.2f", value) + unit : "\(Int(value))\(unit)")
                .monospacedDigit().font(.caption).frame(width: 52, alignment: .trailing)
        }
    }
}

@MainActor
private struct IntTweak: View {
    let label: String
    let path: WritableKeyPath<UITweaks, Int>
    let range: ClosedRange<Int>
    @ObservedObject private var settings = Settings.shared

    init(_ label: String, _ path: WritableKeyPath<UITweaks, Int>, _ range: ClosedRange<Int>) {
        self.label = label; self.path = path; self.range = range
    }

    var body: some View {
        let value = settings.data.ui[keyPath: path]
        HStack {
            Text(label).frame(width: 140, alignment: .leading)
            Slider(value: Binding(get: { Double(value) }, set: { v in settings.update { $0.ui[keyPath: path] = Int(v.rounded()) } }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
            Text("\(value)").monospacedDigit().font(.caption).frame(width: 52, alignment: .trailing)
        }
    }
}
