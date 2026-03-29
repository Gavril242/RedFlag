import Foundation
import SwiftUI
import Combine
import UIKit

#if canImport(UnityFramework)
import UnityFramework
#endif

enum OverrideUnityBridgeConfig {
    static let serverURLDefaultsKey = "redflag.server_url"
    static let teamIDDefaultsKey = "redflag.team_id"
    static let usernameDefaultsKey = "redflag.username"
}

extension Notification.Name {
    static let overrideUnityConfigDidChange = Notification.Name("OverrideUnityConfigDidChange")
}

#if canImport(UnityFramework)
final class UnityManager: NSObject, ObservableObject, UnityFrameworkListener {
    static let shared = UnityManager()

    internal var ufw: UnityFramework?
    @Published var isReady = false

    private override init() {
        super.init()
    }

    func loadUnity() {
        if isReady { return }

        let frameworkPath = Bundle.main.bundlePath + "/Frameworks/UnityFramework.framework"
        guard let bundle = Bundle(path: frameworkPath) else {
            print("[UnityManager] UnityFramework.framework not found at \(frameworkPath)")
            return
        }

        if !bundle.isLoaded {
            bundle.load()
        }

        guard let ufw = UnityFramework.getInstance() else {
            print("[UnityManager] UnityFramework.getInstance() returned nil")
            return
        }

        self.ufw = ufw
        ufw.setDataBundleId(Bundle.main.bundleIdentifier ?? "")
        ufw.register(self)
        ufw.runEmbedded(
            withArgc: CommandLine.argc,
            argv: CommandLine.unsafeArgv,
            appLaunchOpts: nil
        )

        ufw.appController()?.quitHandler = {
            print("[UnityManager] Intercepted Unity quit request")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let unityWindow = self.ufw?.appController()?.window {
                unityWindow.windowLevel = UIWindow.Level.normal - 1
                unityWindow.isHidden = true
            }
        }

        setServerURL(OverrideSession.baseURL)
        isReady = true
    }

    func setServerURL(_ rawValue: String) {
        UserDefaults.standard.set(rawValue, forKey: OverrideUnityBridgeConfig.serverURLDefaultsKey)
        NotificationCenter.default.post(name: .overrideUnityConfigDidChange, object: nil)
    }

    func sendMessage(gameObject: String, methodName: String, message: String) {
        ufw?.sendMessageToGO(withName: gameObject, functionName: methodName, message: message)
    }

    func unityView() -> UIView? {
        ufw?.appController()?.rootViewController?.view
    }

    func unityDidUnload(_ notification: Notification!) {
        ufw?.unregisterFrameworkListener(self)
        ufw = nil
        isReady = false
    }
}
#else
final class UnityManager: NSObject, ObservableObject {
    static let shared = UnityManager()

    @Published var isReady = false

    func loadUnity() {
        print("[UnityManager] UnityFramework module is unavailable for this build configuration.")
    }

    func setServerURL(_ rawValue: String) {}

    func sendMessage(gameObject: String, methodName: String, message: String) {}

    func unityView() -> UIView? { nil }
}
#endif

// MARK: - Safe Hosting Controller

final class UnityHostViewController: UIViewController {
    private let fallbackLabel: UILabel = {
        let label = UILabel()
        label.text = "Unity build pending"
        label.textColor = .white
        label.font = UIFont.monospacedSystemFont(ofSize: 16, weight: .semibold)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        fallbackLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fallbackLabel)
        NSLayoutConstraint.activate([
            fallbackLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            fallbackLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            fallbackLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            fallbackLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
        UnityManager.shared.loadUnity()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if let unityView = UnityManager.shared.unityView() {
            fallbackLabel.isHidden = true
            if unityView.superview != view {
                unityView.frame = view.bounds
                unityView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                unityView.isUserInteractionEnabled = true
                view.addSubview(unityView)
                view.subviews.forEach { if $0 != unityView { view.bringSubviewToFront($0) } }
            } else {
                unityView.frame = view.bounds
            }
        } else {
            fallbackLabel.isHidden = false
        }
    }
}

struct UnityViewRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UnityHostViewController {
        UnityHostViewController()
    }

    func updateUIViewController(_ uiViewController: UnityHostViewController, context: Context) {}
}
