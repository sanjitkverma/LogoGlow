import SwiftUI
import AppKit

// MARK: - Controller

/// Talks to CoreBrightness. Needs admin rights, so commands go through
/// osascript's "with administrator privileges" (the standard macOS password prompt).
final class LogoController: ObservableObject {
    @Published var isOn: Bool
    @Published var busy = false
    @Published var message: String?

    private let key = "logoIsOn"

    init() {
        let stored = UserDefaults.standard.object(forKey: key) as? Bool
        isOn = Self.readSystemState() ?? stored ?? true
    }

    /// Root's preference file usually isn't readable, so this often returns nil
    /// and we fall back to the last state this app set.
    static func readSystemState() -> Bool? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p.arguments = ["read", "/var/root/Library/Preferences/com.apple.CoreBrightness", "LEBacklightMode"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s == "0" ? false : true
    }

    static let offArgs = ["/usr/bin/defaults", "write", "com.apple.CoreBrightness", "LEBacklightMode", "-int", "0"]
    static let onArgs  = ["/usr/bin/defaults", "delete", "com.apple.CoreBrightness", "LEBacklightMode"]
    static let rulePath = "/etc/sudoers.d/logoglow"

    /// True when the one-time permission rule is installed.
    @Published var remembered = FileManager.default.fileExists(atPath: LogoController.rulePath)

    /// Sudo rule that lets only this user run only the two logo commands, without a password.
    private static var ruleLine: String {
        "\(NSUserName()) ALL=(root) NOPASSWD: \(offArgs.joined(separator: " ")), \(onArgs.joined(separator: " "))"
    }

    private static func run(_ path: String, _ args: [String]) -> (ok: Bool, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let err = Pipe()
        p.standardError = err
        p.standardOutput = Pipe()
        do { try p.run() } catch { return (false, error.localizedDescription) }
        p.waitUntilExit()
        let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (p.terminationStatus == 0, e)
    }

    /// Runs a shell command as root through the macOS password prompt.
    private static func runAsAdmin(_ shell: String, prompt: String) -> (ok: Bool, err: String) {
        let script = "do shell script \"\(shell)\" with prompt \"\(prompt)\" with administrator privileges"
        return run("/usr/bin/osascript", ["-e", script])
    }

    func set(_ on: Bool, completion: @escaping (Bool) -> Void) {
        guard !busy else { return }
        busy = true
        message = nil
        let args = on ? Self.onArgs : Self.offArgs

        DispatchQueue.global(qos: .userInitiated).async {
            // 1. Already approved once? Run without a password.
            var result = Self.run("/usr/bin/sudo", ["-n"] + args)
            if !result.ok && on {
                // "delete" fails when the key is already gone, which means it's already on.
                result = Self.run("/usr/bin/sudo", ["-n", "-l"] + args)
            }

            // 2. Otherwise ask once, and save the permission rule at the same time.
            if !result.ok {
                let cmd = args.joined(separator: " ") + (on ? " 2>/dev/null; true" : "")
                let tmp = NSTemporaryDirectory() + "logoglow-sudoers"
                try? (Self.ruleLine + "\n").write(toFile: tmp, atomically: true, encoding: .utf8)
                // Copy as root first, then validate the copied file; remove it if invalid.
                let install = "/usr/bin/install -m 0440 -o root -g wheel '\(tmp)' \(Self.rulePath) && "
                    + "(/usr/sbin/visudo -cf \(Self.rulePath) >/dev/null || /bin/rm -f \(Self.rulePath))"
                let prompt = (on ? "LogoGlow wants to light up your Apple logo."
                                 : "LogoGlow wants to turn off your Apple logo.")
                    + " You won't be asked again."
                result = Self.runAsAdmin("\(cmd); \(install); true", prompt: prompt)
                try? FileManager.default.removeItem(atPath: tmp)
            }

            DispatchQueue.main.async {
                self.busy = false
                self.remembered = FileManager.default.fileExists(atPath: Self.rulePath)
                if result.ok {
                    self.isOn = on
                    UserDefaults.standard.set(on, forKey: self.key)
                } else if result.err.contains("-128") {
                    self.message = "Cancelled."
                } else {
                    self.message = "Couldn't change the logo. " + result.err.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                completion(result.ok)
            }
        }
    }

    /// Removes the saved permission so the password is asked every time again.
    func forgetPermission() {
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Self.runAsAdmin("/bin/rm -f \(Self.rulePath)",
                                    prompt: "LogoGlow wants to remove its saved permission.")
            DispatchQueue.main.async {
                self.remembered = FileManager.default.fileExists(atPath: Self.rulePath)
                if !r.ok && !r.err.contains("-128") { self.message = "Couldn't remove the permission." }
            }
        }
    }
}

// MARK: - Glowing logo

struct GlowingApple: View {
    /// 0 = dark, 1 = fully lit
    var glow: Double
    var breathe: Double
    var size: CGFloat = 170

    private var logo: some View {
        Image(systemName: "apple.logo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }

    var body: some View {
        let g = glow * (0.88 + 0.12 * breathe)
        ZStack {
            // Light bloom on the "lid"
            RadialGradient(colors: [Color.white.opacity(0.22 * g), .clear],
                           center: .center, startRadius: 0, endRadius: size * 1.4)
                .frame(width: size * 3, height: size * 3)
                .blendMode(.screen)

            // Unlit, etched logo
            logo
                .foregroundStyle(
                    LinearGradient(colors: [Color(white: 0.16), Color(white: 0.09)],
                                   startPoint: .top, endPoint: .bottom))
                .overlay(
                    logo.foregroundStyle(.clear)
                        .shadow(color: .white.opacity(0.07), radius: 0.5, x: 0, y: 1)
                )
                .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: -1)

            // Wide soft glow: blurred copies of the logo
            logo.foregroundStyle(Color(red: 0.82, green: 0.9, blue: 1))
                .padding(size * 0.5)
                .blur(radius: 48)
                .opacity(0.75 * g)
            logo.foregroundStyle(.white)
                .padding(size * 0.3)
                .blur(radius: 16)
                .opacity(0.8 * g)

            // Lit logo
            logo
                .foregroundStyle(
                    LinearGradient(colors: [.white, Color(white: 0.9)],
                                   startPoint: .top, endPoint: .bottom))
                .shadow(color: .white.opacity(0.9), radius: 4)
                .opacity(g)
        }
    }
}

struct Ripple: View {
    var progress: Double
    var body: some View {
        Circle()
            .stroke(Color.white.opacity(0.5 * (1 - progress)), lineWidth: 2)
            .frame(width: 120 + 340 * progress, height: 120 + 340 * progress)
            .blur(radius: 2 + 6 * progress)
    }
}

// MARK: - Main window

struct ContentView: View {
    @EnvironmentObject var controller: LogoController
    @State private var glow: Double = 0
    @State private var breathe: Double = 0
    @State private var ripple: Double = 1
    @State private var hovering = false

    var body: some View {
        ZStack {
            // Space-black aluminium lid
            LinearGradient(colors: [Color(white: 0.13), Color(white: 0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            BrushedTexture().opacity(0.35).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                ZStack {
                    Ripple(progress: ripple)
                    GlowingApple(glow: glow, breathe: breathe)
                        .scaleEffect(hovering ? 1.03 : 1)
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: hovering)
                }
                .frame(height: 300)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .onTapGesture { toggle() }
                .help(controller.isOn ? "Turn the Apple logo off" : "Turn the Apple logo on")

                Spacer()

                VStack(spacing: 10) {
                    Text(controller.isOn ? "GLOWING" : "DARK")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .tracking(6)
                        .foregroundStyle(.white.opacity(0.35 + 0.5 * glow))
                        .contentTransition(.opacity)

                    Group {
                        if controller.busy {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text(controller.remembered ? "Switching…" : "Waiting for your password…")
                            }
                        } else if let m = controller.message {
                            Text(m).foregroundStyle(.orange.opacity(0.85))
                        } else {
                            Text(controller.isOn ? "Click the Apple to switch it off"
                                                 : "Click the Apple to bring it back")
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .frame(height: 32)
                }
                .padding(.bottom, 28)
                .padding(.horizontal, 24)
            }
        }
        .frame(width: 420, height: 520)
        .onAppear {
            glow = controller.isOn ? 1 : 0
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathe = 1 }
        }
        .onChange(of: controller.isOn) { _, on in
            on ? ignite() : powerDown()
        }
    }

    private func toggle() {
        controller.set(!controller.isOn) { _ in }
    }

    /// Flickers like a dying bulb, then fades out.
    private func powerDown() {
        Task { @MainActor in
            let steps: [(Double, Double)] = [(0.25, 0.05), (0.95, 0.06), (0.15, 0.05),
                                             (0.7, 0.08), (0.05, 0.05), (0.4, 0.07)]
            for (v, t) in steps {
                withAnimation(.linear(duration: t)) { glow = v }
                try? await Task.sleep(for: .seconds(t))
            }
            withAnimation(.easeOut(duration: 0.9)) { glow = 0 }
        }
    }

    /// Flashes on with a light ripple, then settles.
    private func ignite() {
        Task { @MainActor in
            withAnimation(.easeIn(duration: 0.08)) { glow = 0.3 }
            try? await Task.sleep(for: .seconds(0.12))
            withAnimation(.easeIn(duration: 0.06)) { glow = 0.05 }
            try? await Task.sleep(for: .seconds(0.1))
            ripple = 0
            withAnimation(.easeOut(duration: 1.1)) { ripple = 1 }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.55)) { glow = 1 }
        }
    }
}

/// Subtle horizontal brushed-metal lines.
struct BrushedTexture: View {
    var body: some View {
        Canvas { ctx, size in
            var rng = SystemRandomNumberGenerator()
            var y: CGFloat = 0
            while y < size.height {
                let a = Double.random(in: 0.0...0.05, using: &rng)
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                         with: .color(.white.opacity(a)))
                y += CGFloat.random(in: 1...3, using: &rng)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Menu bar

struct MenuContent: View {
    @EnvironmentObject var controller: LogoController
    var body: some View {
        Button(controller.isOn ? "Turn Apple Logo Off" : "Turn Apple Logo On") {
            controller.set(!controller.isOn) { _ in }
        }
        .disabled(controller.busy)
        if controller.remembered {
            Button("Ask for Password Again") { controller.forgetPermission() }
        }
        Divider()
        Button("Quit LogoGlow") { NSApp.terminate(nil) }
    }
}

// MARK: - App

@main
struct LogoGlowApp: App {
    @StateObject private var controller = LogoController()

    var body: some Scene {
        Window("LogoGlow", id: "main") {
            ContentView().environmentObject(controller)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuContent().environmentObject(controller)
        } label: {
            Image(systemName: "apple.logo")
                .opacity(controller.isOn ? 1 : 0.4)
        }
    }
}
