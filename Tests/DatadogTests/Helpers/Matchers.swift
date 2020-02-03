import XCTest

struct JSONArrayDataMatcher {
    let data: Data
    init(_ data: Data) { self.data = data }

    func assertItFullyMatches(jsonString: String, file: StaticString = #file, line: UInt = #line) {
        assertThatJSONData(data, representing: NSArray.self, fullyMatches: jsonString, file: file, line: line)
    }

    func assertItMatches<T: Equatable>(value: T, onKeyPath keyPath: String, file: StaticString = #file, line: UInt = #line) {
        assertThatJSONData(data, representing: NSArray.self, matchesValue: value, onKeyPath: keyPath, file: file, line: line)
    }

    func assertItMatchesAnyOf<V: Equatable>(values: [V], onKeyPath keyPath: String, file: StaticString = #file, line: UInt = #line) {
        assertThatJSONData(data, representing: NSArray.self, matchesAnyOfTheValues: values, onKeyPath: keyPath, file: file, line: line)
    }
}

struct JSONObjectDataMatcher {
    let data: Data
    init(_ data: Data) { self.data = data }

    func assertItFullyMatches(jsonString: String, file: StaticString = #file, line: UInt = #line) {
        assertThatJSONData(data, representing: NSDictionary.self, fullyMatches: jsonString, file: file, line: line)
    }

    func assertItMatches<T: Equatable>(value: T, onKeyPath keyPath: String, file: StaticString = #file, line: UInt = #line) {
        assertThatJSONData(data, representing: NSDictionary.self, matchesValue: value, onKeyPath: keyPath, file: file, line: line)
    }
}

/// Convenient extension to use JSON data matchers in `XCTestCase`.
extension XCTestCase {
    func assertThat(jsonArrayData: Data, fullyMatches jsonString: String, file: StaticString = #file, line: UInt = #line) {
        JSONArrayDataMatcher(jsonArrayData)
            .assertItFullyMatches(jsonString: jsonString, file: file, line: line)
    }

    func assertThat<T: Equatable>(jsonArrayData: Data, matchesValue value: T, onKeyPath keyPath: String, file: StaticString = #file, line: UInt = #line) {
        JSONArrayDataMatcher(jsonArrayData)
            .assertItMatches(value: value, onKeyPath: keyPath, file: file, line: line)
    }

    func assertThat<V: Equatable>(
        jsonArrayData: Data,
        matchesAnyOfTheValues values: [V],
        onKeyPath keyPath: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        JSONArrayDataMatcher(jsonArrayData)
            .assertItMatchesAnyOf(values: values, onKeyPath: keyPath, file: file, line: line)
    }

    func assertThat(jsonObjectData: Data, fullyMatches jsonString: String, file: StaticString = #file, line: UInt = #line) {
        JSONObjectDataMatcher(jsonObjectData)
            .assertItFullyMatches(jsonString: jsonString, file: file, line: line)
    }

    func assertThat<T: Equatable>(jsonObjectData: Data, matchesValue value: T, onKeyPath keyPath: String, file: StaticString = #file, line: UInt = #line) {
        JSONObjectDataMatcher(jsonObjectData)
            .assertItMatches(value: value, onKeyPath: keyPath, file: file, line: line)
    }
}

private func assertThatJSONData<T: Equatable>(
    _ jsonData: Data,
    representing rootLevelType: T.Type,
    fullyMatches
    jsonString: String,
    file: StaticString = #file,
    line: UInt = #line
) {
    guard let jsonStringData = jsonString.data(using: .utf8) else {
        XCTFail("Cannot encode data from given json string.", file: file, line: line)
        return
    }

    guard let jsonObjectFromSerializedData = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? T else {
        XCTFail("Cannot decode JSON object from given json data.", file: file, line: line)
        return
    }
    guard let jsonObjectFromJSONString = try? JSONSerialization.jsonObject(with: jsonStringData, options: []) as? T else {
        XCTFail("Cannot encode JSON object from given `jsonString`.", file: file, line: line)
        return
    }

    XCTAssertEqual(jsonObjectFromSerializedData, jsonObjectFromJSONString, file: file, line: line)
}

private func assertThatJSONData<T: NSObject, V: Equatable>(
    _ jsonData: Data,
    representing rootLevelType: T.Type,
    matchesValue value: V,
    onKeyPath keyPath: String,
    file: StaticString = #file,
    line: UInt = #line
) {
    guard let jsonObjectFromSerializedData = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? T else {
        XCTFail("Cannot decode JSON object from given `jsonObjectData`.", file: file, line: line)
        return
    }

    guard let jsonObjectValue = jsonObjectFromSerializedData.value(forKeyPath: keyPath) as? V else {
        XCTFail("Cannot access or cast value of type \(V.self) on key path \(keyPath).", file: file, line: line)
        return
    }

    XCTAssertEqual(jsonObjectValue, value, file: file, line: line)
}

private func assertThatJSONData<T: NSObject, V: Equatable>(
    _ jsonData: Data,
    representing rootLevelType: T.Type,
    matchesAnyOfTheValues values: [V],
    onKeyPath keyPath: String,
    file: StaticString = #file,
    line: UInt = #line
) {
    guard let jsonObjectFromSerializedData = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? T else {
        XCTFail("Cannot decode JSON object from given `jsonObjectData`.", file: file, line: line)
        return
    }

    guard let jsonObjectValue = jsonObjectFromSerializedData.value(forKeyPath: keyPath) as? V else {
        XCTFail("Cannot access or cast value of type \(V.self) on key path \(keyPath).", file: file, line: line)
        return
    }

    var atLeastOneMatch = false
    var missmatches: [String] = []

    values.forEach { value in
        if value == jsonObjectValue {
            atLeastOneMatch = true
        } else {
            missmatches.append("\(value)")
        }
    }

    if !atLeastOneMatch {
        XCTFail(
            "Any of specified values doesn't match \(jsonObjectValue): \(missmatches.joined(separator: "\n"))",
            file: file,
            line: line
        )
    }
}
