import UIKit
import os.log

// MARK: - UI настройка и вспомогательные методы
extension ExerciseExecutionViewController {
    
    /// Настраивает элементы обратной связи
    func setupFeedbackLabels() {
        // Настройка метки обратной связи
        feedbackLabel.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        feedbackLabel.textColor = .white
        feedbackLabel.textAlignment = .center
        feedbackLabel.backgroundColor = UIColor(white: 0, alpha: 0.7)
        feedbackLabel.layer.cornerRadius = 10
        feedbackLabel.clipsToBounds = true
        feedbackLabel.numberOfLines = 0
        feedbackLabel.isHidden = true
        feedbackLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Настройка контейнера для обратной связи по качеству
        qualityFeedbackView.backgroundColor = UIColor(white: 0, alpha: 0.7)
        qualityFeedbackView.layer.cornerRadius = 10
        qualityFeedbackView.clipsToBounds = true
        qualityFeedbackView.isHidden = true
        qualityFeedbackView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(feedbackLabel)
        view.addSubview(qualityFeedbackView)
        
        NSLayoutConstraint.activate([
            feedbackLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            feedbackLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            feedbackLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -120),
            feedbackLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
            
            qualityFeedbackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            qualityFeedbackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            qualityFeedbackView.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -40),
            qualityFeedbackView.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        ])
    }
    
    /// Настраивает метку таймера
    func setupTimerLabel() {
        timerLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 22, weight: .medium)
        timerLabel.textColor = .white
        timerLabel.textAlignment = .center
        timerLabel.backgroundColor = UIColor(white: 0, alpha: 0.7)
        timerLabel.layer.cornerRadius = 8
        timerLabel.clipsToBounds = true
        timerLabel.text = "00:00"
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(timerLabel)
        
        NSLayoutConstraint.activate([
            timerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            timerLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            timerLabel.widthAnchor.constraint(equalToConstant: 80),
            timerLabel.heightAnchor.constraint(equalToConstant: 40)
        ])
    }
    
    /// Настраивает кнопку закрытия
    func setupCloseButton() {
        let closeButton = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        
        navigationItem.leftBarButtonItem = closeButton
    }
    
    /// Запускает таймер тренировки
    func startWorkoutTimer() {
        // Сохраняем локальную копию времени начала, чтобы избежать проблем с доступом из @Sendable замыкания
        guard let startTime = workoutStartTime else { return }
        
        // Обновляем таймер каждую секунду
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self, startTime] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            let duration = Date().timeIntervalSince(startTime)
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            
            // Обновляем UI на главном потоке
            DispatchQueue.main.async {
                self.timerLabel.text = String(format: "%02d:%02d", minutes, seconds)
            }
        }
    }
    
    /// Отображает сообщение о качестве выполнения упражнения
    func showQualityFeedback(_ message: String, isCritical: Bool) {
        let feedbackView = UIView()
        feedbackView.backgroundColor = isCritical ? UIColor.systemRed.withAlphaComponent(0.9) : UIColor.systemGreen.withAlphaComponent(0.9)
        feedbackView.layer.cornerRadius = 10
        feedbackView.translatesAutoresizingMaskIntoConstraints = false
        
        let messageLabel = UILabel()
        messageLabel.text = message
        messageLabel.textColor = .white
        messageLabel.font = .systemFont(ofSize: 18, weight: .medium)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        
        feedbackView.addSubview(messageLabel)
        qualityFeedbackView.subviews.forEach { $0.removeFromSuperview() }
        qualityFeedbackView.addSubview(feedbackView)
        
        NSLayoutConstraint.activate([
            feedbackView.topAnchor.constraint(equalTo: qualityFeedbackView.topAnchor),
            feedbackView.leadingAnchor.constraint(equalTo: qualityFeedbackView.leadingAnchor),
            feedbackView.trailingAnchor.constraint(equalTo: qualityFeedbackView.trailingAnchor),
            feedbackView.bottomAnchor.constraint(equalTo: qualityFeedbackView.bottomAnchor),
            
            messageLabel.topAnchor.constraint(equalTo: feedbackView.topAnchor, constant: 10),
            messageLabel.leadingAnchor.constraint(equalTo: feedbackView.leadingAnchor, constant: 10),
            messageLabel.trailingAnchor.constraint(equalTo: feedbackView.trailingAnchor, constant: -10),
            messageLabel.bottomAnchor.constraint(equalTo: feedbackView.bottomAnchor, constant: -10)
        ])
        
        qualityFeedbackView.isHidden = false
        UIView.animate(withDuration: 0.3, animations: {
            self.qualityFeedbackView.alpha = 1.0
        })
        
        // Скрываем сообщение через 3 секунды
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            UIView.animate(withDuration: 0.3, animations: {
                self.qualityFeedbackView.alpha = 0.0
            }, completion: { _ in
                self.qualityFeedbackView.isHidden = true
                self.qualityFeedbackView.alpha = 1.0
            })
        }
    }
    
    /// Отображает предупреждение о выходе из кадра
    func showFrameWarning(_ message: String) {
        feedbackLabel.text = message
        feedbackLabel.isHidden = false
        
        UIView.animate(withDuration: 0.3, animations: {
            self.feedbackLabel.alpha = 1.0
        })
    }
    
    /// Скрывает предупреждение о выходе из кадра
    func hideFrameWarning() {
        UIView.animate(withDuration: 0.3, animations: {
            self.feedbackLabel.alpha = 0.0
        }, completion: { _ in
            self.feedbackLabel.isHidden = true
            self.feedbackLabel.alpha = 1.0
        })
    }
    
    /// Показывает оповещение о завершении тренировки
    func showCompletionAlert() {
        let alertController = UIAlertController(
            title: "Отличная работа!",
            message: "Вы достигли целевого количества повторений. Хотите завершить тренировку?",
            preferredStyle: .alert
        )
        
        alertController.addAction(UIAlertAction(title: "Продолжить", style: .default))
        alertController.addAction(UIAlertAction(title: "Завершить", style: .destructive) { [weak self] _ in
            self?.finishExercise()
        })
        
        present(alertController, animated: true)
    }
    
    /// Определяет тип упражнения на основе названия
    func getExerciseTypeFromName(_ name: String) -> ExerciseType {
        let lowercaseName = name.lowercased()
        
        if lowercaseName.contains("присед") {
            return .squat
        } else if lowercaseName.contains("отжим") {
            return .pushup
        } else if lowercaseName.contains("выпад") {
            return .lunge
        } else if lowercaseName.contains("планк") {
            return .plank
        } else if lowercaseName.contains("джек") || lowercaseName.contains("прыж") {
            return .jumpingJack
        } else {
            return .custom(name)
        }
    }
    
    /// Рассчитывает оценку качества выполнения упражнения
    func calculateQualityScore() -> Int {
        // В реальном приложении здесь будет сложная логика анализа качества движений
        // Пока возвращаем случайное значение между 75 и 100
        return Int.random(in: 75...100)
    }
    
    /// Рассчитывает среднюю длительность повторения
    func calculateAverageRepDuration() -> TimeInterval {
        // В реальном приложении здесь будет анализ времени на основе данных из PoseProcessor
        return TimeInterval.random(in: 1.5...3.5)
    }
    
    /// Событие при нажатии на кнопку "Закрыть"
    @objc func closeTapped() {
        let alertController = UIAlertController(
            title: "Завершить тренировку?",
            message: "Вы уверены, что хотите завершить тренировку?",
            preferredStyle: .alert
        )
        
        alertController.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alertController.addAction(UIAlertAction(title: "Завершить", style: .destructive) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        
        present(alertController, animated: true)
    }
    
    /// Обновляет счетчик повторений
    func updateRepCount(_ count: Int) {
        repCountLabel.text = "\(count)/\(exercise.targetRepCount)"
        
        // Если достигнута цель, показываем поздравление
        if count >= exercise.targetRepCount {
            showCompletionAlert()
        }
    }
    
    /// Завершает текущее упражнение и сохраняет статистику
    @objc internal func finishExercise() {
        // Останавливаем камеру
        if let camera = cameraManager {
            camera.stopSession()
        }
        
        // Получаем данные о тренировке
        guard let startTime = workoutStartTime else {
            dismiss(animated: true)
            return
        }
        
        let duration = Date().timeIntervalSince(startTime)
        let repetitionCount = Int(repsLabel.text?.components(separatedBy: "/").first ?? "0") ?? 0
        
        // Создаем объект статистики тренировки
        let exerciseType = getExerciseTypeFromName(exercise.name)
        let qualityScore = calculateQualityScore()
        let avgRepDuration = calculateAverageRepDuration()
        
        let workoutSession = WorkoutSession(
            date: Date(),
            exerciseType: exerciseType,
            repetitionCount: repetitionCount,
            duration: duration,
            qualityScore: qualityScore,
            averageRepDuration: avgRepDuration
        )
        
        os_log("ExerciseExecutionViewController: Тренировка завершена - %@ (повторений: %d, время: %.1f сек)", 
               log: OSLog.default, type: .debug, 
               exerciseType.displayName, repetitionCount, duration)
        
        // Передаем данные в WorkoutStatsViewController
        if let tabController = presentingViewController as? UITabBarController, 
           let navController = tabController.viewControllers?[1] as? UINavigationController,
           let statsController = navController.topViewController as? WorkoutStatsViewController {
            statsController.addWorkoutSession(workoutSession)
        }
        
        dismiss(animated: true)
    }
    
    /// Обновляет UI для отображения статуса позиции
    func updatePositionStatus(_ isInPosition: Bool) {
        DispatchQueue.main.async {
            if isInPosition {
                // Показываем, что позиция верна
                self.feedbackLabel.text = "Позиция верна"
                self.feedbackLabel.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.7)
                self.feedbackLabel.isHidden = false
            } else {
                // Показываем, что нужно скорректировать позицию
                // Можно скрыть метку или показать другое сообщение/цвет
                self.feedbackLabel.text = "Скорректируйте позицию"
                self.feedbackLabel.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.7)
                self.feedbackLabel.isHidden = false
            }
            // Убедимся, что метка видима, если она была скрыта
            if self.feedbackLabel.isHidden == false && self.feedbackLabel.alpha == 0.0 {
                 UIView.animate(withDuration: 0.3) {
                     self.feedbackLabel.alpha = 1.0
                 }
            }
        }
    }
}
