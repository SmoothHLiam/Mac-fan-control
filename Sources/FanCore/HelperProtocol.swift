#if canImport(ObjectiveC)
import Foundation

public enum HelperConstants {
    public static let machService = "com.macfancontrol.helper"
    public static let appIdentifier = "com.macfancontrol.app"
    public static let helperIdentifier = "com.macfancontrol.helper"
    public static let daemonPlist = "com.macfancontrol.helper.plist"
    public static let protocolVersion = 1

    /// Code-signing requirement the helper enforces on its client (and the app on the helper).
    /// Ad-hoc builds can only pin the identifier. For distribution, replace with a Team ID requirement:
    ///   identifier "com.macfancontrol.app" and anchor apple generic and certificate leaf[subject.OU] = "TEAMID"
    public static let appRequirement = "identifier \"\(appIdentifier)\""
    public static let helperRequirement = "identifier \"\(helperIdentifier)\""
}

/// XPC contract between the app and the root helper. Every call that sets a target doubles as a heartbeat:
/// if none arrives for a few seconds the helper hands the fans back to macOS.
@objc public protocol FanHelperProtocol {
    func setFanTarget(_ fan: Int, rpm: Double, reply: @escaping (String?) -> Void)
    func releaseFan(_ fan: Int, reply: @escaping () -> Void)
    func releaseAllFans(reply: @escaping () -> Void)
    func protocolVersion(reply: @escaping (Int) -> Void)
}
#endif
