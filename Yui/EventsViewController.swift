import UIKit

// MARK: - Класс EventsViewController
// Этот класс отвечает за страницу "Events" (Ежедневные задания).
// Отображает список заданий, текущий ранг и позволяет отмечать задания как выполненные.
// Реализует протоколы UITableViewDataSource и UITableViewDelegate для управления таблицей.
class EventsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    // MARK: - Свойства
    // Список заданий.
    // Используем тестовые данные из DailyTask.testTasks.
    // Массив является изменяемым, чтобы мы могли обновлять статус выполнения.
    private var tasks: [DailyTask] = DailyTask.testTasks
    
    // Текущий ранг пользователя.
    // Рассчитывается на основе количества выполненных заданий.
    private var currentRank: Rank {
        let completedTasks = tasks.filter { $0.isCompleted }.count
        return Rank.rank(for: completedTasks)
    }
    
    // UI-элемент: Метка для отображения текущего ранга.
    private let rankLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 24, weight: .bold) // Шрифт: 24pt, жирный
        label.textAlignment = .center // Выравнивание по центру
        label.translatesAutoresizingMaskIntoConstraints = false // Отключаем autoresizing
        return label
    }()
    
    // UI-элемент: Таблица для списка заданий.
    private let tasksTableView: UITableView = {
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
        updateRankLabel() // Обновляем метку ранга
    }
    
    // MARK: - Функция: Настройка UI
    // Эта функция добавляет UI-элементы на экран и настраивает их расположение.
    // Использует Auto Layout для размещения элементов.
    private func setupUI() {
        // Устанавливаем белый фон для экрана
        view.backgroundColor = .white
        
        // Добавляем UI-элементы на экран
        view.addSubview(rankLabel)
        view.addSubview(tasksTableView)
        
        // Настраиваем таблицу заданий
        tasksTableView.dataSource = self // Указываем, что этот класс управляет данными таблицы
        tasksTableView.delegate = self // Указываем, что этот класс управляет поведением таблицы
        // Регистрируем кастомную ячейку для таблицы
        tasksTableView.register(TaskTableViewCell.self, forCellReuseIdentifier: "TaskCell")
        
        // Настраиваем Auto Layout
        NSLayoutConstraint.activate([
            // Метка ранга: размещаем вверху экрана, по центру
            rankLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            rankLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            rankLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            // Таблица заданий: размещаем под меткой ранга, растягиваем до низа экрана
            tasksTableView.topAnchor.constraint(equalTo: rankLabel.bottomAnchor, constant: 20),
            tasksTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tasksTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tasksTableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    // MARK: - Функция: Обновление метки ранга
    // Эта функция обновляет текст в метке ранга на основе текущего ранга.
    private func updateRankLabel() {
        rankLabel.text = "Ваш ранг: \(currentRank.rawValue)"
    }
    
    // MARK: - UITableViewDataSource
    // Эти методы нужны для управления таблицей заданий.
    
    // Метод возвращает количество строк в таблице (равно количеству заданий).
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return tasks.count
    }
    
    // Метод создаёт и настраивает ячейку для каждой строки таблицы.
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // Получаем ячейку из пула (с идентификатором "TaskCell")
        let cell = tableView.dequeueReusableCell(withIdentifier: "TaskCell", for: indexPath) as! TaskTableViewCell
        
        // Настраиваем ячейку с данными задания
        let task = tasks[indexPath.row]
        cell.configure(with: task)
        
        // Добавляем обработчик для переключателя (UISwitch)
        cell.onSwitchChanged = { [weak self] isOn in
            // Обновляем статус выполнения задания
            self?.tasks[indexPath.row].isCompleted = isOn
            // Обновляем метку ранга
            self?.updateRankLabel()
        }
        
        return cell
    }
    
    // MARK: - UITableViewDelegate
    // Эти методы нужны для настройки поведения таблицы.
    
    // Метод задаёт высоту строки таблицы.
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80 // Устанавливаем высоту строки 80pt, чтобы вместить заголовок и описание
    }
}

// MARK: - Кастомная ячейка TaskTableViewCell
// Эта кастомная ячейка используется для отображения каждого задания.
// Содержит заголовок, описание и переключатель (UISwitch) для отметки выполнения.
class TaskTableViewCell: UITableViewCell {
    
    // MARK: - Свойства
    // UI-элемент: Заголовок задания.
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // UI-элемент: Описание задания.
    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .gray
        label.numberOfLines = 2 // Разрешаем до 2 строк текста
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // UI-элемент: Переключатель для отметки выполнения.
    private let completionSwitch: UISwitch = {
        let switchControl = UISwitch()
        switchControl.translatesAutoresizingMaskIntoConstraints = false
        return switchControl
    }()
    
    // Замыкание для обработки изменения состояния переключателя.
    // Вызывается, когда пользователь включает/выключает переключатель.
    var onSwitchChanged: ((Bool) -> Void)?
    
    // MARK: - Инициализация
    // Инициализатор ячейки.
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Функция: Настройка UI ячейки
    // Эта функция добавляет UI-элементы в ячейку и настраивает их расположение.
    private func setupUI() {
        // Добавляем UI-элементы в ячейку
        contentView.addSubview(titleLabel)
        contentView.addSubview(descriptionLabel)
        contentView.addSubview(completionSwitch)
        
        // Добавляем обработчик для переключателя
        completionSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
        
        // Настраиваем Auto Layout
        NSLayoutConstraint.activate([
            // Переключатель: размещаем справа с отступом
            completionSwitch.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            completionSwitch.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            // Заголовок: размещаем слева, с отступом, выравниваем по верхнему краю переключателя
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: completionSwitch.leadingAnchor, constant: -20),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            
            // Описание: размещаем под заголовком, с отступом
            descriptionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            descriptionLabel.trailingAnchor.constraint(equalTo: completionSwitch.leadingAnchor, constant: -20),
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),
            descriptionLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }
    
    // MARK: - Функция: Настройка ячейки
    // Эта функция заполняет ячейку данными задания.
    func configure(with task: DailyTask) {
        titleLabel.text = task.title
        descriptionLabel.text = task.description
        completionSwitch.isOn = task.isCompleted
    }
    
    // MARK: - Обработчик переключателя
    // Этот метод вызывается, когда пользователь меняет состояние переключателя.
    @objc private func switchChanged() {
        onSwitchChanged?(completionSwitch.isOn)
    }
}
