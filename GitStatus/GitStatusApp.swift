import SwiftUI

@main
struct GitStatusApp: App {
    @State private var store = RepoStore()
    @State private var monitor: GitMonitor?
    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(store: store, monitor: monitor)
                .frame(width: 340, height: 420)
        } label: {
            Image(nsImage: menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        Window("GitStatus Settings", id: "settings") {
            SettingsView(store: store)
                .frame(minWidth: 500, minHeight: 400)
        }
        .defaultSize(width: 560, height: 480)
    }

    private var menuBarIcon: NSImage {
        let count = store.nonGreenCount
        let badgeColor: NSColor = switch store.worstState {
        case .clean: .systemGreen
        case .uncommitted: .systemYellow
        case .notPushed: .systemOrange
        case .behind: .systemRed
        }

        let height: CGFloat = 18
        let iconSize: CGFloat = 16
        let badgeText = count > 0 ? "\(count)" : nil
        let badgeFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)

        // Measure badge width if needed
        var badgeWidth: CGFloat = 0
        var textSize: CGSize = .zero
        if let badgeText {
            let attrs: [NSAttributedString.Key: Any] = [.font: badgeFont]
            textSize = (badgeText as NSString).size(withAttributes: attrs)
            badgeWidth = max(textSize.width + 8, height)
        }

        let totalWidth = iconSize + (badgeText != nil ? 3 + badgeWidth : 0)

        let image = NSImage(size: NSSize(width: totalWidth, height: height), flipped: false) { rect in
            // Draw the SF Symbol in white
            if let symbol = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                let configured = symbol.withSymbolConfiguration(config) ?? symbol
                let symbolSize = configured.size
                let symbolRect = NSRect(
                    x: 0,
                    y: (height - symbolSize.height) / 2,
                    width: symbolSize.width,
                    height: symbolSize.height
                )
                configured.lockFocus()
                NSColor.white.set()
                NSRect(origin: .zero, size: configured.size).fill(using: .sourceAtop)
                configured.unlockFocus()
                configured.draw(in: symbolRect)
            }

            // Draw badge
            if let badgeText {
                let badgeRect = NSRect(x: iconSize + 3, y: (height - height * 0.78) / 2, width: badgeWidth, height: height * 0.78)
                let path = NSBezierPath(roundedRect: badgeRect, xRadius: badgeRect.height / 2, yRadius: badgeRect.height / 2)
                badgeColor.setFill()
                path.fill()

                let attrs: [NSAttributedString.Key: Any] = [
                    .font: badgeFont,
                    .foregroundColor: NSColor.white,
                ]
                let textRect = NSRect(
                    x: badgeRect.midX - textSize.width / 2,
                    y: badgeRect.midY - textSize.height / 2,
                    width: textSize.width,
                    height: textSize.height
                )
                (badgeText as NSString).draw(in: textRect, withAttributes: attrs)
            }

            return true
        }

        image.isTemplate = false
        return image
    }

    init() {
        let s = RepoStore()
        LoginItem.restoreIfNeeded(wanted: s.config.launchAtLogin)
        _store = State(initialValue: s)
        let m = GitMonitor(store: s)
        _monitor = State(initialValue: m)
        m.start()
    }
}
