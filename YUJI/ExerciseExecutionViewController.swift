import UIKit
import AVFoundation
import MediaPipeTasksVision
import CoreImage
import os.log

class ExerciseExecutionViewController: UIViewController, PoseLandmarkerLiveStreamDelegate {
    
    // MARK: - Свойства
    private let exercise: Exercise
    private var cameraManager: CameraManager!
    private var poseProcessor: PoseProcessor!
    
    private let exerciseLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 24, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let repsLabel: UILabel = {
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
    
    // MARK: - Инициализация
    init(exercise: Exercise) {
        self.exercise = exercise
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Жизненный цикл
    override func viewDidLoad() {
        super.viewDidLoad()
        os_log("ExerciseExecutionViewController: viewDidLoad вызван для %@", log: OSLog.default, type: .debug, exercise.name)
        setupUI()
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
    
    // MARK: - Функция: Настройка UI
    private func setupUI() {
        view.backgroundColor = .black
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
    func poseLandmarker(
        _ poseLandmarker: PoseLandmarker,
        didFinishDetection result: PoseLandmarkerResult?,
        timestampInMilliseconds: Int,
        error: Error?
    ) {
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
        
        // Обновляем состояние присутствия человека
        if !isPersonInFrame {
            isPersonInFrame = true
            framesSincePersonReentered = 0
        }
        
        framesWithoutLandmarks = 0
        
        // Вычисляем центр бёдер (midpoint of hips)
        let leftHip = landmarks[23]
        let rightHip = landmarks[24]
        let hipMidpointX = (leftHip.x + rightHip.x) / 2
        let hipMidpointY = (leftHip.y + rightHip.y) / 2
        lastHipMidpoint = (x: hipMidpointX, y: hipMidpointY)
        
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
        
        // Сглаживаем ключевые точки
        let smoothed = smoothLandmarks(landmarks, isInitial: false)
        lastLandmarks = landmarks
        smoothedLandmarks = smoothed
        
        poseProcessor.processPoseLandmarks(result)
        
        DispatchQueue.main.async { [weak self] in
            self?.instructionLabel.isHidden = true
            self?.drawLandmarks(smoothed)
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
        
        let lastLeftHip = last[23]
        let lastRightHip = last[24]
        let lastHipMidpointX = (lastLeftHip.x + lastRightHip.x) / 2
        let lastHipMidpointY = (lastLeftHip.y + lastRightHip.y) / 2
        
        let deltaX = hipMidpoint.x - lastHipMidpointX
        let deltaY = hipMidpoint.y - lastHipMidpointY
        
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
    
    // MARK: - Функция: Отрисовка ключевых точек
    private func drawLandmarks(_ landmarks: [NormalizedLandmark]?) {
        guard let landmarks = landmarks else {
            os_log("ExerciseExecutionViewController: Нет ключевых точек для отрисовки", log: OSLog.default, type: .debug)
            landmarksLayer.sublayers?.removeAll()
            return
        }
        
        landmarksLayer.sublayers?.removeAll()
        
        let screenWidth = view.bounds.width
        let screenHeight = view.bounds.height
        
        for (index, landmark) in landmarks.enumerated() {
            // Фильтруем точки с низкой видимостью или присутствием
            let visibility = landmark.visibility?.floatValue ?? 0.0
            let presence = landmark.presence?.floatValue ?? 0.0
            if visibility < 0.7 || presence < 0.7 {
                continue
            }
            
            let x = CGFloat(landmark.x)
            let y = CGFloat(landmark.y)
            
            // Пропускаем некорректные координаты
            if x < 0 || x > 1 || y < 0 || y > 1 {
                os_log("ExerciseExecutionViewController: Недопустимые координаты для точки %d: x=%f, y=%f", log: OSLog.default, type: .debug, index, x, y)
                continue
            }
            
            // Учитываем зеркальность фронтальной камеры
            let rotatedX = 1.0 - x // Зеркалим по горизонтали
            let rotatedY = y
            
            // Масштабируем к размерам экрана
            let scaledX = rotatedX * screenWidth
            let scaledY = rotatedY * screenHeight
            
            let pointLayer = CALayer()
            pointLayer.bounds = CGRect(x: 0, y: 0, width: 5, height: 5)
            pointLayer.position = CGPoint(x: scaledX, y: scaledY)
            pointLayer.backgroundColor = UIColor.red.cgColor
            landmarksLayer.addSublayer(pointLayer)
        }
    }
    
    // MARK: - Функция: Завершение упражнения
    @objc private func finishExercise() {
        navigationController?.popViewController(animated: true)
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
        
        let status = CVPixelBufferCreate(kCFAllocatorDefault, newWidth, newHeight, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &newPixelBuffer)
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
    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer, orientation: UIImage.Orientation, timestamp: Int64) {
        guard isPoseLandmarkerSetup, poseLandmarker != nil else {
            os_log("ExerciseExecutionViewController: PoseLandmarker не инициализирован", log: OSLog.default, type: .error)
            return
        }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            os_log("ExerciseExecutionViewController: Не удалось получить pixelBuffer из sampleBuffer", log: OSLog.default, type: .error)
            return
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        lastImageDimensions = (width: width, height: height)
        os_log("ExerciseExecutionViewController: Размеры изображения: %dx%d", log: OSLog.default, type: .debug, width, height)
        
        // Масштабируем изображение для улучшения детекции на расстоянии
        guard let scaledSampleBuffer = scaleImage(sampleBuffer, scaleFactor: scaleFactor) else {
            os_log("ExerciseExecutionViewController: Не удалось масштабировать изображение", log: OSLog.default, type: .error)
            return
        }
        
        guard let image = try? MPImage(sampleBuffer: scaledSampleBuffer, orientation: orientation) else {
            os_log("ExerciseExecutionViewController: Не удалось преобразовать CMSampleBuffer в MPImage", log: OSLog.default, type: .error)
            return
        }
        
        do {
            // Гарантируем строго возрастающие временные метки
            let timestampInMilliseconds = max(lastTimestamp + 1, Int(timestamp))
            lastTimestamp = timestampInMilliseconds
            try poseLandmarker?.detectAsync(image: image, timestampInMilliseconds: timestampInMilliseconds)
        } catch {
            os_log("ExerciseExecutionViewController: Ошибка обработки кадра: %@", log: OSLog.default, type: .error, error.localizedDescription)
        }
    }
}
