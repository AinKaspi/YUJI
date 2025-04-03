import Foundation

struct Exercise {
    let name: String
    let description: String
    let targetRepCount: Int
    
    init(name: String, description: String, targetRepCount: Int = 10) {
        self.name = name
        self.description = description
        self.targetRepCount = targetRepCount
    }
    
    static let testExercises: [Exercise] = [
        Exercise(name: "Приседания", description: "Выполните 10 приседаний"),
        Exercise(name: "Отжимания", description: "Выполните 10 отжиманий")
    ]
}
