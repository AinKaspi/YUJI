import AVFoundation
import UIKit
import os.log

protocol CameraManagerDelegate: AnyObject {
    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer, orientation: UIImage.Orientation, timestamp: Int64)
}

class CameraManager: NSObject {
    private let captureSession = AVCaptureSession()
    private var videoDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let sessionQueue = DispatchQueue(label: "com.yui.cameraSessionQueue", qos: .userInitiated)
    private let processingQueue = DispatchQueue(label: "com.yui.processingQueue", qos: .userInitiated)
    
    weak var delegate: CameraManagerDelegate?
    
    override init() {
        super.init()
        os_log("CameraManager: Инициализация", log: OSLog.default, type: .debug)
    }
    
    func setupCamera(completion: @escaping (AVCaptureVideoPreviewLayer) -> Void) {
        os_log("CameraManager: Настройка камеры", log: OSLog.default, type: .debug)
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.captureSession.beginConfiguration()
            
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.previewLayer.frame = frame
            os_log("CameraManager: Обновление frame для previewLayer: %@", log: OSLog.default, type: .debug, String(describing: frame))
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).value
        
        // Динамически определяем ориентацию устройства
        let orientation: UIImage.Orientation
        switch UIDevice.current.orientation {
        case .portrait:
            orientation = .right
        case .portraitUpsideDown:
            orientation = .left
        case .landscapeLeft:
            orientation = .up
        case .landscapeRight:
            orientation = .down
        default:
            orientation = .right // Значение по умолчанию
        }
        os_log("CameraManager: Ориентация устройства: %@", log: OSLog.default, type: .debug, String(describing: orientation))
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            os_log("CameraManager: Не удалось получить pixelBuffer", log: OSLog.default, type: .error)
            return
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        os_log("CameraManager: Размеры изображения: %dx%d", log: OSLog.default, type: .debug, width, height)
        
        delegate?.cameraManager(self, didOutput: sampleBuffer, orientation: orientation, timestamp: timestamp)
    }
}
