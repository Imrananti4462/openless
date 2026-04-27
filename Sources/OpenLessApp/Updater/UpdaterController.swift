import AppKit
import Sparkle

/// Sparkle 更新通道：启动时自动检查、菜单「检查更新…」手动触发、新版本弹窗由 Sparkle 内置 UI 提供。
/// 默认配置：
/// - SUFeedURL：appcast.xml 的 raw GitHub URL（写在 Info.plist）
/// - SUPublicEDKey：EdDSA 公钥（写在 Info.plist）；私钥只在发版机的 Keychain 里
/// - 启动后台后约 30s 做首次检查；之后每小时一次（也可在 Info.plist 调整）
@MainActor
final class UpdaterController: NSObject {
    let updater: SPUStandardUpdaterController

    override init() {
        self.updater = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    /// 菜单项 target = self，action = #selector(checkForUpdates(_:))
    @objc func checkForUpdates(_ sender: Any?) {
        updater.checkForUpdates(sender)
    }
}
