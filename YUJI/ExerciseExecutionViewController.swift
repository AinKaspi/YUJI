import UIKit
import AVFoundation
import MediaPipeTasksVision
import CoreImage
import os.log

class ExerciseExecutionViewController: UIViewController, PoseLandmarkerLiveStreamDelegate {
    
    // MARK: - Свойства
    internal let exercise: Exercise
    internal var cameraManager: CameraManager!
    private var poseProcessor: PoseProcessor!
    
    private let exerciseLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 24, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    internal let repsLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 20)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let instructionLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 18)
        label.textColor = .white
        label.textAlignment = .center
        label.text = "Подойдите ближе к камере"
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let finishButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Завершить", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .systemRed
        button.layer.cornerRadius = 10
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    private var poseLandmarker: PoseLandmarker?
    private var isPoseLandmarkerSetup = false
    private let landmarksLayer = CALayer()
    
    // Свойства для кэширования, сглаживания и стабилизации
    private var lastLandmarks: [NormalizedLandmark]?
    private var smoothedLandmarks: [NormalizedLandmark]?
    private var lastHipMidpoint: (x: Float, y: Float)? // Центр бёдер для ROI
    private var framesWithoutLandmarks = 0
    private let maxFramesWithoutLandmarks = 10 // Порог для перезапуска
    private var isPersonInFrame = false
    private var framesSincePersonReentered = 0
    private let stabilizationFrames = 5 // Период стабилизации после возвращения
    private let smoothingFactor: Float = 0.7 // Коэффициент сглаживания
    private let initialSmoothingFactor: Float = 0.9 // Более агрессивное сглаживание для первых кадров
    private var lastTimestamp: Int = 0 // Для строгого увеличения временных меток
    private var lastImageDimensions: (width: Int, height: Int) = (1080, 1920) // Размеры изображения
    private let scaleFactor: CGFloat = 1.5 // Коэффициент масштабирования для дальних объектов
    internal let repCountLabel = UILabel()
    
    // Фильтр Калмана для стабилизации ключевых точек
    private lazy var landmarkFilter = PoseLandmarkFilter(landmarksCount: 33)
    
    // Флаг для включения/выключения фильтра Калмана
    private let useKalmanFilter = true
    
    // Улучшитель изображений для адаптации к разным условиям
    private lazy var imageEnhancer = ImageEnhancer(enhancementType: .adaptiveEnhancement)
    
    // Флаг для включения/выключения улучшения изображения
    private let useImageEnhancement = false // Временно отключено для диагностики
    
    // Счетчик кадров для логирования и периодических действий
    private var frameCounter = 0
    
    // Счетчик последовательных ошибок
    private var consecutiveErrors = 0
    private let maxConsecutiveErrors = 5  // Максимальное количество последовательных ошибок
    
    // UI-элементы для обратной связи и статистики
    internal let feedbackLabel = UILabel()
    internal let qualityFeedbackView = UIView()
    internal let timerLabel = UILabel()
    internal var workoutStartTime: Date?
    
    // MARK: - Инициализация
    init(exercise: Exercise) {
        self.exercise = exercise
        super.init(nibName: nil, bundle: nil)
        
        // Определяем тип упражнения на основе названия
        let exerciseType = getExerciseTypeFromName(exercise.name)
        poseProcessor = PoseProcessor(exerciseType: exerciseType)
        
        // Устанавливаем обработчики событий
        setupCallbacks()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Жизненный цикл
    override func viewDidLoad() {
        super.viewDidLoad()
        os_log("ExerciseExecutionViewController: viewDidLoad вызван для %@", log: OSLog.default, type: .debug, exercise.name)
        setupUI()
        setupFeedbackLabels()
        setupTimerLabel()
        setupCloseButton()
        workoutStartTime = Date() // Запускаем таймер тренировки
        startWorkoutTimer()
        setupLoadingIndicator()
        setupCameraManager()
        setupMediaPipe()
        setupPoseProcessor()
        setupLandmarksLayer()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        os_log("ExerciseExecutionViewController: viewDidAppear вызван, запускаем камеру", log: OSLog.default, type: .debug)
        cameraManager.startSession()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        os_log("ExerciseExecutionViewController: viewWillDisappear вызван, останавливаем камеру", log: OSLog.default, type: .debug)
        cameraManager.stopSession()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cameraManager.updatePreviewLayerFrame(view.bounds)
        landmarksLayer.frame = view.bounds
    }
    
    // MARK: - Функция: Настройка обработчиков событий
    private func setupCallbacks() {
        // Настраиваем обработчик для событий PoseProcessor
        poseProcessor.onStateChanged = { [weak self] (isInPosition: Bool, repCount: Int, feedback: (message: String, isCritical: Bool)?) in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                // Обновляем счетчик повторений
                self.repsLabel.text = "\(repCount)"
                
                // Обновляем статус позиции
                self.updatePositionStatus(isInPosition)
                
                // Если есть обратная связь по качеству выполнения
                if let feedbackInfo = feedback {
                    self.showQualityFeedback(feedbackInfo.message, isCritical: feedbackInfo.isCritical)
                }
            }
        }
    }
    
    // MARK: - Функция: Настройка UI
    private func setupUI() {
        view.backgroundColor = .black
        title = exercise.name
        
        view.addSubview(exerciseLabel)
        view.addSubview(repsLabel)
        view.addSubview(instructionLabel)
        view.addSubview(finishButton)
        
        exerciseLabel.text = exercise.name
        repsLabel.text = "Повторения: 0"
        finishButton.addTarget(self, action: #selector(finishExercise), for: .touchUpInside)
        
        NSLayoutConstraint.activate([
            exerciseLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            exerciseLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            exerciseLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            repsLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            repsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            repsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            instructionLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50),
            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            instructionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            finishButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            finishButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            finishButton.widthAnchor.constraint(equalToConstant: 200),
            finishButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    // MARK: - Функция: Настройка индикатора загрузки
    private func setupLoadingIndicator() {
        view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        loadingIndicator.startAnimating()
    }
    
    // MARK: - Функция: Настройка слоя для ключевых точек
    private func setupLandmarksLayer() {
        landmarksLayer.frame = view.bounds
        landmarksLayer.backgroundColor = UIColor.clear.cgColor
        view.layer.addSublayer(landmarksLayer)
    }
    
    // MARK: - Функция: Настройка CameraManager
    private func setupCameraManager() {
        os_log("ExerciseExecutionViewController: Настройка CameraManager", log: OSLog.default, type: .debug)
        cameraManager = CameraManager()
        cameraManager.setupCamera { [weak self] previewLayer in
            guard let self = self else { return }
            os_log("ExerciseExecutionViewController: Камера настроена, добавляем previewLayer", log: OSLog.default, type: .debug)
            self.view.layer.insertSublayer(previewLayer, at: 0)
            self.cameraManager.updatePreviewLayerFrame(self.view.bounds)
            DispatchQueue.main.async {
                self.loadingIndicator.stopAnimating()
            }
        }
        cameraManager.delegate = self
    }
    
    // MARK: - Функция: Настройка MediaPipe
    private func setupMediaPipe() {
        os_log("ExerciseExecutionViewController: Настройка MediaPipe", log: OSLog.default, type: .debug)
        let startTime = Date()
        
        guard let modelPath = Bundle.main.path(forResource: "pose_landmarker_full", ofType: "task") else {
            os_log("ExerciseExecutionViewController: Не удалось найти файл модели pose_landmarker_full.task", log: OSLog.default, type: .error)
            return
        }
        
        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.baseOptions.delegate = .GPU
        options.runningMode = .liveStream
        options.numPoses = 1
        options.minPoseDetectionConfidence = 0.5 // Снижаем порог для лучшей детекции на расстоянии
        options.minTrackingConfidence = 0.7
        options.minPosePresenceConfidence = 0.7
        options.poseLandmarkerLiveStreamDelegate = self
        
        do {
            poseLandmarker = try PoseLandmarker(options: options)
            isPoseLandmarkerSetup = true
            let duration = Date().timeIntervalSince(startTime)
            os_log("ExerciseExecutionViewController: MediaPipe успешно настроен за %f секунд", log: OSLog.default, type: .debug, duration)
        } catch {
            os_log("ExerciseExecutionViewController: Ошибка инициализации Pose Landmarker: %@", log: OSLog.default, type: .error, error.localizedDescription)
        }
    }
    
    // MARK: - Функция: Настройка PoseProcessor
    private func setupPoseProcessor() {
        os_log("ExerciseExecutionViewController: Настройка PoseProcessor", log: OSLog.default, type: .debug)
        poseProcessor = PoseProcessor()
        poseProcessor.onRepCountUpdated = { [weak self] (count: Int) in
            DispatchQueue.main.async {
                self?.repsLabel.text = "Повторения: \(count)"
            }
        }
    }
    
    // MARK: - PoseLandmarkerLiveStreamDelegate
    // В Swift 6 метод не может быть одновременно nonisolated и @MainActor
    nonisolated func poseLandmarker(
        _ poseLandmarker: PoseLandmarker,
        didFinishDetection result: PoseLandmarkerResult?,
        timestampInMilliseconds: Int,
        error: Error?
    ) {
        // Переадресуем вызов на MainActor
        // Используем слабую ссылку для безопасного использования в Task
        Task { @MainActor [weak self] in
            guard let weakSelf = self else { return }
            await weakSelf.handlePoseLandmarkerResult(result: result, timestampInMilliseconds: timestampInMilliseconds, error: error)
        }
    }
    
    // Специальный метод для обработки результатов на главном потоке
    @MainActor private func handlePoseLandmarkerResult(result: PoseLandmarkerResult?, timestampInMilliseconds: Int, error: Error?) {
        // Увеличиваем счетчик кадров для логирования
        frameCounter += 1
        let shouldLog = frameCounter % 30 == 0 // Логируем примерно раз в секунду (30 fps)
        
        guard let result = result, error == nil else {
            os_log("ExerciseExecutionViewController: Ошибка обработки MediaPipe: %@", log: OSLog.default, type: .error, error?.localizedDescription ?? "Неизвестная ошибка")
            DispatchQueue.main.async { [weak self] in
                self?.handleLandmarkLoss()
            }
            return
        }
        
        guard let landmarks = result.landmarks.first else {
            os_log("ExerciseExecutionViewController: Нет обнаруженных ключевых точек", log: OSLog.default, type: .debug)
            DispatchQueue.main.async { [weak self] in
                self?.handleLandmarkLoss()
            }
            return
        }
        
        if shouldLog {
            os_log("ExerciseExecutionViewController: Получено %d ключевых точек", log: OSLog.default, type: .debug, landmarks.count)
        }
        
        // Обновляем состояние присутствия человека
        if !isPersonInFrame {
            isPersonInFrame = true
            framesSincePersonReentered = 0
            os_log("ExerciseExecutionViewController: Человек появился в кадре", log: OSLog.default, type: .debug)
        }
        
        framesWithoutLandmarks = 0
        
        // Вычисляем центр бёдер (midpoint of hips)
        let leftHip = landmarks[23]
        let rightHip = landmarks[24]
        let hipMidpointX = (leftHip.x + rightHip.x) / 2
        let hipMidpointY = (leftHip.y + rightHip.y) / 2
        lastHipMidpoint = (x: hipMidpointX, y: hipMidpointY)
        
        if shouldLog {
            os_log("ExerciseExecutionViewController: Центр бедер: x=%.3f, y=%.3f", log: OSLog.default, type: .debug, hipMidpointX, hipMidpointY)
        }
        
        // Пропускаем обработку во время периода стабилизации
        if framesSincePersonReentered < stabilizationFrames {
            framesSincePersonReentered += 1
            os_log("ExerciseExecutionViewController: Период стабилизации, кадр %d/%d", log: OSLog.default, type: .debug, framesSincePersonReentered, stabilizationFrames)
            
            // Используем последние известные точки с более агрессивным сглаживанием
            let predictedLandmarks = predictLandmarksDuringStabilization(landmarks)
            DispatchQueue.main.async { [weak self] in
                self?.instructionLabel.isHidden = true
                self?.drawLandmarks(predictedLandmarks)
            }
            return
        }
        
        // Обрабатываем ключевые точки - выбираем между фильтром Калмана и экспоненциальным сглаживанием
        var processedLandmarks: [NormalizedLandmark]
        var processingMethod: String
        
        if useKalmanFilter {
            // Используем фильтр Калмана
            processedLandmarks = landmarkFilter.process(landmarks: landmarks)
            processingMethod = "фильтр Калмана"
        } else {
            // Используем экспоненциальное сглаживание
            processedLandmarks = smoothLandmarks(landmarks, isInitial: false)
            processingMethod = "экспоненциальное сглаживание"
        }
        
        if shouldLog {
            os_log("ExerciseExecutionViewController: Обработка ключевых точек с использованием: %@", log: OSLog.default, type: .debug, processingMethod)
        }
        
        // Сохраняем для будущего использования
        lastLandmarks = landmarks
        smoothedLandmarks = processedLandmarks
        
        // Передаем результаты в PoseProcessor для анализа упражнений
        poseProcessor.processPoseLandmarks(result)
        
        DispatchQueue.main.async { [weak self] in
            self?.instructionLabel.isHidden = true
            self?.drawLandmarks(processedLandmarks)
        }
    }
    
    // MARK: - Функция: Предсказание точек во время периода стабилизации
    private func predictLandmarksDuringStabilization(_ currentLandmarks: [NormalizedLandmark]) -> [NormalizedLandmark] {
        guard let last = lastLandmarks, last.count == currentLandmarks.count else {
            return currentLandmarks
        }
        
        // Используем центр бёдер для корректировки позиций
        guard let hipMidpoint = lastHipMidpoint else {
            return smoothLandmarks(currentLandmarks, isInitial: true)
        }
        
        let leftHip = landmarks[23]
        let rightHip = landmarks[24]
        let hipMidpointX = (leftHip.x + rightHip.x) / 2
        let hipMidpointY = (leftHip.y + rightHip.y) / 2
        
        let deltaX = hipMidpoint.x - hipMidpointX
        let deltaY = hipMidpoint.y - hipMidpointY
        
        var predicted: [NormalizedLandmark] = []
        for i in 0..<last.count {
            let lastPoint = last[i]
            let newX = lastPoint.x + deltaX
            let newY = lastPoint.y + deltaY
            let predictedLandmark = NormalizedLandmark(
                x: newX,
                y: newY,
                z: lastPoint.z,
                visibility: lastPoint.visibility,
                presence: lastPoint.presence
            )
            predicted.append(predictedLandmark)
        }
        
        // Применяем более агрессивное сглаживание
        return smoothLandmarks(predicted, isInitial: true)
    }
    
    // MARK: - Функция: Обработка потери ключевых точек
    private func handleLandmarkLoss() {
        framesWithoutLandmarks += 1
        if framesWithoutLandmarks >= maxFramesWithoutLandmarks {
            os_log("ExerciseExecutionViewController: Долгая потеря ключевых точек, перезапускаем трекинг", log: OSLog.default, type: .debug)
            setupMediaPipe() // Перезапускаем MediaPipe
            framesWithoutLandmarks = 0
            // Не сбрасываем lastHipMidpoint, чтобы использовать его при восстановлении
            isPersonInFrame = false
            framesSincePersonReentered = 0
        }
        
        instructionLabel.isHidden = false
        drawLandmarks(smoothedLandmarks ?? lastLandmarks) // Используем последние известные точки
    }
    
    // MARK: - Функция: Сглаживание ключевых точек
    private func smoothLandmarks(_ landmarks: [NormalizedLandmark], isInitial: Bool) -> [NormalizedLandmark] {
        guard !landmarks.isEmpty else { return landmarks }
        
        var smoothed: [NormalizedLandmark] = []
        let factor = isInitial ? initialSmoothingFactor : smoothingFactor
        
        if smoothedLandmarks == nil || smoothedLandmarks!.count != landmarks.count {
            smoothedLandmarks = landmarks
            return landmarks
        }
        
        for i in 0..<landmarks.count {
            let current = landmarks[i]
            let previous = smoothedLandmarks![i]
            
            let smoothedX = factor * previous.x + (1 - factor) * current.x
            let smoothedY = factor * previous.y + (1 - factor) * current.y
            let smoothedZ = factor * previous.z + (1 - factor) * current.z
            
            let smoothedLandmark = NormalizedLandmark(
                x: smoothedX,
                y: smoothedY,
                z: smoothedZ,
                visibility: current.visibility,
                presence: current.presence
            )
            smoothed.append(smoothedLandmark)
        }
        
        return smoothed
    }
    
    // Список соединений между ключевыми точками MediaPipe Pose
    private let connections: [(Int, Int)] = [
        // Туловище
        (11, 12), // плечи
        (11, 23), // левое плечо - левое бедро
        (12, 24), // правое плечо - правое бедро
        (23, 24), // бедра
        
        // Руки
        (11, 13), (13, 15), // левая рука
        (12, 14), (14, 16), // правая рука
        
        // Ноги
        (23, 25), (25, 27), (27, 31), // левая нога
        (24, 26), (26, 28), (28, 32), // правая нога
        
        // Лицо
        (0, 1), (1, 2), (2, 3), (3, 7), (0, 4), (4, 5), (5, 6), (6, 8),
        (9, 10) // уши
    ]
    
    // Цвета для разных частей тела
    private let colors: [String: UIColor] = [
        "face": .yellow,
        "leftArm": .green,
        "rightArm": .blue,
        "leftLeg": .orange,
        "rightLeg": .purple,
        "torso": .cyan
    ]
    
    // Хранилище слоев для оптимизации отрисовки
    private var landmarkPointLayers: [Int: CAShapeLayer] = [:]
    private var connectionLineLayers: [String: CAShapeLayer] = [:]
    
    // MARK: - Функция: Отрисовка ключевых точек
    private func drawLandmarks(_ landmarks: [NormalizedLandmark]?) {
        guard let landmarks = landmarks else {
            os_log("ExerciseExecutionViewController: Нет ключевых точек для отрисовки", log: OSLog.default, type: .debug)
            // Скрываем слои вместо удаления для лучшей производительности
            landmarkPointLayers.values.forEach { $0.isHidden = true }
            connectionLineLayers.values.forEach { $0.isHidden = true }
            return
        }
        
        // Логируем только раз в 10 кадров
        if frameCounter % 10 == 0 {
            os_log("ExerciseExecutionViewController: Отрисовка %d ключевых точек", log: OSLog.default, type: .debug, landmarks.count)
        }
        frameCounter += 1
        
        let screenWidth = view.bounds.width
        let screenHeight = view.bounds.height
        
        // Строим массив точек в координатах экрана
        var points: [Int: CGPoint] = [:]
        var visiblePoints: Set<Int> = []
        
        // Преобразуем нормализованные координаты в координаты экрана
        for (index, landmark) in landmarks.enumerated() {
            let visibility = landmark.visibility?.floatValue ?? 0.0
            let presence = landmark.presence?.floatValue ?? 0.0
            
            if visibility < 0.5 || presence < 0.5 {
                continue
            }
            
            let x = CGFloat(landmark.x)
            let y = CGFloat(landmark.y)
            
            if x < 0 || x > 1 || y < 0 || y > 1 {
                continue
            }
            
            // Учитываем зеркальность фронтальной камеры
            let rotatedX = 1.0 - x // Зеркалим по горизонтали
            let rotatedY = y
            
            // Масштабируем к размерам экрана
            let screenPoint = CGPoint(
                x: rotatedX * screenWidth,
                y: rotatedY * screenHeight
            )
            
            points[index] = screenPoint
            visiblePoints.insert(index)
        }
        
        // Отрисовываем точки
        for (index, point) in points {
            let pointLayer: CAShapeLayer
            
            if let existingLayer = landmarkPointLayers[index] {
                // Используем существующий слой
                pointLayer = existingLayer
                pointLayer.isHidden = false
            } else {
                // Создаем новый слой
                pointLayer = CAShapeLayer()
                pointLayer.path = CGPath(ellipseIn: CGRect(x: -4, y: -4, width: 8, height: 8), transform: nil)
                
                // Выбираем цвет в зависимости от части тела
                if index >= 0 && index <= 10 {
                    pointLayer.fillColor = colors["face"]?.cgColor ?? UIColor.yellow.cgColor
                } else if index >= 11 && index <= 16 {
                    pointLayer.fillColor = (index % 2 == 1 ? colors["leftArm"] : colors["rightArm"])?.cgColor ?? UIColor.green.cgColor
                } else if index >= 23 && index <= 32 {
                    pointLayer.fillColor = (index % 2 == 1 ? colors["leftLeg"] : colors["rightLeg"])?.cgColor ?? UIColor.orange.cgColor
                } else {
                    pointLayer.fillColor = colors["torso"]?.cgColor ?? UIColor.cyan.cgColor
                }
                
                landmarksLayer.addSublayer(pointLayer)
                landmarkPointLayers[index] = pointLayer
            }
            
            // Анимируем перемещение точки
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.1) // Длительность анимации
            pointLayer.position = point
            CATransaction.commit()
        }
        
        // Скрываем невидимые точки
        for (index, layer) in landmarkPointLayers {
            if !visiblePoints.contains(index) {
                layer.isHidden = true
            }
        }
        
        // Отрисовываем соединительные линии
        for (index, connection) in connections.enumerated() {
            let startIndex = connection.0
            let endIndex = connection.1
            
            // Проверяем, что обе точки видимы
            guard let startPoint = points[startIndex], let endPoint = points[endIndex] else {
                connectionLineLayers["\(startIndex)-\(endIndex)"]?.isHidden = true
                continue
            }
            
            let connectionLayer: CAShapeLayer
            let connectionKey = "\(startIndex)-\(endIndex)"
            
            if let existingLayer = connectionLineLayers[connectionKey] {
                // Используем существующий слой
                connectionLayer = existingLayer
                connectionLayer.isHidden = false
            } else {
                // Создаем новый слой
                connectionLayer = CAShapeLayer()
                connectionLayer.lineWidth = 2.0
                connectionLayer.lineCap = .round
                
                // Выбираем цвет в зависимости от части тела
                if startIndex >= 0 && startIndex <= 10 && endIndex >= 0 && endIndex <= 10 {
                    connectionLayer.strokeColor = colors["face"]?.cgColor ?? UIColor.yellow.cgColor
                } else if (startIndex >= 11 && startIndex <= 16) || (endIndex >= 11 && endIndex <= 16) {
                    connectionLayer.strokeColor = (startIndex % 2 == 1 ? colors["leftArm"] : colors["rightArm"])?.cgColor ?? UIColor.green.cgColor
                } else if (startIndex >= 23 && startIndex <= 32) || (endIndex >= 23 && endIndex <= 32) {
                    connectionLayer.strokeColor = (startIndex % 2 == 1 ? colors["leftLeg"] : colors["rightLeg"])?.cgColor ?? UIColor.orange.cgColor
                } else {
                    connectionLayer.strokeColor = colors["torso"]?.cgColor ?? UIColor.cyan.cgColor
                }
                
                landmarksLayer.insertSublayer(connectionLayer, at: 0) // Размещаем линии под точками
                connectionLineLayers[connectionKey] = connectionLayer
            }
            
            // Создаем путь для линии
            let path = UIBezierPath()
            path.move(to: startPoint)
            path.addLine(to: endPoint)
            
            // Анимируем изменение пути
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.1)
            connectionLayer.path = path.cgPath
            CATransaction.commit()
        }
        
        // Скрываем невидимые соединения
        for (key, layer) in connectionLineLayers {
            let components = key.split(separator: "-")
            if components.count == 2,
               let startIndex = Int(components[0]),
               let endIndex = Int(components[1]),
               points[startIndex] == nil || points[endIndex] == nil {
                layer.isHidden = true
            }
        }
    }
    
    // MARK: - Функция: Завершение упражнения 
    // Примечание: функциональность перенесена в расширение UIExtensions
    
    // MARK: - Функция: Определение ROI (Region of Interest)
    private func calculateROI() -> CGRect {
        // Если у нас нет данных о положении человека, используем всё изображение
        guard let hipMidpoint = lastHipMidpoint else {
            return CGRect(x: 0, y: 0, width: lastImageDimensions.width, height: lastImageDimensions.height)
        }
        
        // Вычисляем ROI вокруг центра тела
        // Берем 70% от ширины и 80% от высоты для захвата всего тела
        let roiWidth = min(lastImageDimensions.width, Int(lastImageDimensions.width))
        let roiHeight = min(lastImageDimensions.height, Int(lastImageDimensions.height))
        
        // Вычисляем центр ROI на основе midpoint бедер
        // Нормализованные координаты (от 0 до 1) преобразуем в координаты изображения
        let centerX = Int(hipMidpoint.x * Float(lastImageDimensions.width))
        let centerY = Int(hipMidpoint.y * Float(lastImageDimensions.height))
        
        // Координаты верхнего левого угла ROI
        let x = max(0, centerX - roiWidth/2)
        let y = max(0, centerY - roiHeight/2)
        
        // Корректируем размеры, чтобы не выйти за границы изображения
        return CGRect(
            x: x,
            y: y, 
            width: min(roiWidth, lastImageDimensions.width - x),
            height: min(roiHeight, lastImageDimensions.height - y)
        )
    }
    
    // MARK: - Функция: Обрезка кадра до ROI
    private func cropToROI(sampleBuffer: CMSampleBuffer, roi: CGRect) -> CMSampleBuffer? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            os_log("ExerciseExecutionViewController: Не удалось получить pixelBuffer", log: OSLog.default, type: .error)
            return nil
        }
        
        // Создаем CIImage из pixelBuffer
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Нормализуем координаты ROI к размерам изображения (0.0-1.0)
        let normalizedROI = CGRect(
            x: roi.origin.x / CGFloat(CVPixelBufferGetWidth(pixelBuffer)),
            y: roi.origin.y / CGFloat(CVPixelBufferGetHeight(pixelBuffer)),
            width: roi.width / CGFloat(CVPixelBufferGetWidth(pixelBuffer)), 
            height: roi.height / CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        )
        
        // Обрезаем изображение
        let croppedImage = ciImage.cropped(to: normalizedROI)
        
        os_log("ExerciseExecutionViewController: Обрезка ROI: x=%f, y=%f, w=%f, h=%f", 
               log: OSLog.default, type: .debug, 
               normalizedROI.origin.x, normalizedROI.origin.y, 
               normalizedROI.width, normalizedROI.height)
        
        // Создаём новый pixelBuffer для обрезанного изображения
        var newPixelBuffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(roi.width),
            Int(roi.height),
            kCVPixelFormatType_32BGRA,
            attrs,
            &newPixelBuffer
        )
        
        guard status == kCVReturnSuccess, let outputBuffer = newPixelBuffer else {
            os_log("ExerciseExecutionViewController: Не удалось создать pixelBuffer для ROI", log: OSLog.default, type: .error)
            return nil
        }
        
        // Рендерим обрезанное изображение в новый pixelBuffer
        let context = CIContext()
        context.render(croppedImage, to: outputBuffer)
        
        // Создаём новый CMSampleBuffer из нового pixelBuffer
        var newSampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo()
        CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timingInfo)
        
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: outputBuffer,
            formatDescriptionOut: &formatDescription
        )
        
        let createStatus = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: outputBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription!,
            sampleTiming: &timingInfo,
            sampleBufferOut: &newSampleBuffer
        )
        
        guard createStatus == kCVReturnSuccess, let finalSampleBuffer = newSampleBuffer else {
            os_log("ExerciseExecutionViewController: Не удалось создать sampleBuffer для ROI", log: OSLog.default, type: .error)
            return nil
        }
        
        return finalSampleBuffer
    }
    
    // MARK: - Функция: Масштабирование изображения
    private func scaleImage(_ sampleBuffer: CMSampleBuffer, scaleFactor: CGFloat) -> CMSampleBuffer? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            os_log("ExerciseExecutionViewController: Не удалось получить pixelBuffer из sampleBuffer", log: OSLog.default, type: .error)
            return nil
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        let newWidth = Int(CGFloat(width) * scaleFactor)
        let newHeight = Int(CGFloat(height) * scaleFactor)
        
        // Создаём CIImage из pixelBuffer
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Масштабируем изображение
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleFactor, y: scaleFactor))
        
        // Создаём новый pixelBuffer для масштабированного изображения
        var newPixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferWidthKey as String: newWidth,
            kCVPixelBufferHeightKey as String: newHeight
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            newWidth,
            newHeight,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &newPixelBuffer
        )
        
        guard status == kCVReturnSuccess, let outputPixelBuffer = newPixelBuffer else {
            os_log("ExerciseExecutionViewController: Не удалось создать новый pixelBuffer", log: OSLog.default, type: .error)
            return nil
        }
        
        // Рендерим масштабированное изображение в новый pixelBuffer
        let context = CIContext()
        context.render(scaledImage, to: outputPixelBuffer)
        
        // Создаём новый CMSampleBuffer
        var newSampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo()
        CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timingInfo)
        
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: outputPixelBuffer, formatDescriptionOut: &formatDescription)
        
        let createStatus = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: outputPixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription!,
            sampleTiming: &timingInfo,
            sampleBufferOut: &newSampleBuffer
        )
        
        guard createStatus == kCVReturnSuccess, let finalSampleBuffer = newSampleBuffer else {
            os_log("ExerciseExecutionViewController: Не удалось создать новый sampleBuffer", log: OSLog.default, type: .error)
            return nil
        }
        
        return finalSampleBuffer
    }
}

// MARK: - CameraManagerDelegate
extension ExerciseExecutionViewController: CameraManagerDelegate {
    // В Swift 6 метод не может быть одновременно nonisolated и @MainActor
    nonisolated func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer, orientation: UIImage.Orientation, timestamp: Int64) {
        // Переадресуем обработку на главный поток
        let copiedBuffer = sampleBuffer
        // Используем слабую ссылку для безопасного использования в Task
        Task { @MainActor [weak self] in
            guard let weakSelf = self else { return }
            await weakSelf.handleCameraOutput(manager: manager, sampleBuffer: copiedBuffer, orientation: orientation, timestamp: timestamp)
        }
    }
    
    // Метод для обработки вывода камеры на главном потоке
    @MainActor private func handleCameraOutput(manager: CameraManager, sampleBuffer: CMSampleBuffer, orientation: UIImage.Orientation, timestamp: Int64) {
        guard isPoseLandmarkerSetup, poseLandmarker != nil else {
            os_log("ExerciseExecutionViewController: PoseLandmarker не инициализирован", log: OSLog.default, type: .error)
            return
        }
        
        // 1. Улучшаем изображение при необходимости
        var enhancedBuffer = sampleBuffer
        if useImageEnhancement {
            // Принудительно анализируем изображение каждые 60 кадров или при наличии ошибок
            let forceAnalysis = frameCounter % 60 == 0 || consecutiveErrors > 2
            enhancedBuffer = imageEnhancer.enhanceImage(sampleBuffer, forceAnalysis: forceAnalysis)
            
            if frameCounter % 60 == 0 {
                os_log("ExerciseExecutionViewController: Применено улучшение изображения", log: OSLog.default, type: .debug)
            }
        }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(enhancedBuffer) else {
            os_log("ExerciseExecutionViewController: Не удалось получить pixelBuffer", log: OSLog.default, type: .error)
            consecutiveErrors += 1
            return
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        lastImageDimensions = (width: width, height: height)
        
        // 2. Выбираем метод обработки в зависимости от стадии трекинга
        var processedBuffer: CMSampleBuffer = enhancedBuffer
        var processingMethod = "enhanced"
        
        // Если мы трекаем человека и знаем положение тела, используем ROI
        if framesWithoutLandmarks == 0 && lastHipMidpoint != nil {
            let roi = calculateROI()
            if let croppedBuffer = cropToROI(sampleBuffer: enhancedBuffer, roi: roi) {
                processedBuffer = croppedBuffer
                processingMethod = "ROI + enhanced"
            }
        } else {
            // Человек не обнаружен или потерян, применяем масштабирование
            if let scaled = scaleImage(enhancedBuffer, scaleFactor: scaleFactor) {
                processedBuffer = scaled
                processingMethod = "scaled + enhanced"
            }
        }
        
        frameCounter += 1
        if frameCounter % 30 == 0 {
            os_log("ExerciseExecutionViewController: Обработка кадра методом: %@", log: OSLog.default, type: .debug, processingMethod)
        }
        
        // 3. Преобразуем в MPImage и отправляем на обработку
        guard let image = try? MPImage(sampleBuffer: processedBuffer, orientation: orientation) else {
            os_log("ExerciseExecutionViewController: Не удалось преобразовать CMSampleBuffer в MPImage", log: OSLog.default, type: .error)
            consecutiveErrors += 1
            return
        }
        
        // Если дошли до этого места, значит ошибок нет
        consecutiveErrors = 0
        
        do {
            // Гарантируем строго возрастающие временные метки
            let currentTimestamp = Int(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1000)
            let timestampForDetection = max(currentTimestamp, lastTimestamp + 1)
            lastTimestamp = timestampForDetection // Обновляем последнюю метку
            
            // Получаем и логируем размеры изображения
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            os_log("ExerciseExecutionViewController: Размеры изображения: %dx%d, ориентация: %d", 
                  log: OSLog.default, type: .debug, width, height, image.imageOrientation.rawValue)
            
            // Создаем опции с явным указанием размеров
            let options = PoseLandmarkerOptions()
            options.runningMode = .liveStream
            options.delegate = self
            options.numPoses = 1
            options.minPoseDetectionConfidence = 0.5
            options.minPosePresenceConfidence = 0.5
            options.minTrackingConfidence = 0.5
            
            // Выполняем детекцию асинхронно с явными размерами
            try poseLandmarker?.detectAsync(image: image, timestampMs: timestampForDetection)
            os_log("ExerciseExecutionViewController: Задание на детекцию отправлено с timestamp %d", log: OSLog.default, type: .debug, timestampForDetection)
            
        } catch {
            os_log("ExerciseExecutionViewController: Ошибка обработки кадра: %@", log: OSLog.default, type: .error, error.localizedDescription)
            consecutiveErrors += 1
            
            // При повторяющихся ошибках меняем режим улучшения на заданный период
            if consecutiveErrors >= maxConsecutiveErrors {
                // Меры по восстановлению при повторяющихся ошибках
                imageEnhancer.setEnhancementType(.lowLight) // Пробуем режим низкой освещенности
                os_log("ExerciseExecutionViewController: Слишком много ошибок, переключаемся в режим низкой освещенности", log: OSLog.default, type: .info)
                consecutiveErrors = 0
                
                // Через 50 кадров вернемся к адаптивному режиму
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.imageEnhancer.setEnhancementType(.adaptiveEnhancement)
                    os_log("ExerciseExecutionViewController: Возврат к адаптивному режиму", log: OSLog.default, type: .info)
                }
            }
        }
    }
}
