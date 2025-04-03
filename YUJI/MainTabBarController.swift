import UIKit
import os.log

/// Главный контроллер вкладок приложения
class MainTabBarController: UITabBarController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupViewControllers()
        os_log("MainTabBarController: Инициализирован", log: OSLog.default, type: .debug)
    }
    
    private func setupViewControllers() {
        // Создаем контроллер выбора упражнений
        let exerciseSelectionVC = ExerciseSelectionViewController()
        let exerciseSelectionNav = UINavigationController(rootViewController: exerciseSelectionVC)
        exerciseSelectionNav.tabBarItem = UITabBarItem(
            title: "Упражнения",
            image: UIImage(systemName: "figure.walk"),
            selectedImage: UIImage(systemName: "figure.walk.circle.fill")
        )
        
        // Создаем контроллер статистики
        let statsVC = WorkoutStatsViewController()
        let statsNav = UINavigationController(rootViewController: statsVC)
        statsNav.tabBarItem = UITabBarItem(
            title: "Статистика",
            image: UIImage(systemName: "chart.bar"),
            selectedImage: UIImage(systemName: "chart.bar.fill")
        )
        
        // Создаем контроллер профиля (заглушка)
        let profileVC = UIViewController()
        profileVC.view.backgroundColor = .systemBackground
        profileVC.title = "Профиль"
        let profileNav = UINavigationController(rootViewController: profileVC)
        profileNav.tabBarItem = UITabBarItem(
            title: "Профиль",
            image: UIImage(systemName: "person"),
            selectedImage: UIImage(systemName: "person.fill")
        )
        
        // Устанавливаем контроллеры
        self.viewControllers = [exerciseSelectionNav, statsNav, profileNav]
        
        // Устанавливаем первую вкладку по умолчанию
        self.selectedIndex = 0
        
        // Настройка внешнего вида
        if #available(iOS 15.0, *) {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
        }
    }
}
