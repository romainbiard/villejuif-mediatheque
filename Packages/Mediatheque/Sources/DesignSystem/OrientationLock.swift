// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

#if canImport(UIKit)
import SwiftUI
import UIKit

/// Orientations the app accepts, returned by the app delegate's
/// `application(_:supportedInterfaceOrientationsFor:)`.
///
/// SwiftUI has no modifier to stop a screen from rotating: a view locks the interface
/// with `interfaceOrientationLocked(to:)`, which narrows this mask while it's displayed.
/// iPadOS ignores the mask for resizable apps, so the lock only applies on iPhone.
@MainActor
public enum OrientationLock {
    private static var lockedMask: UIInterfaceOrientationMask?

    public static var supportedOrientations: UIInterfaceOrientationMask {
        // Unlocked, the same orientations as the Info.plist.
        lockedMask ?? (UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown)
    }

    /// Restricts the interface to `orientations`, rotating it there if needed.
    static func lock(to orientations: UIInterfaceOrientationMask) {
        lockedMask = orientations
        updateViewControllers()
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations))
        }
    }

    static func unlock() {
        lockedMask = nil
        updateViewControllers()
    }

    /// The system rereads the mask from the root and presented view controllers.
    private static func updateViewControllers() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                var controller = window.rootViewController
                while let current = controller {
                    current.setNeedsUpdateOfSupportedInterfaceOrientations()
                    controller = current.presentedViewController
                }
            }
        }
    }
}

extension View {
    /// Restricts the interface to `orientations` while this view is displayed,
    /// rotating it there if needed (iPhone only, see `OrientationLock`).
    public func interfaceOrientationLocked(to orientations: UIInterfaceOrientationMask) -> some View {
        onAppear { OrientationLock.lock(to: orientations) }
            .onDisappear { OrientationLock.unlock() }
    }
}
#endif
