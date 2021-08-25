/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
#if !DD_COMPILED_FOR_INTEGRATION_TESTS
/// This file is compiled both for Unit and Integration tests.
/// * The Unit Tests target can see `Datadog` by `@testable import Datadog`.
/// * In Integration Tests target we want to compile `Datadog` in "Release" configuration, so testability is not possible.
/// This compiler statement gives both targets the visibility of `RUMDataModels.swift` either by import or direct compilation.
@testable import Datadog
#endif

/// An error thrown by the `RUMSessionMatcher` if it spots an inconsistency in tracked RUM Session, e.g. when
/// two RUM View events have the same `view.id` but different path (which is not allowed by the RUM product constraints).
struct RUMSessionConsistencyException: Error, CustomStringConvertible {
    let description: String
}

internal class RUMSessionMatcher {
    // MARK: - Initialization

    /// Takes the array of `RUMEventMatchers` and groups them by session ID.
    /// For each distinct session ID, the `RUMSessionMatcher` is created.
    /// Each `RUMSessionMatcher` groups its RUM Events by kind and `ViewVisit`.
    class func groupMatchersBySessions(_ matchers: [RUMEventMatcher]) throws -> [RUMSessionMatcher] {
        let eventMatchersBySessionID: [String: [RUMEventMatcher]] = try Dictionary(grouping: matchers) { eventMatcher in
            try eventMatcher.jsonMatcher.value(forKeyPath: "session.id") as String
        }

        return try eventMatchersBySessionID
            .map { try RUMSessionMatcher(sessionEventMatchers: $0.value) }
    }

    // MARK: - View Visits

    /// Single RUM View visit tracked in this RUM Session.
    /// Groups all the `RUMEvents` send during this visit.
    class ViewVisit {
        /// The identifier of all `RUM Views` tracked during this visit.
        let viewID: String

        init(viewID: String) {
            self.viewID = viewID
        }

        /// The `name` of the visited RUM View.
        /// Corresponds to the "VIEW NAME" in RUM Explorer.
        fileprivate(set) var name: String = ""

        /// The `path` of the visited RUM View.
        /// Corresponds to the "VIEW URL" in RUM Explorer.
        fileprivate(set) var path: String = ""

        /// `RUMView` events tracked during this visit.
        fileprivate(set) var viewEvents: [RUMViewEvent] = []

        /// `RUMEventMatchers` corresponding to item in `viewEvents`.
        fileprivate(set) var viewEventMatchers: [RUMEventMatcher] = []

        /// `RUMAction` events tracked during this visit.
        fileprivate(set) var actionEvents: [RUMActionEvent] = []

        /// `RUMResource` events tracked during this visit.
        fileprivate(set) var resourceEvents: [RUMResourceEvent] = []

        /// `RUMError` events tracked during this visit.
        fileprivate(set) var errorEvents: [RUMErrorEvent] = []
    }

    /// An array of view visits tracked during this RUM Session.
    /// Each `ViewVisit` is determined by unique `view.id` and groups all RUM events linked to that `view.id`.
    let viewVisits: [ViewVisit]

    let viewEventMatchers: [RUMEventMatcher]
    let actionEventMatchers: [RUMEventMatcher]
    let resourceEventMatchers: [RUMEventMatcher]
    let errorEventMatchers: [RUMEventMatcher]

    private init(sessionEventMatchers: [RUMEventMatcher]) throws {
        // Sort events so they follow increasing time order
        let sessionEventOrderedByTime = try sessionEventMatchers.sorted { firstEvent, secondEvent in
            let firstEventTime: UInt64 = try firstEvent.jsonMatcher.value(forKeyPath: "date")
            let secondEventTime: UInt64 = try secondEvent.jsonMatcher.value(forKeyPath: "date")
            return firstEventTime < secondEventTime
        }

        let eventsMatchersByType: [String: [RUMEventMatcher]] = try Dictionary(grouping: sessionEventOrderedByTime) { eventMatcher in
            try eventMatcher.jsonMatcher.value(forKeyPath: "type") as String
        }

        // Get RUM Events by kind:

        self.viewEventMatchers = eventsMatchersByType["view"] ?? []
        self.actionEventMatchers = eventsMatchersByType["action"] ?? []
        self.resourceEventMatchers = eventsMatchersByType["resource"] ?? []
        self.errorEventMatchers = eventsMatchersByType["error"] ?? []

        let viewEvents: [RUMViewEvent] = try viewEventMatchers.map { matcher in try matcher.model() }

        let actionEvents: [RUMActionEvent] = try actionEventMatchers
            .map { matcher in try matcher.model() }

        let resourceEvents: [RUMResourceEvent] = try resourceEventMatchers
            .map { matcher in try matcher.model() }

        let errorEvents: [RUMErrorEvent] = try errorEventMatchers
            .map { matcher in try matcher.model() }

        // Validate each group of events individually
        try validate(rumViewEvents: viewEvents)
        try validate(rumActionEvents: actionEvents)
        try validate(rumResourceEvents: resourceEvents)
        try validate(rumErrorEvents: errorEvents)

        // Group RUMView events into ViewVisits:
        let uniqueViewIDs = Set(viewEvents.map { $0.view.id })
        let visits = uniqueViewIDs.map { viewID in ViewVisit(viewID: viewID) }

        var visitsByViewID: [String: ViewVisit] = [:]
        visits.forEach { visit in visitsByViewID[visit.viewID] = visit }

        // Group RUM Events and their matchers by View Visits:
        try zip(viewEvents, viewEventMatchers).forEach { rumEvent, matcher in
            if let visit = visitsByViewID[rumEvent.view.id] {
                visit.viewEvents.append(rumEvent)
                visit.viewEventMatchers.append(matcher)
                if visit.name.isEmpty {
                    visit.name = rumEvent.view.name!
                } else if visit.name != rumEvent.view.name {
                    throw RUMSessionConsistencyException(
                        description: "The RUM View name: \(rumEvent) is different than other RUM View names for the same `view.id`."
                    )
                }
                if visit.path.isEmpty {
                    visit.path = rumEvent.view.url
                } else if visit.path != rumEvent.view.url {
                    throw RUMSessionConsistencyException(
                        description: "The RUM View url: \(rumEvent) is different than other RUM View urls for the same `view.id`."
                    )
                }
            } else {
                throw RUMSessionConsistencyException(
                    description: "Cannot link RUM Event: \(rumEvent) to `RUMSessionMatcher.ViewVisit` by `view.id`."
                )
            }
        }

        try actionEvents.forEach { rumEvent in
            if let visit = visitsByViewID[rumEvent.view.id] {
                visit.actionEvents.append(rumEvent)
            } else {
                throw RUMSessionConsistencyException(
                    description: "Cannot link RUM Event: \(rumEvent) to `RUMSessionMatcher.ViewVisit` by `view.id`."
                )
            }
        }

        try resourceEvents.forEach { rumEvent in
            if let visit = visitsByViewID[rumEvent.view.id] {
                visit.resourceEvents.append(rumEvent)
            } else {
                throw RUMSessionConsistencyException(
                    description: "Cannot link RUM Event: \(rumEvent) to `RUMSessionMatcher.ViewVisit` by `view.id`."
                )
            }
        }

        try errorEvents.forEach { rumEvent in
            if let visit = visitsByViewID[rumEvent.view.id] {
                visit.errorEvents.append(rumEvent)
            } else {
                throw RUMSessionConsistencyException(
                    description: "Cannot link RUM Event: \(rumEvent) to `RUMSessionMatcher.ViewVisit` by `view.id`."
                )
            }
        }

        // Sort visits by time
        let visitsEventOrderedByTime = visits.sorted { firstVisit, secondVisit in
            let firstVisitTime = firstVisit.viewEvents[0].date
            let secondVisitTime = secondVisit.viewEvents[0].date
            return firstVisitTime < secondVisitTime
        }

        // Sort view events in each visit by document version
        visits.forEach { visit in
            visit.viewEvents = visit.viewEvents.sorted { viewUpdate1, viewUpdate2 in
                viewUpdate1.dd.documentVersion < viewUpdate2.dd.documentVersion
            }
        }

        // Validate ViewVisit's view.isActive for each events
        try visits.forEach { visit in
            var viewWasPreviouslyActive = false
            try visit.viewEvents.enumerated().forEach { index, viewEvent in
                let viewIsActive = viewEvent.view.isActive!
                if index == 0 {
                    if !viewIsActive {
                        throw RUMSessionConsistencyException(
                            description: "A `RUMSessionMatcher.ViewVisit` can't have a first event with an inactive `View`."
                        )
                    }
                } else {
                    if !viewWasPreviouslyActive && viewIsActive {
                        throw RUMSessionConsistencyException(
                            description: "A `RUMSessionMatcher.ViewVisit` can't have an event where a `View` is active after the `View` was marked as inactive."
                        )
                    }
                }
                viewWasPreviouslyActive = viewIsActive
            }
        }

        self.viewVisits = visitsEventOrderedByTime
    }
}

private func validate(rumViewEvents: [RUMViewEvent]) throws {
    // All view events must use `session.plan` "lite"
    try rumViewEvents.forEach { viewEvent in
        if viewEvent.dd.session?.plan != .plan1 {
            throw RUMSessionConsistencyException(
                description: "All RUM events must use session plan `1` (RUM Lite). Bad view event: \(viewEvent)"
            )
        }
    }
}

private func validate(rumActionEvents: [RUMActionEvent]) throws {
    // All action events must use `session.plan` "lite"
    try rumActionEvents.forEach { actionEvent in
        if actionEvent.dd.session?.plan != .plan1 {
            throw RUMSessionConsistencyException(
                description: "All RUM events must use session plan `1` (RUM Lite). Bad action event: \(actionEvent)"
            )
        }
    }
}

private func validate(rumResourceEvents: [RUMResourceEvent]) throws {
    // All resource events must have unique ID
    let ids = Set(rumResourceEvents.map { $0.resource.id })
    if ids.count != rumResourceEvents.count {
        throw RUMSessionConsistencyException(
            description: "`resource.id` should be unique - found at least two RUMResourceEvents with the same `resource.id`."
        )
    }

    // All resource events must use `session.plan` "lite"
    try rumResourceEvents.forEach { resourceEvent in
        if resourceEvent.dd.session?.plan != .plan1 {
            throw RUMSessionConsistencyException(
                description: "All RUM events must use session plan `1` (RUM Lite). Bad resource event: \(resourceEvent)"
            )
        }
    }
}

private func validate(rumErrorEvents: [RUMErrorEvent]) throws {
    // All error events must use `session.plan` "lite"
    try rumErrorEvents.forEach { errorEvent in
        if errorEvent.dd.session?.plan != .plan1 {
            throw RUMSessionConsistencyException(
                description: "All RUM events must use session plan `1` (RUM Lite). Bad error event: \(errorEvent)"
            )
        }
    }
}
