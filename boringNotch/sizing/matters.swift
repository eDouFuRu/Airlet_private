//
//  sizeMatters.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 05/08/24.
//

import Defaults
import Foundation
import SwiftUI

let downloadSneakSize: CGSize = .init(width: 65, height: 1)
let batterySneakSize: CGSize = .init(width: 160, height: 1)

let shadowPadding: CGFloat = 20
let openNotchSize: CGSize = .init(width: 640, height: 190)
/// Wide enough for the island, its shadow bleed, and a control floating clear of either
/// edge. The window never resizes, so anything drawn past this is simply clipped away.
let windowSize: CGSize = .init(
    width: openNotchSize.width + 2 * (shadowPadding + NotchAccessoryControl.requiredSideMargin),
    height: SystemHUDLayout.carrierHeight)
let cornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = (opened: (top: 19, bottom: 24), closed: (top: 6, bottom: 14))

enum MusicPlayerImageSizes {
    static let cornerRadiusInset: (opened: CGFloat, closed: CGFloat) = (opened: 13.0, closed: 4.0)
    static let size = (opened: CGSize(width: 90, height: 90), closed: CGSize(width: 20, height: 20))
}

@MainActor func getScreenFrame(_ screenUUID: String? = nil) -> CGRect? {
    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }
    
    if let screen = selectedScreen {
        return screen.frame
    }
    
    return nil
}

@MainActor private var menuBarHeightCache = IslandMenuBarHeightCache()

/// visibleFrame reports no top reservation while the menu bar is automatically hidden.
/// Keep the last usable height for this screen instead of collapsing the wake-up target.
@MainActor private func menuBarHeight(for screen: NSScreen) -> CGFloat {
    let key = screen.displayUUID ?? screen.localizedName
    let measured = screen.frame.maxY - screen.visibleFrame.maxY
    return menuBarHeightCache.height(for: key, measured: measured,
                                    systemHeight: NSStatusBar.system.thickness)
}

@MainActor func getIslandDisplayProfile(screen: NSScreen?) -> IslandDisplayProfile {
    var notchHeight: CGFloat = Defaults[.notchHeight]
    var notchWidth: CGFloat = 120
    var menuHeight: CGFloat = 24
    if let screen {
        menuHeight = menuBarHeight(for: screen)
        // Calculate and set the exact width of the notch
        if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
           let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width
        {
            let width = screen.frame.width - topLeftNotchpadding - topRightNotchpadding
            if width > 0 { notchWidth = width }
        }

        // Check if the Mac has a notch
        if screen.safeAreaInsets.top > 0 {
            // This is a display WITH a notch - use notch height settings
            notchHeight = Defaults[.notchHeight]
            if Defaults[.notchHeightMode] == .matchRealNotchSize {
                notchHeight = screen.safeAreaInsets.top
            } else if Defaults[.notchHeightMode] == .matchMenuBar {
                notchHeight = menuHeight
            }
        }
    }
    return IslandDisplayProfile(screenWidth: screen?.frame.width ?? 1440,
                                safeTop: screen?.safeAreaInsets.top ?? 0,
                                cameraWidth: notchWidth, nativeClosedHeight: notchHeight,
                                menuBarHeight: menuHeight)
}

@MainActor func getIslandDisplayProfile(screenUUID: String? = nil) -> IslandDisplayProfile {
    let screen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) } ?? NSScreen.main
    return getIslandDisplayProfile(screen: screen)
}

@MainActor func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {
    getIslandDisplayProfile(screenUUID: screenUUID).compactSize
}
