// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import XCTest

/// Mon compte, signed in as the fictional demo patron.
@MainActor
final class AccountUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testHomeShowsTheCardAndTheCounters() {
        let app = launchApp()
        app.navigationBars["Mon compte"].waitToAppear()
        XCTAssertTrue(app.buttons["Carte d'abonné de Camille Martin, numéro 0012345"].exists)
        XCTAssertTrue(app.element("Prêts").exists)
        XCTAssertTrue(app.element("En retard").exists)
        XCTAssertTrue(app.element("À retirer").exists)
    }

    func testTheCardOpensFullScreenForTheDesk() {
        let app = launchApp()
        app.buttons["Carte d'abonné de Camille Martin, numéro 0012345"].waitToAppear()
        app.buttons["Carte d'abonné de Camille Martin, numéro 0012345"].tap()

        app.element("Code-barres de la carte, numéro 0012345").waitToAppear()
        app.buttons["Fermer"].tap()
        app.navigationBars["Mon compte"].waitToAppear()
    }

    func testLoansAreGroupedAndCanBeRenewed() {
        let app = launchApp()
        app.button(startingWith: "Mes prêts").waitToAppear()
        app.button(startingWith: "Mes prêts").tap()

        app.navigationBars["Mes prêts"].waitToAppear()
        XCTAssertTrue(app.staticTexts["Le Petit Prince"].exists)
        XCTAssertTrue(app.element("EN RETARD").exists || app.element("En retard").exists)

        app.buttons["Prolonger"].firstMatch.tap()
        app.element("Prêt prolongé").waitToAppear()
    }

    func testHoldsListShowsTheOneReadyForPickup() {
        let app = launchApp()
        app.button(startingWith: "Mes réservations").waitToAppear()
        app.button(startingWith: "Mes réservations").tap()

        app.navigationBars["Mes réservations"].waitToAppear()
        XCTAssertTrue(app.staticTexts["Murmuration"].exists)
    }

    func testSignedOutShowsTheSignInForm() {
        let app = launchApp(signedOut: true)
        app.element("Connexion").waitToAppear()
        let signIn = app.buttons["Se connecter"]
        XCTAssertTrue(signIn.exists)
        // Nothing typed yet: the form can't be sent.
        XCTAssertFalse(signIn.isEnabled)
    }
}
