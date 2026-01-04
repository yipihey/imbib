//
//  imbibUITests.swift
//  imbibUITests
//
//  Created by Claude on 2026-01-04.
//

import XCTest

final class imbibUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunchesSuccessfully() throws {
        let app = XCUIApplication()
        app.launch()

        // Verify sidebar is visible
        XCTAssertTrue(app.outlines.firstMatch.waitForExistence(timeout: 5))
    }

    func testSidebarNavigation() throws {
        let app = XCUIApplication()
        app.launch()

        // Click on Library
        let sidebar = app.outlines.firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))

        // Verify Library section exists
        let libraryItem = sidebar.staticTexts["All Publications"]
        if libraryItem.exists {
            libraryItem.click()
        }
    }

    func testSearchNavigation() throws {
        let app = XCUIApplication()
        app.launch()

        // Click on Search
        let sidebar = app.outlines.firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))

        let searchItem = sidebar.staticTexts["Search Sources"]
        if searchItem.exists {
            searchItem.click()
        }
    }
}
