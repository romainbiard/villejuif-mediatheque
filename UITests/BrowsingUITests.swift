// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import XCTest

/// The public tabs and the hold flow, on the preview data.
@MainActor
final class BrowsingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testEveryTabOpens() {
        let app = launchApp()
        app.navigationBars["Mon compte"].waitToAppear()

        app.openTab("Agenda")
        app.navigationBars["Agenda"].waitToAppear()

        app.openTab("Numérique")
        app.navigationBars["Numérique"].waitToAppear()

        app.openTab("Infos")
        app.navigationBars["Infos pratiques"].waitToAppear()
        XCTAssertTrue(app.staticTexts["Médiathèque Elsa-Triolet"].exists)

        app.openTab("Recherche")
        app.searchFields.firstMatch.waitToAppear()
    }

    func testSearchThenPlaceAHold() {
        let app = launchApp()
        app.openTab("Recherche")
        let field = app.searchFields.firstMatch
        field.waitToAppear()
        field.tap()
        field.typeText("harry potter\n")

        let record = app.staticTexts["Harry Potter à l'école des sorciers"]
        record.waitToAppear()
        record.tap()

        app.buttons["Réserver"].waitToAppear()
        app.buttons["Réserver"].tap()

        app.element("Où voulez-vous le retirer ?").waitToAppear()
        app.buttons["Confirmer la réservation"].tap()
        app.element("Réservation enregistrée").waitToAppear()
    }

    func testAgendaFiltersOpenAndClose() {
        let app = launchApp()
        app.openTab("Agenda")
        app.buttons["Filtres"].waitToAppear()
        app.buttons["Filtres"].tap()

        app.navigationBars["Filtres"].waitToAppear()
        app.swipeDown(velocity: .fast)
        app.navigationBars["Agenda"].waitToAppear()
    }

    /// Every orientation is allowed (WCAG 1.3.4): in landscape, every tab still opens its screen.
    func testEveryTabOpensInLandscape() {
        let app = launchApp()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        app.element("Mon compte").waitToAppear()

        app.openTab("Agenda")
        app.element("Agenda").waitToAppear()
        app.openTab("Numérique")
        app.element("Arte VOD et Univers Ciné").waitToAppear()
        app.openTab("Infos")
        app.staticTexts["Médiathèque Elsa-Triolet"].waitToAppear()
        app.openTab("Recherche")
        // With the sidebar, the search field sits in the results column instead of the navigation bar.
        XCTAssertTrue(
            app.searchFields.firstMatch.waitForExistence(timeout: 3) || app.textFields.firstMatch.waitForExistence(timeout: 3),
            "Champ de recherche introuvable"
        )
    }

    /// Largest accessibility text size: the account home still shows its essentials.
    func testAccountAtTheLargestTextSize() {
        let app = launchApp(textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        app.navigationBars["Mon compte"].waitToAppear()
        XCTAssertTrue(app.buttons["Carte d'abonné de Camille Martin, numéro 0012345"].exists)
        app.swipeUp()
        app.button(startingWith: "Mes prêts").waitToAppear()
    }
}
