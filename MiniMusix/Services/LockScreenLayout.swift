import AppKit
import CoreGraphics
import SwiftUI

/// Computes dynamic lock-surface sizing and placement that avoids the login cluster
/// (profile picture, user name, and password field) on any display size.
struct LockScreenLayout: Equatable {
    let contentSize: CGSize
    let scale: CGFloat
    let artworkSize: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let contentSpacing: CGFloat
    let titleFontSize: CGFloat
    let artistFontSize: CGFloat
    let controlSize: CGFloat
    let prominentControlSize: CGFloat
    let cornerRadius: CGFloat
    let showsProgress: Bool
    let panelFrame: CGRect

    /// Region that must stay clear: avatar, display name, and password / sign-in controls.
    static func loginCredentialsZone(in screenFrame: CGRect, context: SecureDisplayContext) -> CGRect {
        let widthRatio: CGFloat = context == .locked ? 0.50 : 0.40
        let heightRatio: CGFloat = context == .locked ? 0.36 : 0.28
        // Login UI is centered vertically with a slight downward bias on tall displays.
        let verticalBias = screenFrame.height * (context == .locked ? -0.03 : -0.02)
        let clusterCenterY = screenFrame.midY + verticalBias

        let width = screenFrame.width * widthRatio
        let height = screenFrame.height * heightRatio

        return CGRect(
            x: screenFrame.midX - width / 2,
            y: clusterCenterY - height / 2,
            width: width,
            height: height
        )
    }

    /// Upper portion of the login cluster: profile image and user name (excludes password field).
    static func profileClusterZone(in screenFrame: CGRect, context: SecureDisplayContext) -> CGRect {
        let credentials = loginCredentialsZone(in: screenFrame, context: context)
        let passwordPortion: CGFloat = context == .locked ? 0.44 : 0.38

        return CGRect(
            x: credentials.minX,
            y: credentials.minY + credentials.height * passwordPortion,
            width: credentials.width,
            height: credentials.height * (1 - passwordPortion)
        )
    }

    /// Legacy name used by placement logging.
    static func passwordSafeZone(in screenFrame: CGRect, context: SecureDisplayContext) -> CGRect {
        loginCredentialsZone(in: screenFrame, context: context)
    }

    static func make(
        screenFrame: CGRect,
        context: SecureDisplayContext,
        showsProgress: Bool
    ) -> LockScreenLayout {
        let reference = CGSize(width: 1440, height: 900)
        let scale = min(
            1.0,
            max(0.68, screenFrame.width / reference.width),
            max(0.68, screenFrame.height / reference.height)
        )

        let sideInset = max(24, screenFrame.width * 0.04)
        let maxBandWidth = max(260, screenFrame.width - sideInset * 2)

        switch context {
        case .locked:
            return makeAboveProfile(
                screenFrame: screenFrame,
                showsProgress: showsProgress,
                baseScale: scale,
                sideInset: sideInset,
                maxBandWidth: maxBandWidth
            )
        case .screenSaver, .inactive:
            return makeBottomBand(
                screenFrame: screenFrame,
                context: context,
                showsProgress: showsProgress,
                baseScale: scale,
                sideInset: sideInset,
                maxBandWidth: maxBandWidth
            )
        }
    }

    // MARK: - Locked placement (above profile)

    private static func makeAboveProfile(
        screenFrame: CGRect,
        showsProgress: Bool,
        baseScale: CGFloat,
        sideInset: CGFloat,
        maxBandWidth: CGFloat
    ) -> LockScreenLayout {
        let credentials = loginCredentialsZone(in: screenFrame, context: .locked)
        let profile = profileClusterZone(in: screenFrame, context: .locked)
        let gapAboveProfile = max(14, screenFrame.height * 0.016)
        let topReserved = max(72, screenFrame.height * 0.13)
        let topLimit = screenFrame.maxY - topReserved
        let credentialsPadding = credentials.insetBy(dx: -10, dy: -10)

        var appliedScale = baseScale
        var contentSize = proposedContentSize(
            scale: appliedScale,
            showsProgress: showsProgress,
            maxWidth: maxBandWidth,
            maxHeight: .greatestFiniteMagnitude
        )

        var panelFrame = panelFrameAboveProfile(
            contentSize: contentSize,
            screenFrame: screenFrame,
            profileZone: profile,
            gap: gapAboveProfile,
            topLimit: topLimit,
            sideInset: sideInset
        )

        var attempts = 0
        while (panelFrame.intersects(credentialsPadding) || panelFrame.maxY > topLimit + 0.5),
              appliedScale > 0.68,
              attempts < 14 {
            appliedScale -= 0.04
            contentSize = proposedContentSize(
                scale: appliedScale,
                showsProgress: showsProgress,
                maxWidth: maxBandWidth,
                maxHeight: availableHeightAboveProfile(
                    profileZone: profile,
                    gap: gapAboveProfile,
                    topLimit: topLimit
                )
            )
            panelFrame = panelFrameAboveProfile(
                contentSize: contentSize,
                screenFrame: screenFrame,
                profileZone: profile,
                gap: gapAboveProfile,
                topLimit: topLimit,
                sideInset: sideInset
            )
            attempts += 1
        }

        if panelFrame.intersects(credentialsPadding) {
            contentSize.height = min(
                contentSize.height,
                availableHeightAboveProfile(profileZone: profile, gap: gapAboveProfile, topLimit: topLimit)
            )
            panelFrame = panelFrameAboveProfile(
                contentSize: contentSize,
                screenFrame: screenFrame,
                profileZone: profile,
                gap: gapAboveProfile,
                topLimit: topLimit,
                sideInset: sideInset
            )
        }

        return layout(
            contentSize: contentSize,
            appliedScale: appliedScale,
            showsProgress: showsProgress,
            panelFrame: panelFrame
        )
    }

    private static func availableHeightAboveProfile(
        profileZone: CGRect,
        gap: CGFloat,
        topLimit: CGFloat
    ) -> CGFloat {
        max(72, topLimit - (profileZone.maxY + gap))
    }

    private static func panelFrameAboveProfile(
        contentSize: CGSize,
        screenFrame: CGRect,
        profileZone: CGRect,
        gap: CGFloat,
        topLimit: CGFloat,
        sideInset: CGFloat
    ) -> CGRect {
        let width = min(contentSize.width, screenFrame.width - sideInset * 2)
        let height = min(contentSize.height, availableHeightAboveProfile(profileZone: profileZone, gap: gap, topLimit: topLimit))
        let originX = screenFrame.midX - width / 2
        var originY = profileZone.maxY + gap

        if originY + height > topLimit {
            originY = topLimit - height
        }

        originY = max(originY, profileZone.maxY + gap)

        return CGRect(x: originX, y: originY, width: width, height: height)
    }

    // MARK: - Screen saver placement (no login cluster)

    private static func makeBottomBand(
        screenFrame: CGRect,
        context: SecureDisplayContext,
        showsProgress: Bool,
        baseScale: CGFloat,
        sideInset: CGFloat,
        maxBandWidth: CGFloat
    ) -> LockScreenLayout {
        let bottomInset = max(36, screenFrame.height * 0.045)
        let credentials = loginCredentialsZone(in: screenFrame, context: context)
        let maxBandHeight = max(72, credentials.minY - screenFrame.minY - bottomInset - 16)

        var appliedScale = baseScale
        var contentSize = proposedContentSize(
            scale: appliedScale,
            showsProgress: showsProgress,
            maxWidth: maxBandWidth,
            maxHeight: maxBandHeight
        )

        var panelFrame = panelFrameBottom(
            contentSize: contentSize,
            screenFrame: screenFrame,
            bottomInset: bottomInset,
            sideInset: sideInset
        )

        let credentialsPadding = credentials.insetBy(dx: -10, dy: -10)
        var attempts = 0
        while panelFrame.intersects(credentialsPadding), appliedScale > 0.68, attempts < 12 {
            appliedScale -= 0.04
            contentSize = proposedContentSize(
                scale: appliedScale,
                showsProgress: showsProgress,
                maxWidth: maxBandWidth,
                maxHeight: maxBandHeight
            )
            panelFrame = panelFrameBottom(
                contentSize: contentSize,
                screenFrame: screenFrame,
                bottomInset: bottomInset,
                sideInset: sideInset
            )
            attempts += 1
        }

        return layout(
            contentSize: contentSize,
            appliedScale: appliedScale,
            showsProgress: showsProgress,
            panelFrame: panelFrame
        )
    }

    private static func panelFrameBottom(
        contentSize: CGSize,
        screenFrame: CGRect,
        bottomInset: CGFloat,
        sideInset: CGFloat
    ) -> CGRect {
        let width = min(contentSize.width, screenFrame.width - sideInset * 2)
        let height = contentSize.height

        return CGRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.minY + bottomInset,
            width: width,
            height: height
        )
    }

    // MARK: - Shared

    private static func proposedContentSize(
        scale: CGFloat,
        showsProgress: Bool,
        maxWidth: CGFloat,
        maxHeight: CGFloat
    ) -> CGSize {
        let baseWidth = 440 * scale
        let baseHeight = (showsProgress ? 108 : 92) * scale

        return CGSize(
            width: min(max(baseWidth, 260), maxWidth),
            height: min(max(baseHeight, 72), maxHeight)
        )
    }

    private static func layout(
        contentSize: CGSize,
        appliedScale: CGFloat,
        showsProgress: Bool,
        panelFrame: CGRect
    ) -> LockScreenLayout {
        LockScreenLayout(
            contentSize: contentSize,
            scale: appliedScale,
            artworkSize: max(48, 76 * appliedScale),
            horizontalPadding: max(14, 18 * appliedScale),
            verticalPadding: max(10, 14 * appliedScale),
            contentSpacing: max(10, 16 * appliedScale),
            titleFontSize: max(14, 17 * appliedScale),
            artistFontSize: max(11, 13 * appliedScale),
            controlSize: max(28, 32 * appliedScale),
            prominentControlSize: max(34, 38 * appliedScale),
            cornerRadius: max(18, 24 * appliedScale),
            showsProgress: showsProgress,
            panelFrame: panelFrame
        )
    }
}

private struct LockScreenLayoutKey: EnvironmentKey {
    static let defaultValue = LockScreenLayout(
        contentSize: CGSize(width: 440, height: 108),
        scale: 1,
        artworkSize: 76,
        horizontalPadding: 18,
        verticalPadding: 14,
        contentSpacing: 16,
        titleFontSize: 17,
        artistFontSize: 13,
        controlSize: 32,
        prominentControlSize: 38,
        cornerRadius: 24,
        showsProgress: true,
        panelFrame: .zero
    )
}

extension EnvironmentValues {
    var lockScreenLayout: LockScreenLayout {
        get { self[LockScreenLayoutKey.self] }
        set { self[LockScreenLayoutKey.self] = newValue }
    }
}