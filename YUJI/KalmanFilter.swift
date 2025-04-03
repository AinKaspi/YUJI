import Foundation
import MediaPipeTasksVision
import os.log

/// Реализация фильтра Калмана для одномерного значения
class KalmanFilter {
    private var x: Float // Оценка текущего состояния
    private var p: Float // Ковариация ошибки
    private let q: Float // Шум процесса
    private let r: Float // Шум измерений
    
    /// Инициализация нового фильтра Калмана
    /// - Parameters:
    ///   - initialValue: Начальное значение
    ///   - processNoise: Шум процесса (q)
    ///   - measurementNoise: Шум измерения (r)
    init(initialValue: Float, processNoise: Float = 0.001, measurementNoise: Float = 0.01) {
        self.x = initialValue
        self.p = 1.0
        self.q = processNoise
        self.r = measurementNoise
        
        os_log("KalmanFilter: Инициализирован с начальным значением %f, q=%f, r=%f", 
               log: OSLog.default, type: .debug, initialValue, processNoise, measurementNoise)
    }
    
    /// Обновляет фильтр на основе нового измерения
    /// - Parameter measurement: Новое измерение
    /// - Returns: Сглаженное значение
    func update(measurement: Float) -> Float {
        // Предсказание (a priori)
        let x_pred = x
        let p_pred = p + q
        
        // Обновление (a posteriori)
        let k = p_pred / (p_pred + r) // Коэффициент Калмана
        x = x_pred + k * (measurement - x_pred)
        p = (1 - k) * p_pred
        
        return x
    }
}

/// Фильтр для стабилизации ключевых точек позы
class PoseLandmarkFilter {
    private var xFilters: [KalmanFilter] = []
    private var yFilters: [KalmanFilter] = []
    private var zFilters: [KalmanFilter] = []
    private let landmarksCount: Int
    private var isInitialized = false
    
    /// Константы для оптимальной работы фильтра 
    /// (подобраны эмпирически и могут быть настроены)
    private let processNoise: Float = 0.0015  // Шум процесса (меньше = больше сглаживания)
    private let measurementNoise: Float = 0.05  // Шум измерений (меньше = быстрее реакция)
    
    init(landmarksCount: Int = 33) {
        self.landmarksCount = landmarksCount
        os_log("PoseLandmarkFilter: Создан для %d точек", log: OSLog.default, type: .debug, landmarksCount)
    }
    
    /// Инициализирует фильтры для всех точек
    private func initializeFilters(with landmarks: [NormalizedLandmark]) {
        os_log("PoseLandmarkFilter: Инициализация фильтров с %d ключевыми точками", 
               log: OSLog.default, type: .debug, landmarks.count)
        
        // Очищаем существующие фильтры
        xFilters.removeAll()
        yFilters.removeAll()
        zFilters.removeAll()
        
        // Создаем новые фильтры для каждой точки
        for landmark in landmarks {
            xFilters.append(KalmanFilter(initialValue: landmark.x, 
                                         processNoise: processNoise, 
                                         measurementNoise: measurementNoise))
            
            yFilters.append(KalmanFilter(initialValue: landmark.y, 
                                         processNoise: processNoise, 
                                         measurementNoise: measurementNoise))
            
            zFilters.append(KalmanFilter(initialValue: landmark.z, 
                                         processNoise: processNoise, 
                                         measurementNoise: measurementNoise))
        }
        
        isInitialized = true
    }
    
    /// Применяет фильтр Калмана к набору ключевых точек
    /// - Parameter landmarks: Исходные ключевые точки
    /// - Returns: Сглаженные ключевые точки
    func process(landmarks: [NormalizedLandmark]) -> [NormalizedLandmark] {
        // Если кол-во точек не совпадает с ожидаемым или это первый вызов - инициализируем фильтры
        if !isInitialized || landmarks.count != xFilters.count {
            initializeFilters(with: landmarks)
        }
        
        var filteredLandmarks: [NormalizedLandmark] = []
        
        // Применяем фильтр к каждой точке
        for (i, landmark) in landmarks.enumerated() {
            let filteredX = xFilters[i].update(measurement: landmark.x)
            let filteredY = yFilters[i].update(measurement: landmark.y)
            let filteredZ = zFilters[i].update(measurement: landmark.z)
            
            // Создаем новую точку с фильтрованными координатами
            let filteredLandmark = NormalizedLandmark(
                x: filteredX,
                y: filteredY,
                z: filteredZ,
                visibility: landmark.visibility,
                presence: landmark.presence
            )
            
            filteredLandmarks.append(filteredLandmark)
        }
        
        // Добавляем диагностику для некоторых ключевых точек (например, для носа)
        if landmarks.count > 0 {
            let noseIndex = 0 // Нос обычно имеет индекс 0
            os_log("PoseLandmarkFilter: Нос - исходный: (%.3f, %.3f), фильтрованный: (%.3f, %.3f)", 
                   log: OSLog.default, type: .debug,
                   landmarks[noseIndex].x, landmarks[noseIndex].y,
                   filteredLandmarks[noseIndex].x, filteredLandmarks[noseIndex].y)
        }
        
        return filteredLandmarks
    }
}
