import Foundation
import ServiceManagement
import FanCore

/// App side of the XPC link to the privileged helper.
final class HelperClient: FanActuator {
    private var connection: NSXPCConnection?

    private func proxy(onError: @escaping (Error) -> Void) -> FanHelperProtocol? {
        if connection == nil {
            let c = NSXPCConnection(machServiceName: HelperConstants.machService, options: .privileged)
            c.remoteObjectInterface = NSXPCInterface(with: FanHelperProtocol.self)
            c.setCodeSigningRequirement(HelperConstants.helperRequirement)
            let drop: () -> Void = { [weak self] in DispatchQueue.main.async { self?.connection = nil } }
            c.invalidationHandler = drop
            c.interruptionHandler = drop
            c.resume()
            connection = c
        }
        return connection?.remoteObjectProxyWithErrorHandler { onError($0) } as? FanHelperProtocol
    }

    func setTarget(fan: Int, rpm: Double, completion: @escaping (String?, Bool) -> Void) {
        guard let p = proxy(onError: { _ in DispatchQueue.main.async { completion(nil, true) } }) else {
            return completion(nil, true)
        }
        p.setFanTarget(fan, rpm: rpm) { error in
            DispatchQueue.main.async { completion(error, false) }
        }
    }

    func release(fan: Int) {
        proxy(onError: { _ in })?.releaseFan(fan, reply: {})
    }

    func releaseAllBlocking() {
        let done = DispatchSemaphore(value: 0)
        guard let p = proxy(onError: { _ in done.signal() }) else { return }
        p.releaseAllFans { done.signal() }
        _ = done.wait(timeout: .now() + 1.5)
    }

    /// True if a helper answers on the mach service and speaks our protocol version.
    func ping(completion: @escaping (Bool) -> Void) {
        var finished = false
        let finish: (Bool) -> Void = { ok in
            DispatchQueue.main.async {
                guard !finished else { return }
                finished = true
                completion(ok)
            }
        }
        guard let p = proxy(onError: { _ in finish(false) }) else { return finish(false) }
        p.protocolVersion { v in finish(v == HelperConstants.protocolVersion) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { finish(false) }
    }
}

/// Registration of the helper as a launch daemon bundled inside the app (`Contents/Library/LaunchDaemons`).
enum HelperInstaller {
    private static var service: SMAppService { SMAppService.daemon(plistName: HelperConstants.daemonPlist) }

    enum State { case notRegistered, requiresApproval, enabled, notFound }

    static var state: State {
        switch service.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        default: return .notRegistered
        }
    }

    static func register() throws {
        try service.register()
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    static func unregister() throws {
        try service.unregister()
    }

    static func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Login item change failed: \(error)")
        }
    }
}
