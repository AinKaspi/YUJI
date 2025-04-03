import MediaPipeTasksVision
import os.log

/// Перечисление типов поддерживаемых упражнений
enum ExerciseType: Hashable {
    case squat        // Приседания
    case pushup       // Отжимания
    case lunge        // Выпады
    case plank        // Планка
    case jumpingJack  // Прыжки «Джек»
    case custom(String) // Пользовательское упражнение
    
    var displayName: String {
        switch self {
        case .squat: return "Приседания"
        case .pushup: return "Отжимания"
        case .lunge: return "Выпады"
        case .plank: return "Планка"
        case .jumpingJack: return "Прыжки Джек"
        case .custom(let name): return name
        }
    }
    
    // Реализация Hashable для случая с ассоциированным значением
    func hash(into hasher: inout Hasher) {
        switch self {
        case .squat:
            hasher.combine(0)
        case .pushup:
            hasher.combine(1)
        case .lunge:
            hasher.combine(2)
        case .plank:
            hasher.combine(3)
        case .jumpingJack:
            hasher.combine(4)
        case .custom(let name):
            hasher.combine(5)
            hasher.combine(name)
        }
    }
    
    static func == (lhs: ExerciseType, rhs: ExerciseType) -> Bool {
        switch (lhs, rhs) {
        case (.squat, .squat), (.pushup, .pushup), (.lunge, .lunge), (.plank, .plank), (.jumpingJack, .jumpingJack):
            return true
        case (.custom(let lhsName), .custom(let rhsName)):
            return lhsName == rhsName
        default:
            return false
        }
    }
}

/// Основной класс обработки поз для анализа упражнений
class PoseProcessor {
    
    // Основные свойства
    private var repCount = 0
    private var inExercisePosition = false // Общий флаг для любого упражнения (вместо isSquatting)
    private var previousHipY: Float?
    private var previousKneeY: Float?
    private var framesWithoutPerson = 0
    private let resetDelayFrames = 10 // Задержка перед сбросом счётчика
    
    // Тип упражнения, которое сейчас выполняется
    private var exerciseType: ExerciseType = .squat
    
    // Фильтр Калмана для стабилизации ключевых точек
    private var landmarkFilter: PoseLandmarkFilter?
    private let useKalmanFilter: Bool = true
    
    // Калькулятор углов в суставах для точного анализа движений
    private let angleCalculator = JointAngleCalculator()
    
    // Текущие углы в суставах
    private var currentJointAngles: [String: JointAngle] = [:]
    private var filteredJointAngles: [String: JointAngle] = [:]
    
    // Счетчик кадров для логирования
    private var frameCounter = 0
    
    // Callback для обновления состояния упражнения
    var onStateChanged: ((_ isInPosition: Bool, _ repCount: Int, _ feedback: (message: String, isCritical: Bool)?) -> Void)?
    
    // Адаптивные пороги для разных упражнений
    private var exerciseThresholds: [ExerciseType: [String: Float]] = [
        .squat: [
            "kneeAngleStart": 120.0,  // Начало приседания (угол в колене меньше)
            "kneeAngleEnd": 130.0,   // Конец приседания (угол в колене больше)
            "hipAngle": 110.0,       // Минимальный угол в бедре
            "kneeDistance": 0.15     // Минимальное расстояние между коленями
        ],
        .pushup: [
            "elbowAngleStart": 120.0, // Начало отжимания (угол в локте меньше)
            "elbowAngleEnd": 160.0,  // Конец отжимания (угол в локте больше)
            "backAngle": 160.0       // Минимальный угол спины (должен быть прямым)
        ],
        .lunge: [
            "frontKneeAngle": 110.0,  // Угол переднего колена
            "backKneeAngle": 100.0,   // Угол заднего колена
            "hipAngle": 120.0         // Угол бедра
        ],
        .plank: [
            "backAngle": 160.0,       // Угол спины (должен быть прямым)
            "elbowAngle": 90.0,      // Угол в локте
            "minDuration": 10.0       // Минимальная продолжительность в секундах
        ],
        .jumpingJack: [
            "armAngleStart": 20.0,   // Руки опущены
            "armAngleEnd": 150.0,    // Руки подняты
            "legAngleStart": 10.0,   // Ноги вместе
            "legAngleEnd": 45.0      // Ноги врозь
        ]
    ]
    
    // Параметры текущего упражнения
    private var currentExerciseParams: [String: Float] {
        return exerciseThresholds[exerciseType] ?? [:]
    }
    
    // Параметры для фильтра Калмана
    private let filterParams: [ExerciseType: (process: Float, measurement: Float)] = [
        .squat: (process: 0.001, measurement: 0.03),
        .pushup: (process: 0.001, measurement: 0.02),
        .lunge: (process: 0.001, measurement: 0.03),
        .plank: (process: 0.0005, measurement: 0.01),  // Более стабильное отслеживание для планки
        .jumpingJack: (process: 0.003, measurement: 0.05)  // Быстрее реакция для прыжков
    ]
    
    // Данные для логирования репетиций
    private var exerciseStartTime: Date?
    private var lastRepDuration: TimeInterval = 0
    private var repDurations: [TimeInterval] = [] // Хранение времени каждого повторения
    
    // Колбеки для обновления UI
    var onRepCountUpdated: ((Int) -> Void)?
    var onQualityFeedback: ((String, Bool) -> Void)? // (сообщение, критичность)
    
    // MARK: - Инициализация
    
    /// Инициализирует новый процессор поз с заданным типом упражнения
    /// - Parameter exerciseType: Тип упражнения для анализа
    init(exerciseType: ExerciseType = .squat) {
        self.exerciseType = exerciseType
        os_log("PoseProcessor: Инициализирован для упражнения '%@'", log: OSLog.default, type: .debug, exerciseType.displayName)
    }
    
    /// Устанавливает тип упражнения и сбрасывает счетчики
    /// - Parameter type: Новый тип упражнения
    func setExerciseType(_ type: ExerciseType) {
        exerciseType = type
        resetState()
        os_log("PoseProcessor: Установлен тип упражнения '%@'", log: OSLog.default, type: .debug, type.displayName)
    }
    
    func processPoseLandmarks(_ result: PoseLandmarkerResult) {
        // Увеличиваем счетчик кадров для логирования
        frameCounter += 1
        let shouldLog = frameCounter % 30 == 0 // Логируем примерно раз в секунду (30 fps)
        
        guard let landmarks = result.landmarks.first else {
            if shouldLog {
                os_log("PoseProcessor: Нет обнаруженных ключевых точек", log: OSLog.default, type: .debug)
            }
            framesWithoutPerson += 1
            if framesWithoutPerson >= resetDelayFrames {
                resetState()
            }
            return
        }
        
        framesWithoutPerson = 0
        
        // 1. Применяем фильтр Калмана для стабилизации ключевых точек
        var processedLandmarks = landmarks
        if useKalmanFilter {
            // Ленивая инициализация фильтрач
            if landmarkFilter == nil {
                // Выбираем параметры фильтра в зависимости от типа упражнения
                let params = filterParams[exerciseType] ?? (process: 0.001, measurement: 0.03)
                landmarkFilter = PoseLandmarkFilter(landmarksCount: landmarks.count)
                
                os_log("PoseProcessor: Инициализирован фильтр Калмана для %d точек, параметры: process=%.4f, measurement=%.4f", 
                       log: OSLog.default, type: .debug, landmarks.count, params.process, params.measurement)
            }
            
            // Применяем фильтр к ключевым точкам
            processedLandmarks = landmarkFilter!.process(landmarks: landmarks)
        }
        
        // 2. Вычисляем углы в суставах для анализа
        currentJointAngles = angleCalculator.calculateJointAngles(landmarks: landmarks) // Оригинальные углы
        filteredJointAngles = angleCalculator.calculateJointAngles(landmarks: processedLandmarks) // Фильтрованные углы
        
        // Используем фильтрованные или оригинальные углы в зависимости от настроек
        let jointsForAnalysis = useKalmanFilter ? filteredJointAngles : currentJointAngles
        
        // 3. Анализируем движения в зависимости от типа упражнения
        switch exerciseType {
        case .squat:
            processSquat(jointsForAnalysis, originalLandmarks: landmarks, shouldLog: shouldLog)
        case .pushup:
            processPushup(jointsForAnalysis, originalLandmarks: landmarks, shouldLog: shouldLog)
        case .lunge:
            processLunge(jointsForAnalysis, originalLandmarks: landmarks, shouldLog: shouldLog)
        case .plank:
            processPlank(jointsForAnalysis, originalLandmarks: landmarks, shouldLog: shouldLog)
        case .jumpingJack:
            processJumpingJack(jointsForAnalysis, originalLandmarks: landmarks, shouldLog: shouldLog)
        case .custom(let name):
            // Для пользовательских упражнений используем фаллбэк на основе координат
            os_log("PoseProcessor: Обработка пользовательского упражнения '%@'", log: OSLog.default, type: .debug, name)
            processUsingCoordinates(landmarks)
        }
        
        // 4. Проверяем наличие аномалий в движениях
        let anomalies = angleCalculator.detectAnomalies(angles: jointsForAnalysis)
        if !anomalies.isEmpty {
            let message = anomalies.joined(separator: ", ")
            os_log("PoseProcessor: Обнаружены аномалии в движениях: %@", log: OSLog.default, type: .info, message)
            
            // Отправляем критическую обратную связь
            onStateChanged?(inExercisePosition, repCount, (message: "Обнаружены аномалии: \(message)", isCritical: true))
        } else if shouldLog {
            // Периодически отправляем позитивную обратную связь
            // onStateChanged?(inExercisePosition, repCount, (message: "Хорошая работа! Техника верная.", isCritical: false))
        }
    }
    
    /// Фаллбэк метод обработки на основе координат (старый подход)
    private func processUsingCoordinates(_ landmarks: [NormalizedLandmark]) {
        let leftHip = landmarks[23]
        let rightHip = landmarks[24]
        let leftKnee = landmarks[25]
        let rightKnee = landmarks[26]
        
        let hipY = (leftHip.y + rightHip.y) / 2
        let kneeY = (leftKnee.y + rightKnee.y) / 2
        
        os_log("PoseProcessor: Используется фаллбэк по координатам - hipY: %.3f, kneeY: %.3f", 
               log: OSLog.default, type: .debug, hipY, kneeY)
        
        let threshold: Float = 0.05
        
        if previousHipY != nil && previousKneeY != nil {
            // В нижней точке приседания hipY больше kneeY
            if hipY > kneeY + threshold && !inExercisePosition {
                inExercisePosition = true
                os_log("PoseProcessor: Начало приседания (по координатам)", log: OSLog.default, type: .debug)
            }
            // В верхней точке приседания hipY меньше kneeY
            else if hipY < kneeY - threshold && inExercisePosition {
                inExercisePosition = false
                repCount += 1
                os_log("PoseProcessor: Конец приседания (по координатам), repCount: %d", log: OSLog.default, type: .debug, repCount)
                // Обновляем состояние без сообщения обратной связи
                onStateChanged?(inExercisePosition, repCount, nil)
            }
        }
        
        self.previousHipY = hipY
        self.previousKneeY = kneeY
    }
    
    // MARK: - Методы обработки упражнений
    
    /// Обрабатывает приседания на основе углов в суставах
    /// - Parameters:
    ///   - angles: Углы в суставах для анализа
    ///   - landmarks: Оригинальные ключевые точки (для дополнительного анализа)
    ///   - shouldLog: Флаг для логирования
    private func processSquat(_ angles: [String: JointAngle], originalLandmarks: [NormalizedLandmark], shouldLog: Bool) {
        // Получаем параметры для анализа приседаний
        let kneeAngleStartThreshold = currentExerciseParams["kneeAngleStart"] ?? 120.0
        let kneeAngleEndThreshold = currentExerciseParams["kneeAngleEnd"] ?? 130.0
        let hipAngleThreshold = currentExerciseParams["hipAngle"] ?? 110.0
        
        // Получаем углы в колене (используем любое доступное колено)
        let kneeAngle: Float
        let hipAngle: Float
        
        // Проверяем наличие всех необходимых углов
        let hasRequiredAngles = (angles.keys.contains("leftKnee") || angles.keys.contains("rightKnee")) &&
                                (angles.keys.contains("leftHip") || angles.keys.contains("rightHip"))
        
        guard hasRequiredAngles else {
            if shouldLog {
                os_log("PoseProcessor: Недостаточно данных об углах для анализа приседания", log: OSLog.default, type: .debug)
            }
            // Фаллбэк к старому методу на основе координат
            processUsingCoordinates(originalLandmarks)
            return
        }
        
        // Выбираем углы для анализа (left или right)
        if let leftKnee = angles["leftKnee"], leftKnee.isValid {
            kneeAngle = leftKnee.angle
        } else if let rightKnee = angles["rightKnee"], rightKnee.isValid {
            kneeAngle = rightKnee.angle
        } else {
            processUsingCoordinates(originalLandmarks)
            return
        }
        
        if let leftHip = angles["leftHip"], leftHip.isValid {
            hipAngle = leftHip.angle
        } else if let rightHip = angles["rightHip"], rightHip.isValid {
            hipAngle = rightHip.angle
        } else {
            processUsingCoordinates(originalLandmarks)
            return
        }
        
        // Время начала упражнения
        let now = Date()
        
        // анализируем фазу приседания на основе угла в колене
        if shouldLog {
            os_log("PoseProcessor: Анализ приседания - угол в колене: %.1f°, угол в бедре: %.1f°, текущее состояние: %@", 
                   log: OSLog.default, type: .debug, 
                   kneeAngle, hipAngle,
                   inExercisePosition ? "в приседе" : "стоя")
        }
        
        // Дополнительная проверка общего состояния
        let kneeDistanceOK = checkKneeDistance(originalLandmarks)
        
        // Если угол в колене меньше порога - значит человек в приседе
        if kneeAngle < kneeAngleStartThreshold && !inExercisePosition {
            inExercisePosition = true
            exerciseStartTime = now
            
            // Проверка качества приседания
            if !kneeDistanceOK {
                onStateChanged?(inExercisePosition, repCount, (message: "Колени слишком близко, увеличьте расстояние", isCritical: true))
            }
            
            if hipAngle < hipAngleThreshold {
                onStateChanged?(inExercisePosition, repCount, (message: "Слишком большой наклон вперед, держите спину прямее", isCritical: true))
            }
            
            os_log("PoseProcessor: Начало приседания - угол в колене: %.1f°", log: OSLog.default, type: .debug, kneeAngle)
        } 
        // Если угол в колене больше порога и был в приседе - значит встал
        else if kneeAngle > kneeAngleEndThreshold && inExercisePosition { // Добавляем гистерезис между началом и концом
            inExercisePosition = false
            repCount += 1
            
            // Записываем время выполнения репетиции
            if let startTime = exerciseStartTime {
                lastRepDuration = now.timeIntervalSince(startTime)
                repDurations.append(lastRepDuration)
                
                os_log("PoseProcessor: Длительность приседания: %.2f секунд", log: OSLog.default, type: .debug, lastRepDuration)
                
                // Оценка скорости выполнения
                if lastRepDuration < 1.0 {
                    onStateChanged?(inExercisePosition, repCount, (message: "Слишком быстрое приседание, замедлите", isCritical: true))
                } else if lastRepDuration > 4.0 {
                    onStateChanged?(inExercisePosition, repCount, (message: "Слишком медленное приседание", isCritical: false))
                }
            }
            
            os_log("PoseProcessor: Конец приседания - угол в колене: %.1f°, реп: %d", log: OSLog.default, type: .debug, kneeAngle, repCount)
            onStateChanged?(inExercisePosition, repCount, nil)
        }
    }
    
    /// Проверяет расстояние между коленями при приседании
    /// - Parameter landmarks: Ключевые точки для анализа
    /// - Returns: true, если расстояние достаточное
    private func checkKneeDistance(_ landmarks: [NormalizedLandmark]) -> Bool {
        let leftKnee = landmarks[25]
        let rightKnee = landmarks[26]
        
        // Рассчитываем горизонтальное расстояние между коленями
        let kneeDistance = abs(leftKnee.x - rightKnee.x)
        let minKneeDistance = currentExerciseParams["kneeDistance"] ?? 0.15
        
        return kneeDistance >= minKneeDistance
    }
    
    /// Обрабатывает отжимания на основе углов в суставах
    /// - Parameters:
    ///   - angles: Углы в суставах для анализа
    ///   - landmarks: Оригинальные ключевые точки
    ///   - shouldLog: Флаг для логирования
    
    /// Обрабатывает выпады на основе углов в суставах
    /// - Parameters:
    ///   - angles: Углы в суставах для анализа
    ///   - landmarks: Оригинальные ключевые точки
    ///   - shouldLog: Флаг для логирования
    /// Обрабатывает упражнение планка
    /// - Parameters:
    ///   - angles: Углы в суставах для анализа
    ///   - landmarks: Оригинальные ключевые точки
    ///   - shouldLog: Флаг для логирования
    private func processPlank(_ angles: [String: JointAngle], originalLandmarks: [NormalizedLandmark], shouldLog: Bool) {
        // Получаем параметры для анализа планки
        let backAngleThreshold = currentExerciseParams["backAngle"] ?? 160.0
        let elbowAngleThreshold = currentExerciseParams["elbowAngle"] ?? 90.0
        let minDuration = currentExerciseParams["minDuration"] ?? 10.0
        
        // Проверяем наличие всех необходимых углов
        guard let backAngle = angles["back"]?.angle,
              (angles["leftElbow"]?.angle != nil || angles["rightElbow"]?.angle != nil) else {
            if shouldLog {
                os_log("PoseProcessor: Недостаточно данных об углах для анализа планки", log: OSLog.default, type: .debug)
            }
            return
        }
        
        // Выбираем угол в локте
        let elbowAngle = angles["leftElbow"]?.angle ?? angles["rightElbow"]!.angle
        
        let now = Date()
        
        if shouldLog {
            os_log("PoseProcessor: Анализ планки - угол спины: %.1f°, угол в локте: %.1f°", 
                   log: OSLog.default, type: .debug, backAngle, elbowAngle)
        }
        
        // Проверяем качество выполнения планки
        let isBackStraight = backAngle >= backAngleThreshold
        let isElbowAngleCorrect = abs(elbowAngle - elbowAngleThreshold) < 15.0 // Допускаем небольшую погрешность
        
        // В отличие от других упражнений, планка учитывает длительность удержания позиции
        if isBackStraight && isElbowAngleCorrect {
            // Если еще не в позиции планки - начинаем отсчет
            if !inExercisePosition {
                inExercisePosition = true
                exerciseStartTime = now
                os_log("PoseProcessor: Начало планки", log: OSLog.default, type: .debug)
            }
            // Уже держит планку, проверяем длительность
            else if let startTime = exerciseStartTime {
                let duration = now.timeIntervalSince(startTime)
                
                // Периодически обновляем счетчик каждые 5 секунд
                if Int(duration) % 5 == 0 && Int(duration) != Int(lastRepDuration) {
                    lastRepDuration = duration
                    onRepCountUpdated?(Int(duration))
                    os_log("PoseProcessor: Планка держится %.1f секунд", log: OSLog.default, type: .debug, duration)
                    
                    // Если превысили минимальное время - считаем репетицию выполненной
                    if duration >= Double(minDuration) && repCount == 0 {
                        repCount = 1
                        onStateChanged?(inExercisePosition, repCount, (message: "Отлично! Минимальное время достигнуто, продолжайте!", isCritical: false))
                    }
                }
            }
        }
        // Если уже был в планке, но вышел из позиции
        else if inExercisePosition {
            inExercisePosition = false
            
            if let startTime = exerciseStartTime {
                lastRepDuration = now.timeIntervalSince(startTime)
                repDurations.append(lastRepDuration)
                
                os_log("PoseProcessor: Конец планки, продержался %.1f секунд", log: OSLog.default, type: .debug, lastRepDuration)
                
                // Обратная связь по качеству
                if !isBackStraight {
                    onStateChanged?(inExercisePosition, repCount, (message: "Держите спину прямее во время планки", isCritical: true))
                }
                if !isElbowAngleCorrect {
                    onStateChanged?(inExercisePosition, repCount, (message: "Следите за углом в локтях, должен быть около 90 градусов", isCritical: true))
                }
            }
        }
    }
    
    private func processLunge(_ angles: [String: JointAngle], originalLandmarks: [NormalizedLandmark], shouldLog: Bool) {
        // Получаем параметры для анализа выпадов
        let frontKneeAngleThreshold = currentExerciseParams["frontKneeAngle"] ?? 110.0
        let backKneeAngleThreshold = currentExerciseParams["backKneeAngle"] ?? 100.0
        
        // Проверяем наличие углов для коленей
        guard let leftKneeAngle = angles["leftKnee"]?.angle, 
              let rightKneeAngle = angles["rightKnee"]?.angle else {
            if shouldLog {
                os_log("PoseProcessor: Недостаточно данных об углах для анализа выпада", log: OSLog.default, type: .debug)
            }
            return
        }
        
        // Определяем переднее и заднее колено
        // Предполагаем, что колено с меньшим углом - это переднее
        let frontKneeAngle = min(leftKneeAngle, rightKneeAngle)
        let backKneeAngle = max(leftKneeAngle, rightKneeAngle)
        
        let now = Date()
        
        if shouldLog {
            os_log("PoseProcessor: Анализ выпада - переднее колено: %.1f°, заднее колено: %.1f°", 
                   log: OSLog.default, type: .debug, frontKneeAngle, backKneeAngle)
        }
        
        // Анализ выпада: если переднее колено достаточно согнуто, значит в позиции выпада
        if frontKneeAngle < frontKneeAngleThreshold && backKneeAngle < backKneeAngleThreshold && !inExercisePosition {
            inExercisePosition = true
            exerciseStartTime = now
            
            if frontKneeAngle > 90 {
                onStateChanged?(inExercisePosition, repCount, (message: "Согните переднее колено сильнее, до 90 градусов", isCritical: false))
            }
            
            os_log("PoseProcessor: Начало выпада", log: OSLog.default, type: .debug)
        }
        // Выход из выпада если оба колена выпрямлены
        else if frontKneeAngle > frontKneeAngleThreshold && backKneeAngle > backKneeAngleThreshold && inExercisePosition {
            inExercisePosition = false
            repCount += 1
            
            if let startTime = exerciseStartTime {
                lastRepDuration = now.timeIntervalSince(startTime)
                repDurations.append(lastRepDuration)
            }
            
            os_log("PoseProcessor: Конец выпада, реп: %d", log: OSLog.default, type: .debug, repCount)
            onStateChanged?(inExercisePosition, repCount, nil)
        }
    }
    private func processPushup(_ angles: [String: JointAngle], originalLandmarks: [NormalizedLandmark], shouldLog: Bool) {
        // Получаем параметры для анализа отжиманий
        let elbowAngleStartThreshold = currentExerciseParams["elbowAngleStart"] ?? 120.0
        let elbowAngleEndThreshold = currentExerciseParams["elbowAngleEnd"] ?? 160.0
        let backAngleThreshold = currentExerciseParams["backAngle"] ?? 160.0
        
        // Получаем углы в локте и спине
        let elbowAngle: Float
        let backAngle: Float
        
        // Проверяем наличие всех необходимых углов
        let hasRequiredAngles = (angles.keys.contains("leftElbow") || angles.keys.contains("rightElbow")) &&
                                 angles.keys.contains("back")
        
        guard hasRequiredAngles else {
            if shouldLog {
                os_log("PoseProcessor: Недостаточно данных об углах для анализа отжимания", log: OSLog.default, type: .debug)
            }
            return
        }
        
        // Выбираем углы для анализа (левый или правый локоть)
        if let leftElbow = angles["leftElbow"], leftElbow.isValid {
            elbowAngle = leftElbow.angle
        } else if let rightElbow = angles["rightElbow"], rightElbow.isValid {
            elbowAngle = rightElbow.angle
        } else {
            return
        }
        
        if let back = angles["back"], back.isValid {
            backAngle = back.angle
        } else {
            return
        }
        
        // Время начала упражнения
        let now = Date()
        
        // Логируем для отладки
        if shouldLog {
            os_log("PoseProcessor: Анализ отжимания - угол в локте: %.1f°, угол спины: %.1f°, текущее состояние: %@", 
                   log: OSLog.default, type: .debug, 
                   elbowAngle, backAngle,
                   inExercisePosition ? "в нижней точке" : "в верхней точке")
        }
        
        // Проверка положения спины
        if backAngle < backAngleThreshold {
            onStateChanged?(inExercisePosition, repCount, (message: "Держите спину прямее, не прогибайтесь в пояснице", isCritical: true))
        }
        
        // Если угол в локте меньше порога - значит человек в нижней точке отжимания
        if elbowAngle < elbowAngleStartThreshold && !inExercisePosition {
            inExercisePosition = true
            exerciseStartTime = now
            os_log("PoseProcessor: Начало отжимания - угол в локте: %.1f°", log: OSLog.default, type: .debug, elbowAngle)
        } 
        // Если угол в локте больше порога и был в нижней точке - значит вернулся в верхнюю
        else if elbowAngle > elbowAngleEndThreshold && inExercisePosition {
            inExercisePosition = false
            repCount += 1
            
            // Записываем время выполнения репетиции
            if let startTime = exerciseStartTime {
                lastRepDuration = now.timeIntervalSince(startTime)
                repDurations.append(lastRepDuration)
                
                // Оценка скорости
                if lastRepDuration < 1.0 {
                    onStateChanged?(inExercisePosition, repCount, (message: "Слишком быстрое отжимание, замедлите", isCritical: true))
                }
            }
            
            os_log("PoseProcessor: Конец отжимания - угол в локте: %.1f°, реп: %d", log: OSLog.default, type: .debug, elbowAngle, repCount)
            onStateChanged?(inExercisePosition, repCount, nil)
        }
    }
        
    /// Обрабатывает прыжки "Джек" на основе углов в суставах
    /// - Parameters:
    ///   - angles: Углы в суставах для анализа
    ///   - landmarks: Оригинальные ключевые точки
    ///   - shouldLog: Флаг для логирования
    private func processJumpingJack(_ angles: [String: JointAngle], originalLandmarks: [NormalizedLandmark], shouldLog: Bool) {
        // Получаем параметры для анализа прыжков "Джек"
        let armAngleStartThreshold = currentExerciseParams["armAngleStart"] ?? 20.0  // Руки опущены
        let armAngleEndThreshold = currentExerciseParams["armAngleEnd"] ?? 150.0   // Руки подняты
        let legAngleStartThreshold = currentExerciseParams["legAngleStart"] ?? 10.0  // Ноги вместе
        let legAngleEndThreshold = currentExerciseParams["legAngleEnd"] ?? 45.0    // Ноги врозь
        
        // Проверяем наличие необходимых углов
        guard let shoulderAngle = (angles["leftShoulder"]?.angle ?? angles["rightShoulder"]?.angle),
              let legAngle = getHipWidth(landmarks: originalLandmarks) else {
            if shouldLog {
                os_log("PoseProcessor: Недостаточно данных для анализа прыжков Джек", log: OSLog.default, type: .debug)
            }
            return
        }
        
        let now = Date()
        
        if shouldLog {
            os_log("PoseProcessor: Анализ прыжка Джек - угол плеч: %.1f°, расстояние между ногами: %.3f", 
                   log: OSLog.default, type: .debug, shoulderAngle, legAngle)
        }
        
        // Оцениваем позицию рук и ног
        let isArmsUp = shoulderAngle > armAngleEndThreshold
        let isLegsApart = legAngle > legAngleEndThreshold
        let isArmsDown = shoulderAngle < armAngleStartThreshold
        let isLegsTogether = legAngle < legAngleStartThreshold
        
        // Базовая позиция - руки внизу, ноги вместе
        if isArmsDown && isLegsTogether && !inExercisePosition {
            inExercisePosition = true
            exerciseStartTime = now
            os_log("PoseProcessor: Начало прыжка Джек - базовая позиция", log: OSLog.default, type: .debug)
        }
        // Верхняя позиция - руки вверху, ноги врозь
        else if isArmsUp && isLegsApart && inExercisePosition {
            inExercisePosition = false
            repCount += 1
            
            if let startTime = exerciseStartTime {
                lastRepDuration = now.timeIntervalSince(startTime)
                repDurations.append(lastRepDuration)
                
                // Оценка скорости
                if lastRepDuration < 0.3 {
                    onStateChanged?(inExercisePosition, repCount, (message: "Хороший темп! Продолжайте", isCritical: false))
                } else if lastRepDuration > 1.5 {
                    onStateChanged?(inExercisePosition, repCount, (message: "Попробуйте двигаться быстрее", isCritical: false))
                }
            }
            
            // Даем обратную связь по технике
            if shoulderAngle < armAngleEndThreshold - 20 {
                onStateChanged?(inExercisePosition, repCount, (message: "Поднимайте руки выше", isCritical: false))
            }
            if legAngle < legAngleEndThreshold - 10 {
                onStateChanged?(inExercisePosition, repCount, (message: "Расставляйте ноги шире", isCritical: false))
            }
            
            os_log("PoseProcessor: Конец прыжка Джек, реп: %d", log: OSLog.default, type: .debug, repCount)
            onStateChanged?(inExercisePosition, repCount, nil)
        }
    }
    
    /// Получает расстояние между ногами для прыжков Джек
    /// - Parameter landmarks: Ключевые точки
    /// - Returns: Расстояние между ногами (унормированное)
    private func getHipWidth(landmarks: [NormalizedLandmark]) -> Float? {
        guard landmarks.count >= 28 else {
            return nil
        }
        
        let leftAnkle = landmarks[27]
        let rightAnkle = landmarks[28]
        
        // Расчитываем расстояние между лодыжками
        return abs(leftAnkle.x - rightAnkle.x)
    }
    
    // MARK: - Функция: Сброс состояния
    private func resetState() {
        os_log("PoseProcessor: Сброс состояния после %d кадров без человека", log: OSLog.default, type: .debug, resetDelayFrames)
        repCount = 0
        inExercisePosition = false
        previousHipY = nil
        previousKneeY = nil
        framesWithoutPerson = 0
        exerciseStartTime = nil
        repDurations.removeAll()
        onRepCountUpdated?(repCount)
        onStateChanged?(inExercisePosition, repCount, nil) // Обновляем состояние при сбросе
    }
}
