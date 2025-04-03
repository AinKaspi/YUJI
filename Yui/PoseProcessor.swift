import MediaPipeTasksVision
import os.log

class PoseProcessor {
    
    private var repCount = 0
    private var isSquatting = false
    private var previousHipY: Float?
    private var previousKneeY: Float?
    private var framesWithoutPerson = 0
    private let resetDelayFrames = 10 // Задержка перед сбросом счётчика
    
    var onRepCountUpdated: ((Int) -> Void)?
    
    func processPoseLandmarks(_ result: PoseLandmarkerResult) {
        guard let landmarks = result.landmarks.first else {
            os_log("PoseProcessor: Нет обнаруженных ключевых точек", log: OSLog.default, type: .debug)
            framesWithoutPerson += 1
            if framesWithoutPerson >= resetDelayFrames {
                resetState()
            }
            return
        }
        
        framesWithoutPerson = 0
        
        let requiredLandmarks = [23, 24, 25, 26]
        var allVisible = true
        for index in requiredLandmarks {
            let visibility = landmarks[index].visibility?.doubleValue ?? 0.0
            let x = landmarks[index].x
            let y = landmarks[index].y
            os_log("PoseProcessor: Точка %d - x: %f, y: %f, visibility: %f", log: OSLog.default, type: .debug, index, x, y, visibility)
            if visibility < 0.7 {
                os_log("PoseProcessor: Ключевая точка %d не видна, visibility: %f", log: OSLog.default, type: .debug, index, visibility)
                allVisible = false
            }
        }
        
        guard allVisible else {
            os_log("PoseProcessor: Не все ключевые точки видны", log: OSLog.default, type: .debug)
            return
        }
        
        let leftHip = landmarks[23]
        let rightHip = landmarks[24]
        let leftKnee = landmarks[25]
        let rightKnee = landmarks[26]
        
        let hipY = (leftHip.y + rightHip.y) / 2
        let kneeY = (leftKnee.y + rightKnee.y) / 2
        
        os_log("PoseProcessor: hipY: %f, kneeY: %f, isSquatting: %d", log: OSLog.default, type: .debug, hipY, kneeY, isSquatting ? 1 : 0)
        
        let threshold: Float = 0.05
        
        if previousHipY != nil && previousKneeY != nil {
            // В нижней точке приседания hipY больше kneeY
            if hipY > kneeY + threshold && !isSquatting {
                isSquatting = true
                os_log("PoseProcessor: Начало приседания", log: OSLog.default, type: .debug)
            }
            // В верхней точке приседания hipY меньше kneeY
            else if hipY < kneeY - threshold && isSquatting {
                isSquatting = false
                repCount += 1
                os_log("PoseProcessor: Конец приседания, repCount: %d", log: OSLog.default, type: .debug, repCount)
                onRepCountUpdated?(repCount)
            }
        }
        
        self.previousHipY = hipY
        self.previousKneeY = kneeY
    }
    
    // MARK: - Функция: Сброс состояния
    private func resetState() {
        os_log("PoseProcessor: Сброс состояния после %d кадров без человека", log: OSLog.default, type: .debug, resetDelayFrames)
        repCount = 0
        isSquatting = false
        previousHipY = nil
        previousKneeY = nil
        framesWithoutPerson = 0
        onRepCountUpdated?(repCount)
    }
}
