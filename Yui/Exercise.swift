import Foundation

struct Exercise {
    let name: String
    let description: String
    
    static let testExercises: [Exercise] = [
        Exercise(name: "Приседания", description: "Выполните 10 приседаний"),
        Exercise(name: "Отжимания", description: "Выполните 10 отжиманий")
    ]
}
