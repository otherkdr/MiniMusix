import SwiftUI

enum AppMotion {
    static func primary(reduceMotion: Bool = false) -> Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.50, dampingFraction: 0.92, blendDuration: 0.10)
    }

    static func panel(reduceMotion: Bool = false) -> Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.44, dampingFraction: 0.90, blendDuration: 0.08)
    }

    static func control(reduceMotion: Bool = false) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.26, dampingFraction: 0.88, blendDuration: 0.04)
    }

    static func content(reduceMotion: Bool = false) -> Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .easeInOut(duration: 0.22)
    }

    static func progress(reduceMotion: Bool = false) -> Animation {
        reduceMotion ? .linear(duration: 0.01) : .linear(duration: 0.20)
    }

    static func lyricScroll(reduceMotion: Bool = false) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.94, blendDuration: 0.08)
    }

    static func hoverScale(_ isHovered: Bool, amount: CGFloat = 1.035) -> CGFloat {
        isHovered ? amount : 1
    }

    static var subtleInsertion: AnyTransition {
        .opacity
            .combined(with: .scale(scale: 0.985, anchor: .center))
            .combined(with: .offset(y: 6))
    }

    static var panelTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.97, anchor: .bottom))
                .combined(with: .offset(y: 10)),
            removal: .opacity
                .combined(with: .scale(scale: 0.985, anchor: .bottom))
                .combined(with: .offset(y: 4))
        )
    }

    static var toastTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.96, anchor: .bottom))
                .combined(with: .offset(y: 8)),
            removal: .opacity
                .combined(with: .scale(scale: 0.98, anchor: .bottom))
                .combined(with: .offset(y: 4))
        )
    }
}
