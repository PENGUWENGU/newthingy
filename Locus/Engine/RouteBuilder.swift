import CoreLocation
import Foundation
import MapKit

enum RouteBuilder {
    static func roadRoute(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        mode: TravelMode
    ) async throws -> [CLLocationCoordinate2D] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = mode.mkTransportType
        request.requestsAlternateRoutes = false

        let directions = MKDirections(request: request)
        let response = try await directions.calculate()
        guard let route = response.routes.first else {
            throw NSError(domain: "Locus", code: 1, userInfo: [NSLocalizedDescriptionKey: "No route found"])
        }
        return sample(polyline: route.polyline, every: 12)
    }

    static func sample(polyline: MKPolyline, every meters: CLLocationDistance) -> [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: polyline.pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        return sample(coordinates: coords, every: meters)
    }

    static func sample(coordinates: [CLLocationCoordinate2D], every meters: CLLocationDistance) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 1 else { return coordinates }
        var sampled = [coordinates[0]]
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            let dist = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            let steps = max(1, Int(ceil(dist / meters)))
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                sampled.append(CLLocationCoordinate2D(
                    latitude: a.latitude + (b.latitude - a.latitude) * t,
                    longitude: a.longitude + (b.longitude - a.longitude) * t
                ))
            }
        }
        return sampled
    }
}

// MARK: - GPX data model
//
// `GPXTrack`/`GPXTrackPoint` are the app's GPX-level representation: a name plus one or
// more segments (`<trkseg>`) of points, each optionally carrying elevation/time. Every
// existing call site only ever needs the flat path, so `GPXTrack.coordinates` gives back
// exactly the `[CLLocationCoordinate2D]` they already worked with — nothing about the
// map/joystick/route-playback code needs to know this richer type exists.

struct GPXTrackPoint: Equatable {
    var coordinate: CLLocationCoordinate2D
    var elevation: Double?
    var time: Date?

    init(coordinate: CLLocationCoordinate2D, elevation: Double? = nil, time: Date? = nil) {
        self.coordinate = coordinate
        self.elevation = elevation
        self.time = time
    }

    static func == (lhs: GPXTrackPoint, rhs: GPXTrackPoint) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.elevation == rhs.elevation
            && lhs.time == rhs.time
    }
}

struct GPXTrack: Equatable {
    var name: String?
    var segments: [[GPXTrackPoint]]

    /// Flattened points across every segment, in order — the representation the rest of
    /// the app already uses for the map polyline and joystick/route playback.
    var coordinates: [CLLocationCoordinate2D] {
        segments.flatMap { $0.map(\.coordinate) }
    }

    var allPoints: [GPXTrackPoint] {
        segments.flatMap { $0 }
    }

    var isEmpty: Bool {
        segments.allSatisfy { $0.isEmpty }
    }
}

enum GPXError: LocalizedError, Equatable {
    case unreadableFile(String)
    case malformedXML(String)
    case noTrackPoints
    case invalidCoordinate(lat: String, lon: String)

    var errorDescription: String? {
        switch self {
        case .unreadableFile(let reason):
            return "Couldn't read the GPX file: \(reason)"
        case .malformedXML(let reason):
            return "This isn't a valid GPX/XML file: \(reason)"
        case .noTrackPoints:
            return "This GPX file doesn't contain any track points."
        case .invalidCoordinate(let lat, let lon):
            return "Found an out-of-range or unreadable coordinate (lat \(lat), lon \(lon))."
        }
    }
}

enum GPXCodec {
    /// Rich import: preserves segments, elevation, and timestamps when present.
    /// Handles security-scoped URLs from `.fileImporter` / `onOpenURL` the same way the
    /// previous implementation did.
    static func parseTrack(_ url: URL) throws -> GPXTrack {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw GPXError.unreadableFile(error.localizedDescription)
        }
        return try parseTrack(data: data)
    }

    /// Same parser, from raw GPX bytes directly (used by tests, and anything re-parsing
    /// data it already has in memory).
    static func parseTrack(data: Data) throws -> GPXTrack {
        guard !data.isEmpty else { throw GPXError.malformedXML("the file is empty") }
        let delegate = GPXParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            let reason = parser.parserError?.localizedDescription ?? "the XML could not be parsed"
            throw GPXError.malformedXML(reason)
        }
        if let error = delegate.validationError {
            throw error
        }
        let track = delegate.buildTrack()
        guard !track.isEmpty else { throw GPXError.noTrackPoints }
        return track
    }

    /// Back-compat entry point: every existing call site just wants the flat path.
    static func parse(_ url: URL) throws -> [CLLocationCoordinate2D] {
        try parseTrack(url).coordinates
    }

    /// Rich export: multiple `<trkseg>` blocks, with `<ele>`/`<time>` included per point
    /// whenever the track has them.
    static func export(_ track: GPXTrack) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Locus" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>\(xmlEscape(track.name?.isEmpty == false ? track.name! : "Locus Route"))</name>

        """
        let segmentsToWrite = track.segments.isEmpty ? [[]] : track.segments
        for segment in segmentsToWrite {
            xml += "    <trkseg>\n"
            for point in segment {
                xml += "      <trkpt lat=\"\(coordinateString(point.coordinate.latitude))\" lon=\"\(coordinateString(point.coordinate.longitude))\">"
                var wroteChild = false
                if let elevation = point.elevation, elevation.isFinite {
                    xml += "\n        <ele>\(elevationString(elevation))</ele>"
                    wroteChild = true
                }
                if let time = point.time {
                    xml += "\n        <time>\(isoFormatter.string(from: time))</time>"
                    wroteChild = true
                }
                xml += wroteChild ? "\n      </trkpt>\n" : "</trkpt>\n"
            }
            xml += "    </trkseg>\n"
        }
        xml += """
          </trk>
        </gpx>
        """
        return xml
    }

    /// Back-compat entry point: wraps a flat coordinate list (no elevation/time) into a
    /// single-segment track — exactly what every existing call site already passes in.
    static func export(_ coordinates: [CLLocationCoordinate2D], name: String = "Locus Route") -> String {
        let points = coordinates.map { GPXTrackPoint(coordinate: $0) }
        return export(GPXTrack(name: name, segments: [points]))
    }

    // MARK: - Formatting

    /// 7 decimal places (~1cm at the equator) — comfortably preserves precision through
    /// an export/re-import round trip without the file size of full double precision.
    private static func coordinateString(_ value: Double) -> String {
        String(format: "%.7f", value)
    }

    private static func elevationString(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// No fractional seconds on export, for maximum compatibility with GPX readers;
    /// parsing (below) accepts fractional seconds too, for files from other tools.
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

/// SAX-style GPX parser. Only `<trk>` / `<trkseg>` / `<trkpt>` (and their `<ele>`/`<time>`
/// children) are ever inspected for coordinates — waypoints (`<wpt>`), route points
/// (`<rtept>`), and metadata such as `<bounds minlat="…" minlon="…" .../>` are never
/// touched. The previous regex-based parser matched `lat="…" … lon="…"` anywhere in the
/// file, so a `<bounds>` element (present in most real-world GPX exports) was silently
/// misread as a track point — this is the actual reason GPX import produced wrong/broken
/// routes.
private final class GPXParserDelegate: NSObject, XMLParserDelegate {
    private var segments: [[GPXTrackPoint]] = []
    private var currentSegment: [GPXTrackPoint] = []
    private var trackName: String?

    private var elementStack: [String] = []
    private var currentText = ""

    private var insideTrkpt = false
    private var pendingLat: Double?
    private var pendingLon: Double?
    private var pendingElevation: Double?
    private var pendingTime: Date?

    private(set) var validationError: GPXError?

    private static let isoFormatterFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let isoFormatter = ISO8601DateFormatter()

    func buildTrack() -> GPXTrack {
        if !currentSegment.isEmpty {
            segments.append(currentSegment)
            currentSegment = []
        }
        return GPXTrack(name: trackName, segments: segments)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard validationError == nil else { return }
        let name = Self.localName(elementName)
        elementStack.append(name)
        currentText = ""

        switch name {
        case "trkseg":
            if !currentSegment.isEmpty {
                segments.append(currentSegment)
                currentSegment = []
            }
        case "trkpt":
            insideTrkpt = true
            pendingElevation = nil
            pendingTime = nil
            let latText = attributeDict["lat"] ?? ""
            let lonText = attributeDict["lon"] ?? ""
            guard let lat = Double(latText), let lon = Double(lonText),
                  lat.isFinite, lon.isFinite,
                  (-90...90).contains(lat), (-180...180).contains(lon) else {
                pendingLat = nil
                pendingLon = nil
                validationError = .invalidCoordinate(
                    lat: attributeDict["lat"] ?? "missing",
                    lon: attributeDict["lon"] ?? "missing"
                )
                return
            }
            pendingLat = lat
            pendingLon = lon
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard validationError == nil else { return }
        let name = Self.localName(elementName)
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        currentText = ""

        switch name {
        case "name":
            // Only a track-level <trk><name>, never a <wpt><name> or top-level
            // <metadata><name>, so those don't silently overwrite the track's name.
            if elementStack.count >= 2, elementStack[elementStack.count - 2] == "trk", !text.isEmpty {
                trackName = text
            }
        case "ele":
            if insideTrkpt, let value = Double(text), value.isFinite {
                pendingElevation = value
            }
        case "time":
            if insideTrkpt {
                pendingTime = Self.isoFormatterFractional.date(from: text) ?? Self.isoFormatter.date(from: text)
            }
        case "trkpt":
            if let lat = pendingLat, let lon = pendingLon {
                currentSegment.append(GPXTrackPoint(
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    elevation: pendingElevation,
                    time: pendingTime
                ))
            }
            insideTrkpt = false
            pendingLat = nil
            pendingLon = nil
            pendingElevation = nil
            pendingTime = nil
        default:
            break
        }

        if !elementStack.isEmpty { elementStack.removeLast() }
    }

    /// `XMLParser` reports the same failure two ways: this delegate callback, and a
    /// `false` return from `parser.parse()` (which is what the caller above actually
    /// checks, reading `parser.parserError` for the message). Nothing extra to do here.
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {}

    private static func localName(_ elementName: String) -> String {
        guard let colonIndex = elementName.lastIndex(of: ":") else { return elementName }
        return String(elementName[elementName.index(after: colonIndex)...])
    }
}

private func xmlEscape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}

