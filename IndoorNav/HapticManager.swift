import UIKit
import CoreHaptics

final class HapticManager {

    static let shared = HapticManager()

    private var engine: CHHapticEngine?
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()

    private init() {
        prepareHaptics()
    }

    private func prepareHaptics() {
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        notification.prepare()
        selection.prepare()

        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            engine = try CHHapticEngine()
            try engine?.start()

            engine?.resetHandler = { [weak self] in
                do {
                    try self?.engine?.start()
                } catch {
                    print("Failed to restart haptic engine: \(error)")
                }
            }
        } catch {
            print("Failed to create haptic engine: \(error)")
        }
    }

    // MARK: - Simple Haptics

    func lightImpact() {
        impactLight.impactOccurred()
    }

    func mediumImpact() {
        impactMedium.impactOccurred()
    }

    func heavyImpact() {
        impactHeavy.impactOccurred()
    }

    func selectionChanged() {
        selection.selectionChanged()
    }

    func success() {
        notification.notificationOccurred(.success)
    }

    func warning() {
        notification.notificationOccurred(.warning)
    }

    func error() {
        notification.notificationOccurred(.error)
    }

    // MARK: - App-Specific Haptics

    func destinationDropped() {
        mediumImpact()
    }

    func waypointDropped() {
        lightImpact()
    }

    func destinationSelected() {
        mediumImpact()
    }

    func mapSaved() {
        success()
    }

    func arrived() {
        playArrivalPattern()
    }

    func relocalized() {
        success()
    }

    func approachingDestination(distance: Float) {
        // Intensity increases as you get closer
        let normalizedDistance = max(0, min(1, distance / 2.0))  // 0-2m range
        let intensity = 1.0 - normalizedDistance

        if intensity > 0.8 {
            heavyImpact()
        } else if intensity > 0.5 {
            mediumImpact()
        }
    }

    // MARK: - Custom Haptic Patterns

    private func playArrivalPattern() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = engine else {
            // Fallback to basic haptics
            success()
            return
        }

        do {
            // Create a celebratory pattern
            var events: [CHHapticEvent] = []

            // Initial strong tap
            events.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ],
                relativeTime: 0
            ))

            // Rising pulses
            for i in 1...3 {
                let time = Double(i) * 0.15
                let intensity = 0.5 + Float(i) * 0.15
                events.append(CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                    ],
                    relativeTime: time
                ))
            }

            // Final strong confirmation
            events.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
                ],
                relativeTime: 0.6
            ))

            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Fallback
            success()
        }
    }

    func playNavigationPulse() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = engine else {
            lightImpact()
            return
        }

        do {
            let events = [
                CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                    ],
                    relativeTime: 0,
                    duration: 0.1
                )
            ]

            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            lightImpact()
        }
    }
}
