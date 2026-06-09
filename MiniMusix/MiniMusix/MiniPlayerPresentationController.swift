import SwiftUI
import Combine

@MainActor
final class MiniPlayerPresentationController: ObservableObject {
    @Published var mode: MiniPlayerPresentationMode = .compact
    @Published var showingLyrics = false
    @Published var showingAmbient = false
    @Published var showingAmbientLyrics = false

    var miniPlayerMode: MiniPlayerMode {
        mode.miniPlayerMode
    }

    func applyPreferredMode(_ preferredMode: MiniPlayerMode) {
        mode = MiniPlayerPresentationMode(miniPlayerMode: preferredMode)
        showingLyrics = false
        showingAmbient = false
        showingAmbientLyrics = false
    }

    func selectCompact() {
        mode = .compact
        showingLyrics = false
    }

    func selectExpanded() {
        mode = .expanded
    }

    func toggleCompactExpanded() {
        mode = mode == .compact ? .expanded : .compact
    }

    func showRegularLyrics() {
        showingLyrics = true
    }

    func hideRegularLyrics() {
        showingLyrics = false
    }

    func showLyricsFocus() {
        mode = .expanded
        showingLyrics = true
    }

    func showAmbient() {
        showingLyrics = false
        showingAmbientLyrics = false
        showingAmbient = true
    }

    func hideAmbient() {
        showingAmbientLyrics = false
        showingAmbient = false
    }

    func toggleAmbientLyrics() {
        showingAmbientLyrics.toggle()
    }

    func windowSize(didCompleteOnboarding: Bool, screenSize: CGSize) -> CGSize {
        guard didCompleteOnboarding else {
            return CGSize(width: OnboardingView.onboardingSize, height: OnboardingView.onboardingSize)
        }

        if showingAmbient {
            return screenSize
        }

        if showingLyrics {
            return mode == .compact ? CGSize(width: 1020, height: 286) : CGSize(width: 1160, height: 286)
        }

        return mode == .compact ? CGSize(width: 606, height: 160) : CGSize(width: 748, height: 220)
    }
}
