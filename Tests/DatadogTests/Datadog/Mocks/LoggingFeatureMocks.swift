/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import Datadog

extension LoggingFeature {
    /// Mocks feature instance which performs no writes and no uploads.
    static func mockNoOp() -> LoggingFeature {
        return LoggingFeature(
            storage: .init(writer: NoOpFileWriter(), reader: NoOpFileReader()),
            upload: .init(uploader: NoOpDataUploadWorker()),
            commonDependencies: .mockAny()
        )
    }

    static func mockFullFeature(
        directory: Directory,
        dependencies: FeaturesCommonDependencies = .mockForWorkingFeature()
    ) -> LoggingFeature {
        return LoggingFeature(
            directory: directory,
            commonDependencies: dependencies
        )
    }

    static func mockPartialFeature(
        dataUploadWorkerMock: DataUploadWorkerMock,
        directory: Directory,
        dependencies: FeaturesCommonDependencies = .mockForWorkingFeature(),
        loggingFeature: LoggingFeature? = nil,
        tracingUUIDGenerator: TracingUUIDGenerator = DefaultTracingUUIDGenerator()
    ) -> LoggingFeature {
        let fullFeature: LoggingFeature = .mockFullFeature(
            directory: directory,
            dependencies: dependencies
        )
        let observedStorage = dataUploadWorkerMock.observe(featureStorage: fullFeature.storage)
        let upload = FeatureUpload(uploader: dataUploadWorkerMock)
        return LoggingFeature(
            storage: observedStorage,
            upload: upload,
            commonDependencies: dependencies
        )
    }
}

// MARK: - Log Mocks

extension Log {
    static func mockWith(
        date: Date = .mockAny(),
        status: Log.Status = .mockAny(),
        message: String = .mockAny(),
        serviceName: String = .mockAny(),
        environment: String = .mockAny(),
        loggerName: String = .mockAny(),
        loggerVersion: String = .mockAny(),
        threadName: String = .mockAny(),
        applicationVersion: String = .mockAny(),
        userInfo: UserInfo = .mockAny(),
        networkConnectionInfo: NetworkConnectionInfo = .mockAny(),
        mobileCarrierInfo: CarrierInfo? = .mockAny(),
        attributes: LogAttributes = .mockAny(),
        tags: [String]? = nil
    ) -> Log {
        return Log(
            date: date,
            status: status,
            message: message,
            serviceName: serviceName,
            environment: environment,
            loggerName: loggerName,
            loggerVersion: loggerVersion,
            threadName: threadName,
            applicationVersion: applicationVersion,
            userInfo: userInfo,
            networkConnectionInfo: networkConnectionInfo,
            mobileCarrierInfo: mobileCarrierInfo,
            attributes: attributes,
            tags: tags
        )
    }
}

extension Log.Status {
    static func mockAny() -> Log.Status {
        return .info
    }
}

// MARK: - Component Mocks

extension Logger {
    static func mockWith(
        logOutput: LogOutput = LogOutputMock(),
        dateProvider: DateProvider = SystemDateProvider(),
        identifier: String = .mockAny(),
        rumContextIntegration: LoggingWithRUMContextIntegration? = nil
    ) -> Logger {
        return Logger(
            logOutput: logOutput,
            dateProvider: dateProvider,
            identifier: identifier,
            rumContextIntegration: rumContextIntegration
        )
    }
}

extension LogBuilder {
    static func mockAny() -> LogBuilder {
        return mockWith()
    }

    static func mockWith(
        applicationVersion: String = .mockAny(),
        environment: String = .mockAny(),
        serviceName: String = .mockAny(),
        loggerName: String = .mockAny(),
        userInfoProvider: UserInfoProvider = .mockAny(),
        networkConnectionInfoProvider: NetworkConnectionInfoProviderType = NetworkConnectionInfoProviderMock.mockAny(),
        carrierInfoProvider: CarrierInfoProviderType = CarrierInfoProviderMock.mockAny()
    ) -> LogBuilder {
        return LogBuilder(
            applicationVersion: applicationVersion,
            environment: environment,
            serviceName: serviceName,
            loggerName: loggerName,
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider
        )
    }
}

extension LogAttributes: Equatable {
    static func mockAny() -> LogAttributes {
        return mockWith()
    }

    static func mockWith(
        userAttributes: [String: Encodable] = [:],
        internalAttributes: [String: Encodable]? = nil
    ) -> LogAttributes {
        return LogAttributes(
            userAttributes: userAttributes,
            internalAttributes: internalAttributes
        )
    }

    public static func == (lhs: LogAttributes, rhs: LogAttributes) -> Bool {
        let lhsUserAttributesSorted = lhs.userAttributes.sorted { $0.key < $1.key }
        let rhsUserAttributesSorted = rhs.userAttributes.sorted { $0.key < $1.key }

        let lhsInternalAttributesSorted = lhs.internalAttributes?.sorted { $0.key < $1.key }
        let rhsInternalAttributesSorted = rhs.internalAttributes?.sorted { $0.key < $1.key }

        return String(describing: lhsUserAttributesSorted) == String(describing: rhsUserAttributesSorted)
            && String(describing: lhsInternalAttributesSorted) == String(describing: rhsInternalAttributesSorted)
    }
}

/// `LogOutput` recording received logs.
class LogOutputMock: LogOutput {
    struct RecordedLog: Equatable {
        var level: LogLevel
        var message: String
        var date: Date
        var attributes = LogAttributes(userAttributes: [:], internalAttributes: nil)
        var tags: Set<String> = []
    }

    var recordedLog: RecordedLog? = nil

    func writeLogWith(level: LogLevel, message: String, date: Date, attributes: LogAttributes, tags: Set<String>) {
        recordedLog = RecordedLog(level: level, message: message, date: date, attributes: attributes, tags: tags)
    }
}
