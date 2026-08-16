//
//  bilibili_tvUITestsLaunchTests.swift
//  bilibili_tvUITests
//
//  Created by debiancc on 2026/4/18.
//

import XCTest

final class bilibili_tvUITestsLaunchTests: XCTestCase {
    // XCTest 要求 override class 重写,不能用 static
    // swiftlint:disable:next static_over_final_class
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }
}
