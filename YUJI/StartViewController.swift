import UIKit

class StartViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    private let exercises: [Exercise] = Exercise.testExercises
    
    private let exercisesTableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        view.backgroundColor = .white
        view.addSubview(exercisesTableView)
        
        exercisesTableView.dataSource = self
        exercisesTableView.delegate = self
        exercisesTableView.register(UITableViewCell.self, forCellReuseIdentifier: "ExerciseCell")
        
        NSLayoutConstraint.activate([
            exercisesTableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            exercisesTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            exercisesTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            exercisesTableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return exercises.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ExerciseCell", for: indexPath)
        let exercise = exercises[indexPath.row]
        cell.textLabel?.text = exercise.name
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let exercise = exercises[indexPath.row]
        let exerciseVC = ExerciseExecutionViewController(exercise: exercise)
        print("Переход на ExerciseExecutionViewController для упражнения: \(exercise.name)")
        if let navController = navigationController {
            navController.pushViewController(exerciseVC, animated: true)
        } else {
            print("Ошибка: navigationController не найден")
        }
    }
}
