// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import XCTest

/// Launches the app on the preview data (App/UITesting.swift), in French, whatever the simulator's language.
@MainActor
func launchApp(signedOut: Bool = false, onboarding: Bool = false, textSize: String? = nil) -> XCUIApplication {
    // A test that turned the device must not leave the next one in landscape.
    XCUIDevice.shared.orientation = .portrait
    let app = XCUIApplication()
    app.launchArguments = ["-uiTesting", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]
    if signedOut { app.launchArguments.append("-uiTestingSignedOut") }
    if onboarding { app.launchArguments.append("-uiTestingOnboarding") }
    if let textSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize] }
    app.launch()
    return app
}

extension XCUIApplication {
    /// Opens a tab ("Compte", "Agenda", "Numérique", "Infos", "Recherche"): from the tab bar, or from the
    /// sidebar that wide windows show instead (iPad, a Pro Max iPhone in landscape).
    func openTab(_ title: String) {
        let tab = tabBars.buttons[title]
        if tab.waitForExistence(timeout: 2) {
            tab.tap()
        } else {
            // Sidebar rows are list cells holding the tab's title.
            cells.containing(NSPredicate(format: "label == %@", title)).firstMatch.tap()
        }
    }

    /// A button whose label starts with this text: menu rows add their badge ("Mes prêts, 1 en retard").
    func button(startingWith text: String) -> XCUIElement {
        buttons.matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    /// Any element showing this text, label or value.
    func element(_ text: String) -> XCUIElement {
        descendants(matching: .any).matching(NSPredicate(format: "label == %@", text)).firstMatch
    }
}

extension XCUIElement {
    /// Waits for the element, with a message naming it when it never shows.
    func waitToAppear(timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitForExistence(timeout: timeout), "« \(label) » introuvable", file: file, line: line)
    }
}
