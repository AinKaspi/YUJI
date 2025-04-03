import AVFoundation
import UIKit
import os.log

protocol CameraManagerDelegate: AnyObject {
    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer, orientation: UIImage.Orientation, timestamp: Int64)
}

/// Перечисление для уровней разрешения камеры
enum CameraResolution {
    case low     // 640x480
    case medium  // 1280x720
    case high    // 1920x1080
    
    var preset: AVCaptureSession.Preset {
        switch self {
        case .low:
            return .vga640x480
        case .medium:
            return .hd1280x720
        case .high:
            return .hd1920x1080
        }
    }
    
    var description: String {
        switch self {
        case .low: return "низкое (640x480)"
        case .medium: return "среднее (1280x720)"
        case .high: return "высокое (1920x1080)"
        }
    }
}

class CameraManager: NSObject {
    private let captureSession = AVCaptureSession()
    private var videoDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let sessionQueue = DispatchQueue(label: "com.yui.cameraSessionQueue", qos: .userInitiated)
    private let processingQueue = DispatchQueue(label: "com.yui.processingQueue", qos: .userInitiated)
    
    // Текущая ориентация устройства (для безопасного доступа из фоновых потоков)
    private var currentOrientation: UIImage.Orientation? = .right
    
    // Наблюдатель за изменением ориентации устройства
    private var orientationObserver: NSObjectProtocol?
    
    // Свойства для буферизации и управления разрешением
    private var currentResolution: CameraResolution = .medium
    private let frameBufferSize = 3
    private var frameBuffer: [CMSampleBuffer] = []
    private let frameBufferLock = NSLock()
    
    weak var delegate: CameraManagerDelegate?
    
    override init() {
        super.init()
        os_log("CameraManager: Инициализация", log: OSLog.default, type: .debug)
        
        // Вызываем setupCamera с завершающим блоком, который принимает previewLayer
        setupCamera() { _ in
            // Ничего не делаем с previewLayer в этом случае, так как он будет получен через свойство previewLayer
        }
        
        // В Swift 6 мы не можем передавать актор-изолированные значения в Task
        // Вместо этого, создадим новый независимый таск, который сам настроит наблюдателя
        initOrientationObserver()
    }
    
    // Инициализируем наблюдение за ориентацией устройства
    private func initOrientationObserver() {
        // В Swift 6 мы не можем передавать изолированные значения в Task
        // Поэтому запускаем статический метод, который будет управлять этим процессом
        CameraManager.initializeOrientationObserver(for: self)
    }
    
    /// Статический метод для запуска наблюдателя ориентации на главном потоке
    static func initializeOrientationObserver(for manager: CameraManager) {
        // Сохраняем адрес менеджера как небезопасный указатель
        // Это безопасный способ передачи идентификатора объекта в @Sendable контекст
        let managerAddress = UInt(bitPattern: Unmanaged.passUnretained(manager).toOpaque())
        
        // Запускаем задачу на главном потоке
        DispatchQueue.main.async {
            // Обратно получаем менеджер из адреса (это безопасно на главном потоке)
            let ptr = UnsafeRawPointer(bitPattern: managerAddress)
            guard let ptr = ptr else { return }
            let retrievedManager = Unmanaged<CameraManager>.fromOpaque(ptr).takeUnretainedValue()
            
            // На главном потоке мы можем считать ориентацию
            let deviceOrientation = UIDevice.current.orientation
            
            // Настраиваем ориентацию и наблюдатель
            retrievedManager.setupOrientationOnMainThread(deviceOrientation)
        }
    }
    
    // Настройка ориентации на главном потоке (вызывается из DispatchQueue.main)
    private func setupOrientationOnMainThread(_ deviceOrientation: UIDeviceOrientation) {
        // Конвертируем и сохраняем ориентацию
        switch deviceOrientation {
        case .portrait:
            currentOrientation = .right
        case .portraitUpsideDown:
            currentOrientation = .left
        case .landscapeLeft:
            currentOrientation = .up
        case .landscapeRight:
            currentOrientation = .down
        default:
            currentOrientation = .right // Значение по умолчанию
        }
        
        os_log("CameraManager: Ориентация устройства изменена: %@", log: OSLog.default, type: .debug, String(describing: currentOrientation))
        
        // Удаляем существующий наблюдатель, если он существует
        if let observer = orientationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        // Создаем новый наблюдатель
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Вместо прямого доступа к UI в замыкании, создаем новую Task
            Task { @MainActor in
                guard let self = self else { return }
                // На MainActor мы можем безопасно получить ориентацию
                let deviceOrientation = UIDevice.current.orientation
                self.convertAndStoreOrientation(deviceOrientation)
            }
        }
    }
    
    // Конвертирует и сохраняет ориентацию
    @MainActor private func convertAndStoreOrientation(_ deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portrait:
            currentOrientation = .right
        case .portraitUpsideDown:
            currentOrientation = .left
        case .landscapeLeft:
            currentOrientation = .up
        case .landscapeRight:
            currentOrientation = .down
        default:
            currentOrientation = .right // Значение по умолчанию
        }
        
        os_log("CameraManager: Ориентация устройства изменена: %@", log: OSLog.default, type: .debug, String(describing: currentOrientation))
    }
    
    // Этот метод больше не используется, так как мы перешли на прямое вызывание setupDeviceOrientationNotification
    
    deinit {
        // Удаляем наблюдатель при уничтожении объекта
        if let observer = orientationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    /// Настраивает наблюдатель за изменением ориентации устройства
    @MainActor private func setupOrientationObserver() async {
        // Сохраняем текущую ориентацию для безопасного использования в замыканиях
        let currentUIOrientation = UIDevice.current.orientation
        
        // Записываем начальное значение ориентации
        switch currentUIOrientation {
        case .portrait:
            currentOrientation = .right
        case .portraitUpsideDown:
            currentOrientation = .left
        case .landscapeLeft:
            currentOrientation = .up
        case .landscapeRight:
            currentOrientation = .down
        default:
            currentOrientation = .right // Значение по умолчанию
        }
        
        os_log("CameraManager: Инициальная ориентация устройства: %@", log: OSLog.default, type: .debug, String(describing: currentOrientation))
        
        // Создаем наблюдатель за изменением ориентации
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Поскольку это Sendable замыкание, мы не можем обращаться к UIDevice.current.orientation напрямую
            // Вместо этого запускаем Task для выполнения на главном потоке
            Task { @MainActor in
                guard let self = self else { return }
                
                // Теперь мы можем безопасно обратиться к UIDevice.current.orientation
                switch UIDevice.current.orientation {
                case .portrait:
                    self.currentOrientation = .right
                case .portraitUpsideDown:
                    self.currentOrientation = .left
                case .landscapeLeft:
                    self.currentOrientation = .up
                case .landscapeRight:
                    self.currentOrientation = .down
                default:
                    self.currentOrientation = .right // Значение по умолчанию
                }
                
                os_log("CameraManager: Ориентация устройства изменена: %@", log: OSLog.default, type: .debug, String(describing: self.currentOrientation))
            }
        }
        
        // Инициализация происходит выше
    }
    
    /// Переключает разрешение камеры на указанное
    /// - Parameter resolution: Новое разрешение камеры
    func switchResolution(to resolution: CameraResolution) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = resolution.preset
            self.currentResolution = resolution
            self.captureSession.commitConfiguration()
            
            os_log("CameraManager: Разрешение изменено на %@", log: OSLog.default, type: .debug, resolution.description)
        }
    }
    
    /// Добавляет кадр в буфер
    /// - Parameter sampleBuffer: Кадр для буферизации
    private func bufferFrame(_ sampleBuffer: CMSampleBuffer) {
        frameBufferLock.lock()
        defer { frameBufferLock.unlock() }
        
        frameBuffer.append(sampleBuffer)
        if frameBuffer.count > frameBufferSize {
            frameBuffer.removeFirst()
        }
    }
    
    /// Возвращает последний кадр из буфера
    /// - Returns: Буферизованный кадр или nil, если буфер пуст
    func getLatestBufferedFrame() -> CMSampleBuffer? {
        frameBufferLock.lock()
        defer { frameBufferLock.unlock() }
        
        return frameBuffer.last
    }
    
    func setupCamera(completion: @escaping (AVCaptureVideoPreviewLayer) -> Void) {
        os_log("CameraManager: Настройка камеры", log: OSLog.default, type: .debug)
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.captureSession.beginConfiguration()
            
            // Устанавливаем начальное разрешение
            self.captureSession.sessionPreset = self.currentResolution.preset
            
            // Настройка входного устройства
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                os_log("CameraManager: Не удалось найти фронтальную камеру", log: OSLog.default, type: .error)
                return
            }
            self.videoDevice = device
            
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.captureSession.canAddInput(input) {
                    self.captureSession.addInput(input)
                    self.videoInput = input
                }
            } catch {
                os_log("CameraManager: Ошибка настройки входного устройства: %@", log: OSLog.default, type: .error, error.localizedDescription)
                return
            }
            
            // Оптимизация частоты кадров
            do {
                try device.lockForConfiguration()
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30) // 30 fps
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
                device.unlockForConfiguration()
            } catch {
                os_log("CameraManager: Ошибка настройки частоты кадров: %@", log: OSLog.default, type: .error, error.localizedDescription)
            }
            
            // Настройка выхода
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.setSampleBufferDelegate(self, queue: self.processingQueue)
            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
            }
            
            // Настройка ориентации
            if let connection = self.videoOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            }
            
            self.captureSession.commitConfiguration()
            
            // Настройка previewLayer
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
                self.previewLayer.videoGravity = .resizeAspectFill
                os_log("CameraManager: Обновление frame для previewLayer: %@", log: OSLog.default, type: .debug, String(describing: self.previewLayer.frame))
                completion(self.previewLayer)
            }
        }
    }
    
    func startSession() {
        os_log("CameraManager: Запуск сессии", log: OSLog.default, type: .debug)
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
                os_log("CameraManager: Сессия запущена", log: OSLog.default, type: .debug)
            }
        }
    }
    
    func stopSession() {
        os_log("CameraManager: Остановка сессии", log: OSLog.default, type: .debug)
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
                os_log("CameraManager: Сессия остановлена", log: OSLog.default, type: .debug)
            }
        }
    }
    
    func updatePreviewLayerFrame(_ frame: CGRect) {
        // Сохраняем координаты как примитивы для передачи в Sendable замыкание
        let x = frame.origin.x
        let y = frame.origin.y
        let width = frame.size.width
        let height = frame.size.height
        let description = "(x:\(x), y:\(y), width:\(width), height:\(height))"
        
        // Сохраняем указатель на объект как примитивное значение
        let managerAddress = UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque())
        
        // Выполняем на главном потоке
        DispatchQueue.main.async {
            // Восстанавливаем объект из адреса
            let ptr = UnsafeRawPointer(bitPattern: managerAddress)
            guard let ptr = ptr else { return }
            let manager = Unmanaged<CameraManager>.fromOpaque(ptr).takeUnretainedValue()
            
            // Создаем новый прямоугольник из примитивных данных
            let frameRect = CGRect(x: x, y: y, width: width, height: height)
            
            // Обновляем интерфейс
            if let layer = manager.previewLayer {
                layer.frame = frameRect
                os_log("CameraManager: Обновление frame для previewLayer: %@", log: OSLog.default, type: .debug, description)
            } else {
                os_log("CameraManager: previewLayer не настроен", log: OSLog.default, type: .error)
            }
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).value
        
        // Динамически определяем ориентацию устройства
        // В Swift 6 мы не можем обратиться к UIDevice.current.orientation из фонового потока
        // Используем сохраненную ориентацию или дефолтную
        let orientation = currentOrientation ?? .right
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            os_log("CameraManager: Не удалось получить pixelBuffer", log: OSLog.default, type: .error)
            return
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // Буферизуем кадр для возможного использования в будущем
        bufferFrame(sampleBuffer)
        
        // Логируем с меньшей частотой, чтобы не переполнять логи
        if timestamp % 30 == 0 { // Примерно раз в секунду при 30 fps
            os_log("CameraManager: Ориентация устройства: %@, размеры: %dx%d", log: OSLog.default, type: .debug, String(describing: orientation), width, height)
        }
        
        // Передаем кадр делегату
        delegate?.cameraManager(self, didOutput: sampleBuffer, orientation: orientation, timestamp: timestamp)
    }
}
