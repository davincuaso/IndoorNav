import SwiftUI
import ARKit

struct ARViewContainer: UIViewRepresentable {
    let arManager: ARManager
    var showCoaching: Bool = true
    var coachingGoal: ARCoachingOverlayView.Goal = .tracking

    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        let arView = arManager.arView
        arView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(arView)

        NSLayoutConstraint.activate([
            arView.topAnchor.constraint(equalTo: containerView.topAnchor),
            arView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            arView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            arView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ])

        if showCoaching {
            let coachingOverlay = ARCoachingOverlayView()
            coachingOverlay.session = arView.session
            coachingOverlay.goal = coachingGoal
            coachingOverlay.activatesAutomatically = true
            coachingOverlay.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview(coachingOverlay)

            NSLayoutConstraint.activate([
                coachingOverlay.topAnchor.constraint(equalTo: containerView.topAnchor),
                coachingOverlay.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                coachingOverlay.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                coachingOverlay.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
            ])

            context.coordinator.coachingOverlay = coachingOverlay
        }

        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.coachingOverlay?.goal = coachingGoal
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var coachingOverlay: ARCoachingOverlayView?
    }
}
