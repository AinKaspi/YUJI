import UIKit

// MARK: - Класс PersonViewController
// Этот класс отвечает за страницу "Person" (Профиль пользователя).
// Он отображает имя, аватар, уровень и список достижений.
// Реализует протокол UITableViewDataSource для управления таблицей достижений.
class PersonViewController: UIViewController, UITableViewDataSource {
    
    // MARK: - Свойства
    // Модель профиля пользователя.
    // Мы используем тестовые данные из UserProfile.testProfile.
    private let userProfile = UserProfile.testProfile
    
    // UI-элемент: Аватар пользователя.
    // UIImageView отображает изображение (пока системную иконку).
    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit // Сохраняем пропорции изображения
        imageView.translatesAutoresizingMaskIntoConstraints = false // Отключаем autoresizing для Auto Layout
        return imageView
    }()
    
    // UI-элемент: Метка для имени пользователя.
    // UILabel отображает текст (имя).
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 24, weight: .bold) // Шрифт: 24pt, жирный
        label.textAlignment = .center // Выравнивание по центру
        label.translatesAutoresizingMaskIntoConstraints = false // Отключаем autoresizing
        return label
    }()
    
    // UI-элемент: Метка для уровня пользователя.
    // UILabel отображает текст (уровень).
    private let levelLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 18) // Шрифт: 18pt
        label.textAlignment = .center // Выравнивание по центру
        label.translatesAutoresizingMaskIntoConstraints = false // Отключаем autoresizing
        return label
    }()
    
    // UI-элемент: Таблица для списка достижений.
    // UITableView отображает список достижений в виде строк.
    private let achievementsTableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false // Отключаем autoresizing
        return tableView
    }()
    
    // MARK: - Жизненный цикл
    // Метод viewDidLoad вызывается, когда контроллер загружается в память.
    // Здесь мы настраиваем UI и заполняем его данными.
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI() // Настраиваем UI
        configureData() // Заполняем UI данными
    }
    
    // MARK: - Функция: Настройка UI
    // Эта функция добавляет UI-элементы на экран и настраивает их расположение.
    // Использует Auto Layout для размещения элементов.
    private func setupUI() {
        // Устанавливаем белый фон для экрана
        view.backgroundColor = .white
        
        // Добавляем UI-элементы на экран (в иерархию view)
        view.addSubview(avatarImageView)
        view.addSubview(nameLabel)
        view.addSubview(levelLabel)
        view.addSubview(achievementsTableView)
        
        // Настраиваем таблицу достижений
        achievementsTableView.dataSource = self // Указываем, что этот класс управляет данными таблицы
        // Регистрируем ячейку для таблицы (используем стандартную ячейку UITableViewCell)
        achievementsTableView.register(UITableViewCell.self, forCellReuseIdentifier: "AchievementCell")
        
        // Настраиваем Auto Layout (ограничения для расположения элементов)
        NSLayoutConstraint.activate([
            // Аватар: размещаем вверху экрана, по центру, размер 100x100
            avatarImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            avatarImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 100),
            avatarImageView.heightAnchor.constraint(equalToConstant: 100),
            
            // Имя: размещаем под аватаром, с отступом 10pt, растягиваем на всю ширину с отступами по краям
            nameLabel.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 10),
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            // Уровень: размещаем под именем, с отступом 10pt, растягиваем на всю ширину
            levelLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 10),
            levelLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            levelLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            // Таблица достижений: размещаем под уровнем, растягиваем до низа экрана
            achievementsTableView.topAnchor.constraint(equalTo: levelLabel.bottomAnchor, constant: 20),
            achievementsTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            achievementsTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            achievementsTableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    // MARK: - Функция: Заполнение UI данными
    // Эта функция берёт данные из модели userProfile и заполняет ими UI-элементы.
    private func configureData() {
        // Устанавливаем изображение для аватара (системная иконка)
        avatarImageView.image = UIImage(systemName: userProfile.avatarImageName)
        
        // Устанавливаем текст для имени
        nameLabel.text = userProfile.name
        
        // Устанавливаем текст для уровня (форматируем строку)
        levelLabel.text = "Уровень: \(userProfile.level)"
        
        // Таблица достижений обновится автоматически через UITableViewDataSource
    }
    
    // MARK: - UITableViewDataSource
    // Эти методы нужны для управления таблицей достижений.
    
    // Метод возвращает количество строк в таблице (равно количеству достижений).
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return userProfile.achievements.count
    }
    
    // Метод создаёт и настраивает ячейку для каждой строки таблицы.
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // Получаем ячейку из пула (с идентификатором "AchievementCell")
        let cell = tableView.dequeueReusableCell(withIdentifier: "AchievementCell", for: indexPath)
        
        // Устанавливаем текст ячейки (достижение из списка)
        cell.textLabel?.text = userProfile.achievements[indexPath.row]
        
        return cell
    }
}
