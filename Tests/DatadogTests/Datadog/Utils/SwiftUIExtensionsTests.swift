/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

#if canImport(SwiftUI)

import XCTest
import SwiftUI
@testable import Datadog

@available(iOS 13, *)
class CustomHostingController: UIHostingController<AnyView> {}

@available(iOS 13, *)
final class TestView: View {
    var body = EmptyView()
}

class SwiftUIExtensionsTests: XCTestCase {
    func testSwiftUIViewTypeDescription() {
        guard #available(iOS 13, *) else {
            return
        }

        let view = TestView().cornerRadius(8)
        XCTAssertEqual(view.typeDescription, "ModifiedContent<TestView, _ClipEffect<RoundedRectangle>>")
    }

    func testBundleIsSwiftUI() {
        guard #available(iOS 13, *) else {
            return
        }

        // Given
        let someSwiftUITypes: [AnyClass] = [
            UIHostingController<AnyView>.self // The only class in SwiftUI
        ]

        let someNonSwiftUITypes: [AnyClass] = [
            TestView.self,
            UIViewController.self,
            OperationQueue.self,
        ]

        // Then
        someSwiftUITypes.forEach { XCTAssertTrue(Bundle(for: $0).isSwiftUI) }
        someNonSwiftUITypes.forEach { XCTAssertFalse(Bundle(for: $0).isSwiftUI) }
    }
}
#endif
