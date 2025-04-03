import Foundation
import AVFoundation
import CoreImage
import os.log

/// Класс для улучшения качества изображений в различных условиях
class ImageEnhancer {
    
    /// Типы улучшений, которые можно применить
    enum EnhancementType {
        case none                 // без улучшений
        case lowLight             // улучшение при низкой освещенности
        case highContrast         // повышение контрастности 
        case noiseReduction       // уменьшение шума
        case sharpening           // повышение резкости
        case adaptiveEnhancement  // адаптивное улучшение на основе анализа изображения
    }
    
    // Контекст для обработки изображений
    private let ciContext = CIContext()
    
    // Фильтры для улучшения
    private var currentFilters: [CIFilter] = []
    
    // Активный тип улучшения
    private var activeEnhancement: EnhancementType = .none
    
    // Коэффициенты для адаптивного улучшения
    private var brightness: Float = 0.0
    private var contrast: Float = 1.0
    private var saturation: Float = 1.0
    
    // Счетчик кадров для периодического анализа
    private var frameCounter = 0
    
    /// Инициализирует улучшитель изображений с определенным типом улучшения
    /// - Parameter enhancementType: Тип улучшения для применения
    init(enhancementType: EnhancementType = .adaptiveEnhancement) {
        setEnhancementType(enhancementType)
        os_log("ImageEnhancer: Инициализирован с типом улучшения %@", log: OSLog.default, type: .debug, String(describing: enhancementType))
    }
    
    /// Устанавливает тип улучшения
    /// - Parameter type: Тип улучшения для применения
    func setEnhancementType(_ type: EnhancementType) {
        self.activeEnhancement = type
        setupFilters(for: type)
        os_log("ImageEnhancer: Установлен тип улучшения %@", log: OSLog.default, type: .debug, String(describing: type))
    }
    
    /// Настраивает фильтры для определенного типа улучшения
    /// - Parameter type: Тип улучшения
    private func setupFilters(for type: EnhancementType) {
        currentFilters.removeAll()
        
        switch type {
        case .none:
            break
            
        case .lowLight:
            // Авто-улучшение яркости и контраста
            if let autoAdjustFilter = CIFilter(name: "CIAutoEnhance") {
                currentFilters.append(autoAdjustFilter)
            }
            
            // Добавляем фильтр для повышения яркости
            if let brightnessFilter = CIFilter(name: "CIColorControls") {
                brightnessFilter.setValue(0.3, forKey: kCIInputBrightnessKey)
                currentFilters.append(brightnessFilter)
            }
            
        case .highContrast:
            // Фильтр для повышения контраста
            if let contrastFilter = CIFilter(name: "CIColorControls") {
                contrastFilter.setValue(1.5, forKey: kCIInputContrastKey)
                currentFilters.append(contrastFilter)
            }
            
        case .noiseReduction:
            // Фильтр для уменьшения шума
            if let noiseReductionFilter = CIFilter(name: "CIGaussianBlur") {
                // Используем Gaussian Blur с низким значением для уменьшения шума
                noiseReductionFilter.setValue(2.0, forKey: kCIInputRadiusKey)
                currentFilters.append(noiseReductionFilter)
            }
            
            // Добавляем фильтр для повышения резкости после размытия
            if let sharpenFilter = CIFilter(name: "CISharpenLuminance") {
                sharpenFilter.setValue(0.4, forKey: kCIInputSharpnessKey)
                currentFilters.append(sharpenFilter)
            }
            
        case .sharpening:
            // Фильтр для повышения резкости
            if let sharpenFilter = CIFilter(name: "CISharpenLuminance") {
                sharpenFilter.setValue(0.5, forKey: kCIInputSharpnessKey)
                currentFilters.append(sharpenFilter)
            }
            
        case .adaptiveEnhancement:
            // Будем динамически настраивать фильтры на основе анализа
            if let colorControlsFilter = CIFilter(name: "CIColorControls") {
                colorControlsFilter.setValue(brightness, forKey: kCIInputBrightnessKey)
                colorControlsFilter.setValue(contrast, forKey: kCIInputContrastKey)
                colorControlsFilter.setValue(saturation, forKey: kCIInputSaturationKey)
                currentFilters.append(colorControlsFilter)
            }
        }
    }
    
    /// Улучшает изображение из буфера образца
    /// - Parameters:
    ///   - sampleBuffer: Исходный буфер изображения
    ///   - forceAnalysis: Принудительный анализ изображения
    /// - Returns: Улучшенный буфер изображения или исходный, если улучшение не удалось
    func enhanceImage(_ sampleBuffer: CMSampleBuffer, forceAnalysis: Bool = false) -> CMSampleBuffer {
        // Если улучшение не требуется, возвращаем исходное изображение
        if activeEnhancement == .none {
            return sampleBuffer
        }
        
        // Получаем pixelBuffer из sampleBuffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            os_log("ImageEnhancer: Не удалось получить pixelBuffer из sampleBuffer", log: OSLog.default, type: .error)
            return sampleBuffer
        }
        
        // Создаем CIImage из pixelBuffer
        let inputImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Счетчик кадров для периодического анализа
        frameCounter += 1
        
        // Анализируем изображение каждые 30 кадров или при принудительном анализе
        if (frameCounter % 30 == 0 || forceAnalysis) && activeEnhancement == .adaptiveEnhancement {
            analyzeAndAdjust(inputImage)
        }
        
        // Применяем фильтры
        var outputImage = inputImage
        for filter in currentFilters {
            filter.setValue(outputImage, forKey: kCIInputImageKey)
            if let filteredImage = filter.outputImage {
                outputImage = filteredImage
            }
        }
        
        // Создаем новый pixelBuffer для обработанного изображения
        let outputPixelBuffer = pixelBuffer
        CVPixelBufferLockBaseAddress(outputPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        // Рендерим обработанное изображение в исходный pixelBuffer
        ciContext.render(outputImage, to: outputPixelBuffer)
        CVPixelBufferUnlockBaseAddress(outputPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        // Возвращаем исходный sampleBuffer (внутренний pixelBuffer был изменен)
        return sampleBuffer
    }
    
    /// Анализирует изображение и настраивает параметры фильтров
    /// - Parameter image: Изображение для анализа
    private func analyzeAndAdjust(_ image: CIImage) {
        // Анализируем яркость изображения
        let imageProperties = analyzeImageProperties(image)
        
        // Адаптивно настраиваем параметры
        if imageProperties.averageBrightness < 0.3 {
            // Низкая освещенность - увеличиваем яркость и контраст
            brightness = min(brightness + 0.05, 0.4)
            contrast = min(contrast + 0.05, 1.5)
            saturation = max(saturation - 0.05, 0.8)
            
            os_log("ImageEnhancer: Низкая освещенность (%.2f), увеличиваем яркость до %.2f", 
                  log: OSLog.default, type: .debug, 
                  imageProperties.averageBrightness, brightness)
        } else if imageProperties.averageBrightness > 0.7 {
            // Высокая яркость - нормализуем параметры
            brightness = max(brightness - 0.05, 0.0)
            contrast = max(contrast - 0.05, 1.0)
            saturation = min(saturation + 0.05, 1.2)
            
            os_log("ImageEnhancer: Хорошая освещенность (%.2f), нормализуем яркость до %.2f", 
                  log: OSLog.default, type: .debug, 
                  imageProperties.averageBrightness, brightness)
        }
        
        // Обновляем фильтры с новыми значениями
        for filter in currentFilters {
            if filter.name == "CIColorControls" {
                filter.setValue(brightness, forKey: kCIInputBrightnessKey)
                filter.setValue(contrast, forKey: kCIInputContrastKey)
                filter.setValue(saturation, forKey: kCIInputSaturationKey)
            }
        }
    }
    
    /// Анализирует свойства изображения
    /// - Parameter image: Изображение для анализа
    /// - Returns: Свойства изображения (яркость, контраст и т.д.)
    private func analyzeImageProperties(_ image: CIImage) -> (averageBrightness: CGFloat, contrast: CGFloat) {
        // Создаем уменьшенную версию для анализа (для ускорения)
        let extent = image.extent
        let scale = min(100 / extent.width, 100 / extent.height)
        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        // Анализируем яркость с помощью CIAreaAverage
        let extentVector = CIVector(x: scaledImage.extent.origin.x, 
                                   y: scaledImage.extent.origin.y, 
                                   z: scaledImage.extent.size.width, 
                                   w: scaledImage.extent.size.height)
        
        guard let averageFilter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: scaledImage,
            kCIInputExtentKey: extentVector
        ]) else {
            return (0.5, 1.0) // Возвращаем значения по умолчанию
        }
        
        guard let averageImage = averageFilter.outputImage else {
            return (0.5, 1.0)
        }
        
        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(averageImage, 
                         toBitmap: &bitmap, 
                         rowBytes: 4, 
                         bounds: CGRect(x: 0, y: 0, width: 1, height: 1), 
                         format: CIFormat.RGBA8, 
                         colorSpace: CGColorSpaceCreateDeviceRGB())
        
        // Вычисляем среднюю яркость (по формуле ITU-R BT.709)
        let averageBrightness = (CGFloat(bitmap[0]) * 0.2126 + 
                                CGFloat(bitmap[1]) * 0.7152 + 
                                CGFloat(bitmap[2]) * 0.0722) / 255.0
        
        // Простая оценка контраста (можно улучшить)
        let contrast: CGFloat = 1.0
        
        return (averageBrightness, contrast)
    }
}
