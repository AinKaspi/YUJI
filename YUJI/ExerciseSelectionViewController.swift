import UIKit
import os.log

/// Контроллер для выбора типа упражнения
class ExerciseSelectionViewController: UIViewController {
    
    // MARK: - Properties
    
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    
    // Список упражнений для отображения
    private let exercises: [(type: ExerciseType, icon: String)] = [
        (.squat, "figure.squat"),
        (.pushup, "figure.core.training"),
        (.lunge, "figure.step.training"),
        (.plank, "figure.core.training"),
        (.jumpingJack, "figure.jumprope")
    ]
    
    // Обработчик выбора упражнения
    var onExerciseSelected: ((ExerciseType) -> Void)?
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        configureTableView()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        title = "Выбор упражнения"
        view.backgroundColor = .systemBackground
        
        if #available(iOS 15.0, *) {
            navigationItem.scrollEdgeAppearance = navigationItem.standardAppearance
        }
        
        // Добавление кнопки закрытия, если контроллер отображается модально
        if presentingViewController != nil {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .close,
                target: self,
                action: #selector(closeButtonTapped)
            )
        }
        
        // Добавление информационной кнопки
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "info.circle"),
            style: .plain,
            target: self,
            action: #selector(showInfo)
        )
    }
    
    private func configureTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(ExerciseCell.self, forCellReuseIdentifier: "ExerciseCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - Actions
    
    @objc private func closeButtonTapped() {
        dismiss(animated: true)
    }
    
    @objc private func showInfo() {
        let infoVC = UIAlertController(
            title: "Информация",
            message: "YUJI анализирует вашу технику выполнения упражнений, используя компьютерное зрение. Выберите тип упражнения и следуйте инструкциям на экране.",
            preferredStyle: .alert
        )
        
        infoVC.addAction(UIAlertAction(title: "Понятно", style: .default))
        present(infoVC, animated: true)
    }
}

// MARK: - UITableViewDelegate & UITableViewDataSource

extension ExerciseSelectionViewController: UITableViewDelegate, UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return exercises.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ExerciseCell", for: indexPath) as! ExerciseCell
        
        let exercise = exercises[indexPath.row]
        cell.configure(with: exercise.type.displayName, iconName: exercise.icon)
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let selectedExercise = exercises[indexPath.row].type
        onExerciseSelected?(selectedExercise)
        
        os_log("ExerciseSelectionViewController: Выбрано упражнение '%@'", log: OSLog.default, type: .debug, selectedExercise.displayName)
        
        // Настраиваем упражнение в Exercise
        let exercise = Exercise(
            name: selectedExercise.displayName,
            description: getExerciseDescription(for: selectedExercise),
            targetRepCount: 10
        )
        
        // Создаем и отображаем контроллер выполнения упражнения
        let exerciseVC = ExerciseExecutionViewController(exercise: exercise)
        navigationController?.pushViewController(exerciseVC, animated: true)
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "Доступные упражнения"
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return "Выберите упражнение для начала тренировки. YUJI отслеживает вашу технику и считает повторения."
    }
    
    // MARK: - Helper Methods
    
    /// Возвращает описание для конкретного типа упражнения
    private func getExerciseDescription(for type: ExerciseType) -> String {
        switch type {
        case .squat:
            return "Встаньте прямо, ноги на ширине плеч. Опускайтесь, сгибая колени до угла 90°, держа спину прямо. Затем вернитесь в исходное положение."
        case .pushup:
            return "Примите упор лежа, руки на ширине плеч. Опуститесь, сгибая руки в локтях, пока грудь почти не коснется пола, затем поднимитесь обратно."
        case .lunge:
            return "Сделайте широкий шаг вперед, опустите заднее колено почти до пола, сохраняя переднее колено под углом 90°. Вернитесь в исходное положение."
        case .plank:
            return "Примите положение как для отжимания, но опирайтесь на предплечья. Держите тело прямым, напрягая мышцы кора. Удерживайте позицию."
        case .jumpingJack:
            return "Встаньте прямо, руки по бокам. Прыгните, расставив ноги в стороны и подняв руки над головой. Вернитесь в исходное положение."
        case .custom(let name):
            return "Пользовательское упражнение: \(name). Следуйте собственной технике выполнения."
        }
    }
}

/// Ячейка для отображения упражнения
class ExerciseCell: UITableViewCell {
    
    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        accessoryType = .disclosureIndicator
        
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.tintColor = .systemBlue
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        
        titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(iconImageView)
        contentView.addSubview(titleLabel)
        
        NSLayoutConstraint.activate([
            iconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconImageView.widthAnchor.constraint(equalToConstant: 30),
            iconImageView.heightAnchor.constraint(equalToConstant: 30),
            
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        ])
    }
    
    func configure(with title: String, iconName: String) {
        titleLabel.text = title
        iconImageView.image = UIImage(systemName: iconName)
    }
}
