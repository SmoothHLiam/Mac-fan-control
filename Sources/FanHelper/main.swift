import Foundation
import FanCore

/// Root daemon. Deliberately tiny: it exposes "set a fan target" and "release", clamps to the hardware's own
/// limits, and hands control back to macOS whenever the app goes quiet.
final class HelperService: NSObject, FanHelperProtocol, NSXPCListenerDelegate {
    private let smc: SMCClient
    private let queue = DispatchQueue(label: "com.macfancontrol.helper.smc")
    private var manualFans = Set<Int>()
    private var lastCommand = Date()
    private var limits: [Int: FanHardwareInfo] = [:]
    private var watchdog: DispatchSourceTimer?

    init(smc: SMCClient) {
        self.smc = smc
        super.init()
        for info in smc.fanHardware() { limits[info.index] = info }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2, leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in self?.checkWatchdog() }
        timer.resume()
        watchdog = timer
    }

    private func checkWatchdog() {
        guard !manualFans.isEmpty, Date().timeIntervalSince(lastCommand) > 6 else { return }
        releaseEverything()
    }

    private func releaseEverything() {
        smc.releaseAllFans()
        manualFans.removeAll()
    }

    func shutdown() {
        queue.sync { releaseEverything() }
    }

    // MARK: NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: FanHelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    // MARK: FanHelperProtocol

    func setFanTarget(_ fan: Int, rpm: Double, reply: @escaping (String?) -> Void) {
        queue.async {
            guard let hw = self.limits[fan] else { return reply("Unknown fan \(fan)") }
            guard rpm.isFinite else { return reply("Invalid RPM") }
            let clamped = min(max(rpm, hw.minRPM), hw.maxRPM)
            self.lastCommand = Date()
            if let error = self.smc.setManualTarget(fan: fan, rpm: clamped) {
                return reply(error)
            }
            self.manualFans.insert(fan)
            reply(nil)
        }
    }

    func releaseFan(_ fan: Int, reply: @escaping () -> Void) {
        queue.async {
            self.smc.releaseFan(fan)
            self.manualFans.remove(fan)
            if self.manualFans.isEmpty { self.smc.releaseAllFans() }   // also clears the Ftst unlock
            reply()
        }
    }

    func releaseAllFans(reply: @escaping () -> Void) {
        queue.async {
            self.releaseEverything()
            reply()
        }
    }

    func protocolVersion(reply: @escaping (Int) -> Void) {
        reply(HelperConstants.protocolVersion)
    }
}

guard geteuid() == 0 else {
    FileHandle.standardError.write(Data("FanHelper must run as root (it is launched by launchd).\n".utf8))
    exit(1)
}
guard let smc = SMCClient() else {
    FileHandle.standardError.write(Data("Could not open AppleSMC.\n".utf8))
    exit(2)
}

let service = HelperService(smc: smc)
let listener = NSXPCListener(machServiceName: HelperConstants.machService)
listener.setConnectionCodeSigningRequirement(HelperConstants.appRequirement)
listener.delegate = service
listener.resume()

// Whatever ends this process, give the fans back first.
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGTERM, SIGINT, SIGHUP] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
        service.shutdown()
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}

RunLoop.main.run()
