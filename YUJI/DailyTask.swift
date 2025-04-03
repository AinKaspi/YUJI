import Foundation

// MARK: - Модель DailyTask
// Эта структура хранит данные о ежедневном задании.
// Содержит название, описание и статус выполнения.
struct DailyTask {
    // Название задания (например, "Сделать 10 приседаний").
    let title: String
    
    // Описание задания (например, "Выполните 10 приседаний утром").
    let description: String
    
    // Статус выполнения (true, если выполнено, false, если нет).
    var isCompleted: Bool
}

// MARK: - Перечисление Rank
// Это перечисление определяет возможные ранги пользователя: E, D, C, B, A, S.
// Каждый ранг соответствует определённому количеству выполненных заданий.
enum Rank: String {
    case e = "E"
    case d = "D"
    case c = "C"
    case b = "B"
    case a = "A"
    case s = "S"
    
    // Функция для определения ранга на основе количества выполненных заданий.
    // Чем больше заданий выполнено, тем выше ранг.
    static func rank(for completedTasks: Int) -> Rank {
        switch completedTasks {
        case 0: return .e // 0 заданий — ранг E
        case 1: return .d // 1 задание — ранг D
        case 2: return .c // 2 задания — ранг C
        case 3: return .b // 3 задания — ранг B
        case 4: return .a // 4 задания — ранг A
        default: return .s // 5 и более заданий — ранг S
        }
    }
}

// MARK: - Тестовые данные
// Расширение для DailyTask, чтобы создать тестовый список заданий.
// Это позволяет нам сразу протестировать UI.
extension DailyTask {
    // Статическое свойство testTasks создаёт тестовый список заданий.
    static let testTasks = [
        DailyTask(title: "Сделать 10 приседаний", description: "Выполните 10 приседаний утром", isCompleted: false),
        DailyTask(title: "Пробежать 1 км", description: "Пробегите 1 км в парке", isCompleted: false),
        DailyTask(title: "Выпить 2 литра воды", description: "Выпейте 2 литра воды в течение дня", isCompleted: false),
        DailyTask(title: "Сделать растяжку", description: "Выполните 10 минут растяжки", isCompleted: false),
        DailyTask(title: "Пройти 5000 шагов", description: "Пройдите 5000 шагов за день", isCompleted: false)
    ]
}
