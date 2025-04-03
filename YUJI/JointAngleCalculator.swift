import Foundation
import MediaPipeTasksVision
import os.log
import UIKit

/// Структура для хранения данных о угле сустава
struct JointAngle {
    let name: String          // Название сустава (например, "leftKnee")
    let angle: Float          // Угол в градусах
    let isValid: Bool         // Флаг валидности угла
    
    // Дополнительные значения для анализа
    let confidence: Float     // Уверенность в определении угла (0-1)
    let previousAngle: Float? // Предыдущее значение угла
    let velocity: Float?      // Скорость изменения угла (град/сек)
}

/// Класс для расчета углов в суставах из ключевых точек MediaPipe
class JointAngleCalculator {
    
    // Хранение предыдущих углов для расчета скорости изменения
    private var previousAngles: [String: (angle: Float, timestamp: TimeInterval)] = [:]
    private var lastUpdateTime: TimeInterval = Date().timeIntervalSince1970
    
    /// Рассчитывает все важные углы в суставах на основе ключевых точек
    /// - Parameter landmarks: Массив ключевых точек от MediaPipe
    /// - Returns: Словарь с углами суставов
    func calculateJointAngles(landmarks: [NormalizedLandmark]) -> [String: JointAngle] {
        guard landmarks.count >= 33 else {
            os_log("JointAngleCalculator: Недостаточно точек для расчета углов (%d)", 
                   log: OSLog.default, type: .error, landmarks.count)
            return [:]
        }
        
        // Текущее время для расчета скорости изменения угла
        let currentTime = Date().timeIntervalSince1970
        
        // Словарь для результатов
        var angles: [String: JointAngle] = [:]
        
        // Расчет углов в коленях
        if let leftKneeAngle = calculateKneeAngle(landmarks: landmarks, isLeft: true) {
            let name = "leftKnee"
            let velocity = calculateVelocity(name: name, currentAngle: leftKneeAngle, currentTime: currentTime)
            
            angles[name] = JointAngle(
                name: name,
                angle: leftKneeAngle,
                isValid: true,
                confidence: calculateConfidence(landmarks: landmarks, indices: [23, 25, 27]),
                previousAngle: previousAngles[name]?.angle,
                velocity: velocity
            )
            
            os_log("JointAngleCalculator: Левое колено - угол: %.1f°, скорость: %.2f°/с", 
                   log: OSLog.default, type: .debug, leftKneeAngle, velocity ?? 0)
        }
        
        if let rightKneeAngle = calculateKneeAngle(landmarks: landmarks, isLeft: false) {
            let name = "rightKnee"
            let velocity = calculateVelocity(name: name, currentAngle: rightKneeAngle, currentTime: currentTime)
            
            angles[name] = JointAngle(
                name: name,
                angle: rightKneeAngle,
                isValid: true,
                confidence: calculateConfidence(landmarks: landmarks, indices: [24, 26, 28]),
                previousAngle: previousAngles[name]?.angle,
                velocity: velocity
            )
            
            // Логирование с меньшей частотой
            if Int(currentTime * 10) % 30 == 0 {
                os_log("JointAngleCalculator: Правое колено - угол: %.1f°, скорость: %.2f°/с", 
                       log: OSLog.default, type: .debug, rightKneeAngle, velocity ?? 0)
            }
        }
        
        // Обновляем предыдущие значения для будущих расчетов
        updatePreviousValues(angles: angles, timestamp: currentTime)
        
        return angles
    }
    
    /// Определяет аномалии в углах суставов
    /// - Parameter angles: Словарь с углами суставов
    /// - Returns: Массив описаний обнаруженных аномалий
    func detectAnomalies(angles: [String: JointAngle]) -> [String] {
        var anomalies: [String] = []
        
        // Проверка углов в коленях
        if let leftKnee = angles["leftKnee"], let rightKnee = angles["rightKnee"],
           leftKnee.isValid && rightKnee.isValid {
            
            // Проверка на асимметрию
            let kneeAngleDifference = abs(leftKnee.angle - rightKnee.angle)
            if kneeAngleDifference > 15 {
                anomalies.append("Асимметрия в коленях: \(Int(kneeAngleDifference))°")
                os_log("JointAngleCalculator: Обнаружена асимметрия в коленях: %.1f°", 
                       log: OSLog.default, type: .info, kneeAngleDifference)
            }
            
            // Проверка на неестественный угол в коленях
            for (name, angle) in [("левом", leftKnee.angle), ("правом", rightKnee.angle)] {
                if angle < 60 || angle > 175 {
                    anomalies.append("Необычный угол в \(name) колене: \(Int(angle))°")
                    os_log("JointAngleCalculator: Необычный угол в %@ колене: %.1f°", 
                           log: OSLog.default, type: .info, name, angle)
                }
            }
            
            // Проверка на слишком быструю скорость движения
            for (name, joint) in [("левое", leftKnee), ("правое", rightKnee)] {
                if let velocity = joint.velocity, abs(velocity) > 300 {
                    anomalies.append("Слишком быстрое движение в \(name) колене: \(Int(velocity))°/с")
                    os_log("JointAngleCalculator: Быстрое движение в %@ колене: %.1f°/с", 
                           log: OSLog.default, type: .info, name, velocity)
                }
            }
        }
        
        return anomalies
    }
    
    // MARK: - Private helper methods
    
    /// Рассчитывает угол в колене
    private func calculateKneeAngle(landmarks: [NormalizedLandmark], isLeft: Bool) -> Float? {
        let hipIndex = isLeft ? 23 : 24
        let kneeIndex = isLeft ? 25 : 26
        let ankleIndex = isLeft ? 27 : 28
        
        guard landmarks.count > ankleIndex else { return nil }
        
        let hip = landmarks[hipIndex]
        let knee = landmarks[kneeIndex]
        let ankle = landmarks[ankleIndex]
        
        // Проверяем видимость точек
        let hipVis = hip.visibility?.floatValue ?? 0
        let kneeVis = knee.visibility?.floatValue ?? 0
        let ankleVis = ankle.visibility?.floatValue ?? 0
        
        if hipVis < 0.5 || kneeVis < 0.5 || ankleVis < 0.5 {
            return nil
        }
        
        return calculateAngle(
            point1: CGPoint(x: CGFloat(hip.x), y: CGFloat(hip.y)),
            point2: CGPoint(x: CGFloat(knee.x), y: CGFloat(knee.y)),
            point3: CGPoint(x: CGFloat(ankle.x), y: CGFloat(ankle.y))
        )
    }
    
    /// Рассчитывает угол между тремя точками (в градусах)
    private func calculateAngle(point1: CGPoint, point2: CGPoint, point3: CGPoint) -> Float {
        // Вектор от точки 2 (сустав) к точке 1
        let vector1 = CGPoint(x: point1.x - point2.x, y: point1.y - point2.y)
        
        // Вектор от точки 2 (сустав) к точке 3
        let vector2 = CGPoint(x: point3.x - point2.x, y: point3.y - point2.y)
        
        // Скалярное произведение
        let dotProduct = vector1.x * vector2.x + vector1.y * vector2.y
        
        // Длины векторов
        let magnitude1 = sqrt(vector1.x * vector1.x + vector1.y * vector1.y)
        let magnitude2 = sqrt(vector2.x * vector2.x + vector2.y * vector2.y)
        
        // Защита от деления на ноль
        guard magnitude1 > 0 && magnitude2 > 0 else { return 0 }
        
        // Косинус угла
        let cosAngle = dotProduct / (magnitude1 * magnitude2)
        
        // Защита от ошибок вычисления, которые могут привести к значениям вне [-1, 1]
        let clampedCosAngle = max(-1.0, min(1.0, cosAngle))
        
        // Угол в радианах и перевод в градусы
        let angleRadians = acos(clampedCosAngle)
        let angleDegrees = angleRadians * 180.0 / .pi
        
        return Float(angleDegrees)
    }
    
    /// Рассчитывает уверенность в определении угла на основе видимости ключевых точек
    private func calculateConfidence(landmarks: [NormalizedLandmark], indices: [Int]) -> Float {
        var totalConfidence: Float = 0
        
        for index in indices {
            guard index < landmarks.count else { continue }
            let visibility = landmarks[index].visibility?.floatValue ?? 0
            let presence = landmarks[index].presence?.floatValue ?? 0
            
            // Усредняем видимость и присутствие
            let pointConfidence = (visibility + presence) / 2
            totalConfidence += pointConfidence
        }
        
        return totalConfidence / Float(indices.count)
    }
    
    /// Вычисляет скорость изменения угла в градусах в секунду
    private func calculateVelocity(name: String, currentAngle: Float, currentTime: TimeInterval) -> Float? {
        guard let previous = previousAngles[name] else { return nil }
        
        let timeDiff = currentTime - previous.timestamp
        guard timeDiff > 0 else { return nil }
        
        let angleDiff = currentAngle - previous.angle
        return angleDiff / Float(timeDiff)
    }
    
    /// Обновляет хранилище предыдущих значений
    private func updatePreviousValues(angles: [String: JointAngle], timestamp: TimeInterval) {
        for (name, angle) in angles {
            previousAngles[name] = (angle: angle.angle, timestamp: timestamp)
        }
        
        lastUpdateTime = timestamp
    }
}
