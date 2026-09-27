import XCTest
import CoreLocation

/// Covers the GPX pipeline in isolation from the rest of the app (see project.yml for
/// why this target compiles `GPXCodec` directly rather than linking the Locus target).
final class GPXCodecTests: XCTestCase {

    // MARK: - Basic parsing

    func testBasicTrack() throws {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>Basic</name>
            <trkseg>
              <trkpt lat="47.6062" lon="-122.3321"></trkpt>
              <trkpt lat="47.6070" lon="-122.3315"></trkpt>
              <trkpt lat="47.6080" lon="-122.3300"></trkpt>
            </trkseg>
          </trk>
        </gpx>
        """
        let track = try GPXCodec.parseTrack(data: Data(gpx.utf8))
        XCTAssertEqual(track.name, "Basic")
        XCTAssertEqual(track.segments.count, 1)
        XCTAssertEqual(track.coordinates.count, 3)
        XCTAssertEqual(track.coordinates[0].latitude, 47.6062, accuracy: 1e-6)
        XCTAssertEqual(track.coordinates[0].longitude, -122.3321, accuracy: 1e-6)
        XCTAssertNil(track.allPoints[0].elevation)
        XCTAssertNil(track.allPoints[0].time)
    }

    func testMultipleTrackSegments() throws {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>Two segments</name>
            <trkseg>
              <trkpt lat="10.0" lon="20.0"></trkpt>
              <trkpt lat="10.1" lon="20.1"></trkpt>
            </trkseg>
            <trkseg>
              <trkpt lat="11.0" lon="21.0"></trkpt>
              <trkpt lat="11.1" lon="21.1"></trkpt>
              <trkpt lat="11.2" lon="21.2"></trkpt>
            </trkseg>
          </trk>
        </gpx>
        """
        let track = try GPXCodec.parseTrack(data: Data(gpx.utf8))
        XCTAssertEqual(track.segments.count, 2)
        XCTAssertEqual(track.segments[0].count, 2)
        XCTAssertEqual(track.segments[1].count, 3)
        XCTAssertEqual(track.coordinates.count, 5)
    }

    func testTimestamps() throws {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <trkseg>
              <trkpt lat="1.0" lon="2.0">
                <time>2024-03-05T08:15:30Z</time>
              </trkpt>
            </trkseg>
          </trk>
        </gpx>
        """
        let track = try GPXCodec.parseTrack(data: Data(gpx.utf8))
        let point = try XCTUnwrap(track.allPoints.first)
        let time = try XCTUnwrap(point.time)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: time)
        XCTAssertEqual(c.year, 2024)
        XCTAssertEqual(c.month, 3)
        XCTAssertEqual(c.day, 5)
        XCTAssertEqual(c.hour, 8)
        XCTAssertEqual(c.minute, 15)
        XCTAssertEqual(c.second, 30)
    }

    func testWithoutElevation() throws {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <trkseg>
              <trkpt lat="5.0" lon="6.0"></trkpt>
            </trkseg>
          </trk>
        </gpx>
        """
        let track = try GPXCodec.parseTrack(data: Data(gpx.utf8))
        let point = try XCTUnwrap(track.allPoints.first)
        XCTAssertNil(point.elevation)
        XCTAssertEqual(point.coordinate.latitude, 5.0, accuracy: 1e-9)
    }

    func testElevationWhenPresent() throws {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <trkseg>
              <trkpt lat="5.0" lon="6.0"><ele>123.45</ele></trkpt>
            </trkseg>
          </trk>
        </gpx>
        """
        let track = try GPXCodec.parseTrack(data: Data(gpx.utf8))
        let point = try XCTUnwrap(track.allPoints.first)
        XCTAssertEqual(point.elevation ?? -1, 123.45, accuracy: 0.001)
    }

    // MARK: - Regression: the actual historical bug

    func testBoundsAndWaypointsAreNotMistakenForTrackPoints() throws {
        // The previous regex-based parser matched `lat="…" … lon="…"` anywhere in the
        // raw file text, so a <bounds> tag (present in most real-world GPX exports) or a
        // <wpt> got silently misread as an extra, bogus track point — this is the actual
        // bug that made real-world GPX imports look corrupted.
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata>
            <bounds minlat="1.111111" minlon="2.222222" maxlat="9.999999" maxlon="8.888888"/>
          </metadata>
          <wpt lat="50.0" lon="60.0"><name>Some Waypoint</name></wpt>
          <trk>
            <trkseg>
              <trkpt lat="10.0" lon="20.0"></trkpt>
              <trkpt lat="10.1" lon="20.1"></trkpt>
            </trkseg>
          </trk>
        </gpx>
        """
        let track = try GPXCodec.parseTrack(data: Data(gpx.utf8))
        XCTAssertEqual(track.coordinates.count, 2, "bounds/waypoints must not be parsed as track points")
        XCTAssertEqual(track.coordinates[0].latitude, 10.0, accuracy: 1e-9)
        XCTAssertEqual(track.coordinates[0].longitude, 20.0, accuracy: 1e-9)
    }

    // MARK: - Invalid GPX

    func testEmptyDataThrows() {
        XCTAssertThrowsError(try GPXCodec.parseTrack(data: Data()))
    }

    func testMalformedXMLThrows() {
        let malformed = Data("<gpx><trk><trkseg><trkpt lat=\"1.0\" lon=\"2.0\">".utf8) // unterminated
        XCTAssertThrowsError(try GPXCodec.parseTrack(data: malformed)) { error in
            XCTAssertTrue(error is GPXError)
        }
    }

    func testNoTrackPointsThrows() {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata><name>Empty</name></metadata>
        </gpx>
        """
        XCTAssertThrowsError(try GPXCodec.parseTrack(data: Data(gpx.utf8))) { error in
            guard case GPXError.noTrackPoints = error else {
                return XCTFail("expected .noTrackPoints, got \(error)")
            }
        }
    }

    func testOutOfRangeCoordinateThrows() {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><trkseg><trkpt lat="999" lon="20.0"></trkpt></trkseg></trk>
        </gpx>
        """
        XCTAssertThrowsError(try GPXCodec.parseTrack(data: Data(gpx.utf8))) { error in
            guard case GPXError.invalidCoordinate = error else {
                return XCTFail("expected .invalidCoordinate, got \(error)")
            }
        }
    }

    func testDoesNotCrashOnGarbageInput() {
        let garbage = Data([0x00, 0xFF, 0x13, 0x37, 0x01, 0x02] + Array("not xml at all <<<".utf8))
        XCTAssertThrowsError(try GPXCodec.parseTrack(data: garbage))
    }

    // MARK: - Export

    func testExportProducesWellFormedXML() {
        let track = GPXTrack(name: "My Route", segments: [[
            GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 1.0, longitude: 2.0)),
            GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 1.1, longitude: 2.1))
        ]])
        let xml = GPXCodec.export(track)
        XCTAssertTrue(xml.contains("<gpx"))
        XCTAssertTrue(xml.contains("<trkseg>"))
        XCTAssertTrue(xml.contains("<trkpt"))
        let parser = XMLParser(data: Data(xml.utf8))
        XCTAssertTrue(parser.parse(), "export must produce XML that actually parses, not just look like XML")
    }

    func testExportEscapesNameForXMLSafety() {
        let track = GPXTrack(name: "Ride & <fun>", segments: [[
            GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 1))
        ]])
        let xml = GPXCodec.export(track)
        XCTAssertFalse(xml.contains("<fun>"), "unescaped angle brackets would produce invalid XML")
        XCTAssertTrue(xml.contains("&amp;"))
        let parser = XMLParser(data: Data(xml.utf8))
        XCTAssertTrue(parser.parse())
    }

    // MARK: - Round trips

    func testImportThenExportRoundTrip() throws {
        let original = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>Loop</name>
            <trkseg>
              <trkpt lat="37.334600" lon="-122.009000"><ele>15.5</ele><time>2023-11-01T09:00:00Z</time></trkpt>
              <trkpt lat="37.335600" lon="-122.008000"><ele>16.2</ele><time>2023-11-01T09:00:10Z</time></trkpt>
              <trkpt lat="37.336600" lon="-122.007000"><ele>17.0</ele><time>2023-11-01T09:00:20Z</time></trkpt>
            </trkseg>
          </trk>
        </gpx>
        """
        let imported = try GPXCodec.parseTrack(data: Data(original.utf8))
        let exportedXML = GPXCodec.export(imported)
        let reimported = try GPXCodec.parseTrack(data: Data(exportedXML.utf8))

        XCTAssertEqual(reimported.name, imported.name)
        XCTAssertEqual(reimported.coordinates.count, imported.coordinates.count)
        for (a, b) in zip(imported.allPoints, reimported.allPoints) {
            XCTAssertEqual(a.coordinate.latitude, b.coordinate.latitude, accuracy: 1e-6)
            XCTAssertEqual(a.coordinate.longitude, b.coordinate.longitude, accuracy: 1e-6)
            XCTAssertEqual(a.elevation ?? .nan, b.elevation ?? .nan, accuracy: 0.01)
            XCTAssertNotNil(b.time)
        }
    }

    func testExportThenReimportPreservesPrecision() throws {
        let points = [
            GPXTrackPoint(
                coordinate: CLLocationCoordinate2D(latitude: 47.1234567, longitude: -122.7654321),
                elevation: 42.13,
                time: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            GPXTrackPoint(
                coordinate: CLLocationCoordinate2D(latitude: 47.1235000, longitude: -122.7650000),
                elevation: 43.0,
                time: Date(timeIntervalSince1970: 1_700_000_010)
            )
        ]
        let track = GPXTrack(name: "Precision", segments: [points])
        let xml = GPXCodec.export(track)
        let reimported = try GPXCodec.parseTrack(data: Data(xml.utf8))

        XCTAssertEqual(reimported.allPoints.count, points.count)
        for (original, reimportedPoint) in zip(points, reimported.allPoints) {
            XCTAssertEqual(original.coordinate.latitude, reimportedPoint.coordinate.latitude, accuracy: 1e-6)
            XCTAssertEqual(original.coordinate.longitude, reimportedPoint.coordinate.longitude, accuracy: 1e-6)
            XCTAssertEqual(original.elevation ?? .nan, reimportedPoint.elevation ?? .nan, accuracy: 0.01)
            XCTAssertNotNil(reimportedPoint.time)
        }
    }

    // MARK: - Back-compat entry points used by the rest of the app

    func testFlatCoordinateExportImportBackCompat() throws {
        let coords = [
            CLLocationCoordinate2D(latitude: 1, longitude: 1),
            CLLocationCoordinate2D(latitude: 2, longitude: 2)
        ]
        let xml = GPXCodec.export(coords)
        let reimportedCoords = try GPXCodec.parseTrack(data: Data(xml.utf8)).coordinates
        XCTAssertEqual(reimportedCoords.count, coords.count)
    }

    func testParseFromFileURL() throws {
        // Exercises the actual file-URL / security-scoped-resource code path (GPX file
        // selection via Files/`.fileImporter`), not just the in-memory data path the
        // rest of these tests use.
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><trkseg><trkpt lat="3.0" lon="4.0"></trkpt></trkseg></trk>
        </gpx>
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gpx-test-\(UUID().uuidString).gpx")
        try Data(gpx.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let coords = try GPXCodec.parse(url)
        XCTAssertEqual(coords.count, 1)
        XCTAssertEqual(coords[0].latitude, 3.0, accuracy: 1e-9)
    }
}
