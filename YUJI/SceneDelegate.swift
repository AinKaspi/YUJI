import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    
    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        print("SceneDelegate: Настройка окна")
        guard let windowScene = (scene as? UIWindowScene) else { return }
        let window = UIWindow(windowScene: windowScene)
        let startVC = StartViewController()
        let navController = UINavigationController(rootViewController: startVC)
        window.rootViewController = navController
        self.window = window
        window.makeKeyAndVisible()
    }
}
