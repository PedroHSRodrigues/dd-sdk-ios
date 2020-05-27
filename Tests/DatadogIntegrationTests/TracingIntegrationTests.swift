/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import HTTPServerMock
import XCTest

class TracingIntegrationTests: IntegrationTests {
    private struct Constants {
        /// Time needed for data to be uploaded to mock server.
        static let dataDeliveryTime: TimeInterval = 30
    }

    func testLaunchTheAppAndSendTraces() throws {
        let testBeginTimeInNanoseconds = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)

        let tracingServerSession = server.obtainUniqueRecordingSession()
        let loggingServerSession = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(
            mockLogsEndpointURL: loggingServerSession.recordingURL,
            mockTracesEndpointURL: tracingServerSession.recordingURL
        )
        app.tapSendTracesForUITests()

        // Wait for delivery
        Thread.sleep(forTimeInterval: Constants.dataDeliveryTime)

        // Assert tracing requests
        let recordedTracingRequests = try tracingServerSession.getRecordedPOSTRequests()
        recordedTracingRequests.forEach { request in
            // Example path here: `/36882784-420B-494F-910D-CBAC5897A309/ui-tests-client-token?batch_time=1589969230153`
            let pathRegexp = #"^(.*)(/ui-tests-client-token\?batch_time=)([0-9]+)$"#
            XCTAssertNotNil(request.path.range(of: pathRegexp, options: .regularExpression, range: nil, locale: nil))
            XCTAssertTrue(request.httpHeaders.contains("Content-Type: text/plain;charset=UTF-8"))
        }

        let testEndTimeInNanoseconds = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)

        // Assert spans
        let spanMatchers = try recordedTracingRequests
            .flatMap { request in try SpanMatcher.fromNewlineSeparatedJSONObjectsData(request.httpBody) }

        XCTAssertEqual(spanMatchers.count, 3)
        XCTAssertEqual(try spanMatchers[0].operationName(), "data downloading")
        XCTAssertEqual(try spanMatchers[1].operationName(), "data presentation")
        XCTAssertEqual(try spanMatchers[2].operationName(), "view appearing")

        // they share the same `trace_id`
        XCTAssertEqual(try spanMatchers[0].traceID(), try spanMatchers[1].traceID())
        XCTAssertEqual(try spanMatchers[0].traceID(), try spanMatchers[2].traceID())

        // "downloading" and "presentation" are childs of "view appearing"
        XCTAssertEqual(try spanMatchers[0].parentSpanID(), try spanMatchers[2].spanID())
        XCTAssertEqual(try spanMatchers[1].parentSpanID(), try spanMatchers[2].spanID())

        XCTAssertNil(try? spanMatchers[0].metrics.isRootSpan())
        XCTAssertNil(try? spanMatchers[1].metrics.isRootSpan())
        XCTAssertEqual(try spanMatchers[2].metrics.isRootSpan(), 1)

        // "downloading" span's tags
        XCTAssertEqual(try spanMatchers[0].meta.custom(keyPath: "meta.data.kind"), "image")
        XCTAssertEqual(try spanMatchers[0].meta.custom(keyPath: "meta.data.url"), "https://example.com/image.png")

        try spanMatchers.forEach { matcher in
            XCTAssertGreaterThan(try matcher.startTime(), testBeginTimeInNanoseconds)
            XCTAssertLessThan(try matcher.startTime(), testEndTimeInNanoseconds)

            XCTAssertEqual(try matcher.serviceName(), "ui-tests-service-name")
            XCTAssertEqual(try matcher.resource(), try matcher.operationName())
            XCTAssertEqual(try matcher.type(), "custom")
            XCTAssertEqual(try matcher.isError(), 0)
            XCTAssertEqual(try matcher.environment(), "integration")

            XCTAssertEqual(try matcher.meta.source(), "ios")
            XCTAssertEqual(try matcher.meta.tracerVersion().split(separator: ".").count, 3)
            XCTAssertEqual(try matcher.meta.applicationVersion(), "1.0")

            XCTAssertTrue(
                SpanMatcher.allowedNetworkReachabilityValues.contains(
                    try matcher.meta.networkReachability()
                )
            )

            try matcher.meta.networkAvailableInterfaces().split(separator: "+").forEach { interface in
                XCTAssertTrue(
                    SpanMatcher.allowedNetworkAvailableInterfacesValues.contains(String(interface))
                )
            }

            XCTAssertTrue(["0", "1"].contains(try matcher.meta.networkConnectionSupportsIPv4()))
            XCTAssertTrue(["0", "1"].contains(try matcher.meta.networkConnectionSupportsIPv6()))
            XCTAssertTrue(["0", "1"].contains(try matcher.meta.networkConnectionIsExpensive()))
            if #available(iOS 13.0, *) {
                XCTAssertTrue(["0", "1"].contains(try matcher.meta.networkConnectionIsConstrained()))
            }

            #if targetEnvironment(simulator)
                // When running on iOS Simulator
                XCTAssertNil(try? matcher.meta.mobileNetworkCarrierName())
                XCTAssertNil(try? matcher.meta.mobileNetworkCarrierISOCountryCode())
                XCTAssertNil(try? matcher.meta.mobileNetworkCarrierRadioTechnology())
                XCTAssertNil(try? matcher.meta.mobileNetworkCarrierAllowsVoIP())
            #else
                // When running on physical device with SIM card registered
                XCTAssertNotNil(try? matcher.meta.mobileNetworkCarrierName())
                XCTAssertNotNil(try? matcher.meta.mobileNetworkCarrierISOCountryCode())
                XCTAssertNotNil(try? matcher.meta.mobileNetworkCarrierRadioTechnology())
                XCTAssertNotNil(try? matcher.meta.mobileNetworkCarrierAllowsVoIP())
            #endif
        }

        // Assert logs requests
        let recordedLoggingRequests = try loggingServerSession.getRecordedPOSTRequests()

        // Assert logs
        let logMatchers = try recordedLoggingRequests
            .flatMap { request in try LogMatcher.fromArrayOfJSONObjectsData(request.httpBody) }

        XCTAssertEqual(logMatchers.count, 1)

        logMatchers[0].assertStatus(equals: "INFO")
        logMatchers[0].assertMessage(equals: "download progress")
        logMatchers[0].assertValue(forKey: "progress", equals: 0.99)

        // Assert logs are linked to "data downloading" span
        logMatchers[0].assertValue(forKey: "dd.trace_id", equals: try spanMatchers[0].traceID().hexadecimalNumberToDecimal)
        logMatchers[0].assertValue(forKey: "dd.span_id", equals: try spanMatchers[0].spanID().hexadecimalNumberToDecimal)
    }
}

private extension String {
    /// Tracing feature uses hexadecimal representation of trace and span IDs, while Logging uses decimals.
    /// This helper converts hexadecimal string to decimal string for comparison.
    var hexadecimalNumberToDecimal: String {
        return "\(UInt64(self, radix: 16)!)"
    }
}
