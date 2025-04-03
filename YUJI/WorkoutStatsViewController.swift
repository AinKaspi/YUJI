import UIKit
import os.log

/// Структура для хранения данных тренировки
struct WorkoutSession {
    let date: Date
    let exerciseType: ExerciseType
    let repetitionCount: Int
    let duration: TimeInterval
    let qualityScore: Int // Оценка качества от 0 до 100
    let averageRepDuration: TimeInterval
    
    // Преобразуем количество секунд в строку формата "мм:сс"
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // Преобразуем среднюю длительность повторения в удобный формат
    var formattedAvgRepDuration: String {
        return String(format: "%.1f сек", averageRepDuration)
    }
}

/// Контроллер для отображения статистики тренировок
class WorkoutStatsViewController: UIViewController {
    
    // MARK: - UI Components
    
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyStateLabel = UILabel()
    
    // MARK: - Properties
    
    // Пример данных (в реальном приложении их нужно загружать из хранилища)
    private var workoutSessions: [WorkoutSession] = [
        WorkoutSession(
            date: Date().addingTimeInterval(-86400),
            exerciseType: .squat,
            repetitionCount: 15,
            duration: 180,
            qualityScore: 85,
            averageRepDuration: 2.5
        ),
        WorkoutSession(
            date: Date().addingTimeInterval(-172800),
            exerciseType: .pushup,
            repetitionCount: 20,
            duration: 240,
            qualityScore: 90,
            averageRepDuration: 3.2
        ),
        WorkoutSession(
            date: Date().addingTimeInterval(-259200),
            exerciseType: .jumpingJack,
            repetitionCount: 30,
            duration: 120,
            qualityScore: 95,
            averageRepDuration: 1.5
        )
    ]
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        configureTableView()
        updateEmptyStateVisibility()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        title = "Статистика тренировок"
        view.backgroundColor = .systemBackground
        
        // Настройка кнопки добавления тренировки
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addNewWorkoutTapped)
        )
        
        // Настройка метки для пустого состояния
        emptyStateLabel.text = "Пока нет данных о тренировках.\nНачните тренировку, нажав на '+'"
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.textColor = .secondaryLabel
        emptyStateLabel.numberOfLines = 0
        emptyStateLabel.font = UIFont.systemFont(ofSize: 17)
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(emptyStateLabel)
        
        NSLayoutConstraint.activate([
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }
    
    private func configureTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(WorkoutSessionCell.self, forCellReuseIdentifier: "WorkoutSessionCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func updateEmptyStateVisibility() {
        emptyStateLabel.isHidden = !workoutSessions.isEmpty
        tableView.isHidden = workoutSessions.isEmpty
    }
    
    // MARK: - Actions
    
    @objc private func addNewWorkoutTapped() {
        let exerciseSelectionVC = ExerciseSelectionViewController()
        let navController = UINavigationController(rootViewController: exerciseSelectionVC)
        present(navController, animated: true)
    }
    
    /// Добавляет новую сессию тренировки и обновляет интерфейс
    func addWorkoutSession(_ session: WorkoutSession) {
        workoutSessions.insert(session, at: 0)
        updateEmptyStateVisibility()
        tableView.reloadData()
        
        os_log("WorkoutStatsViewController: Добавлена новая тренировка: %@ (повторений: %d)", 
               log: OSLog.default, type: .debug, 
               session.exerciseType.displayName, session.repetitionCount)
    }
}

// MARK: - UITableViewDelegate & UITableViewDataSource

extension WorkoutStatsViewController: UITableViewDelegate, UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return workoutSessions.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "WorkoutSessionCell", for: indexPath) as! WorkoutSessionCell
        
        let session = workoutSessions[indexPath.row]
        cell.configure(with: session)
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "История тренировок"
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 120
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        // В будущем здесь можно показывать детали конкретной тренировки
    }
}

/// Ячейка для отображения информации о тренировке
class WorkoutSessionCell: UITableViewCell {
    
    // MARK: - UI Components
    
    private let exerciseTypeLabel = UILabel()
    private let dateLabel = UILabel()
    private let statsStackView = UIStackView()
    
    private let repCountLabel = UILabel()
    private let durationLabel = UILabel()
    private let qualityScoreLabel = UILabel()
    private let avgRepDurationLabel = UILabel()
    
    // MARK: - Initialization
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setupViews() {
        // Настройка основных меток
        exerciseTypeLabel.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        exerciseTypeLabel.translatesAutoresizingMaskIntoConstraints = false
        
        dateLabel.font = UIFont.systemFont(ofSize: 14)
        dateLabel.textColor = .secondaryLabel
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Настройка дополнительных меток
        repCountLabel.font = UIFont.systemFont(ofSize: 15)
        durationLabel.font = UIFont.systemFont(ofSize: 15)
        qualityScoreLabel.font = UIFont.systemFont(ofSize: 15)
        avgRepDurationLabel.font = UIFont.systemFont(ofSize: 15)
        
        // Настройка стека для статистики
        statsStackView.axis = .vertical
        statsStackView.distribution = .fillEqually
        statsStackView.spacing = 4
        statsStackView.translatesAutoresizingMaskIntoConstraints = false
        
        // Добавление подписей в стек
        statsStackView.addArrangedSubview(repCountLabel)
        statsStackView.addArrangedSubview(durationLabel)
        statsStackView.addArrangedSubview(qualityScoreLabel)
        statsStackView.addArrangedSubview(avgRepDurationLabel)
        
        // Добавление элементов в ячейку
        contentView.addSubview(exerciseTypeLabel)
        contentView.addSubview(dateLabel)
        contentView.addSubview(statsStackView)
        
        // Настройка ограничений
        NSLayoutConstraint.activate([
            exerciseTypeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            exerciseTypeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            exerciseTypeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            dateLabel.topAnchor.constraint(equalTo: exerciseTypeLabel.bottomAnchor, constant: 4),
            dateLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            dateLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            statsStackView.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 8),
            statsStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            statsStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            statsStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }
    
    // MARK: - Configuration
    
    func configure(with session: WorkoutSession) {
        exerciseTypeLabel.text = session.exerciseType.displayName
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        dateLabel.text = dateFormatter.string(from: session.date)
        
        repCountLabel.text = "Повторения: \(session.repetitionCount)"
        durationLabel.text = "Длительность: \(session.formattedDuration)"
        qualityScoreLabel.text = "Качество: \(session.qualityScore)%"
        avgRepDurationLabel.text = "Среднее время: \(session.formattedAvgRepDuration)"
    }
}
