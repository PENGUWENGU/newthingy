import XCTest

final class SpeedInputTests: XCTestCase {
    func testRejectsEmptyOrWhitespaceInput() {
        XCTAssertNil(SpeedInput.parse(""))
        XCTAssertNil(SpeedInput.parse("   "))
    }

    func testRejectsMalformedNumbers() {
        XCTAssertNil(SpeedInput.parse("fast"))
        XCTAssertNil(SpeedInput.parse("12mph"))
        XCTAssertNil(SpeedInput.parse("abc"))
        XCTAssertNil(SpeedInput.parse("1.2.3"))
    }

    func testRejectsNaNAndInfinity() {
        XCTAssertNil(SpeedInput.parse("nan"))
        XCTAssertNil(SpeedInput.parse("inf"))
        XCTAssertNil(SpeedInput.parse("+infinity"))
        XCTAssertNil(SpeedInput.parse("-infinity"))
    }

    func testRejectsZeroAndNegativeValues() {
        XCTAssertNil(SpeedInput.parse("0"))
        XCTAssertNil(SpeedInput.parse("-5"))
        XCTAssertNil(SpeedInput.parse("-0.001"))
    }

    func testAcceptsPlainDecimalValues() {
        XCTAssertEqual(SpeedInput.parse("3.5"), 3.5)
        XCTAssertEqual(SpeedInput.parse("10"), 10)
    }

    func testAcceptsCommaAsDecimalSeparator() {
        XCTAssertEqual(SpeedInput.parse("3,5"), 3.5)
    }

    func testClampsExtremeButValidValuesRatherThanRejecting() {
        XCTAssertEqual(SpeedInput.parse("0.0000001"), SpeedInput.minimumMetersPerSecond)
        XCTAssertEqual(SpeedInput.parse("999999999"), SpeedInput.maximumMetersPerSecond)
    }

    func testAllowsSpeedsOutsideTheFourPresets() {
        // The whole point of the feature: not limited to walk/run/cycle/drive.
        XCTAssertEqual(SpeedInput.parse("42.7"), 42.7)
    }
}

final class TravelModeTests: XCTestCase {
    func testAllPresetsHaveAPositiveBaseSpeed() {
        for mode in TravelMode.allCases {
            XCTAssertGreaterThan(mode.baseSpeed, 0)
        }
    }
}

final class SpeedPreferenceTests: XCTestCase {
    override func tearDown() {
        SpeedPreference.setCustomSpeed(nil)
        super.tearDown()
    }

    func testStoresAndClearsACustomSpeed() {
        SpeedPreference.setCustomSpeed(7.5)
        XCTAssertEqual(SpeedPreference.storedValue, 7.5)
        SpeedPreference.setCustomSpeed(nil)
        XCTAssertNil(SpeedPreference.storedValue)
    }

    func testDoesNotPersistAnInvalidValue() {
        SpeedPreference.setCustomSpeed(-3)
        XCTAssertNil(SpeedPreference.storedValue)
    }
}
