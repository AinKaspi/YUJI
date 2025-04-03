import UIKit
import os.log

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    
    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        os_log("SceneDelegate: Настройка окна", log: OSLog.default, type: .debug)
        guard let windowScene = (scene as? UIWindowScene) else { return }
        let window = UIWindow(windowScene: windowScene)
        
        // Используем MainTabBarController как основной корневой контроллер
        let mainTabBarController = MainTabBarController()
        window.rootViewController = mainTabBarController
        
        self.window = window
        window.makeKeyAndVisible()
    }
}
