import CoreLocation
import Foundation
import MapKit

// MARK: - Coordinate Equatable Extension

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

// MARK: - Route Creation Method

enum RouteCreationMethod: String, CaseIterable, Identifiable {
    case points = "Points"
    case freehand = "Freehand"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .points: return "mappin.and.ellipse"
        case .freehand: return "pencil.tip.crop.circle"
        }
    }

    var title: String {
        switch self {
        case .points: return "Points Route"
        case .freehand: return "Freehand Route"
        }
    }

    var description: String {
        switch self {
        case .points:
            return "Place sequential waypoints on the map to build road or direct paths."
        case .freehand:
            return "Draw any custom trajectory by dragging your finger freely across the map."
        }
    }
}

// MARK: - Points Connection Type

enum RouteConnectionType: String, CaseIterable, Identifiable {
    case road = "Roads"
    case straight = "Straight"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .road: return "road.lanes"
        case .straight: return "line.diagonal"
        }
    }
}

// MARK: - Route Connection Preference

enum RouteConnectionPreference {
    static let key = "locus.default_connection_type"

    static var defaultType: RouteConnectionType {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let type = RouteConnectionType(rawValue: raw) else {
                return .road
            }
            return type
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}

// MARK: - Route Waypoint Model

struct RouteWaypoint: Identifiable, Equatable, Hashable {
    let id: UUID
    var coordinate: CLLocationCoordinate2D
    var name: String
    var stopDuration: TimeInterval // 0 = normal pass-through waypoint; > 0 = dwell stop in seconds

    init(
        id: UUID = UUID(),
        coordinate: CLLocationCoordinate2D,
        name: String = "",
        stopDuration: TimeInterval = 0
    ) {
        self.id = id
        self.coordinate = coordinate
        self.name = name
        self.stopDuration = stopDuration
    }

    var isStop: Bool {
        stopDuration > 0
    }

    var formattedStopDuration: String {
        guard stopDuration > 0 else { return "Pass-through" }
        let totalSecs = Int(stopDuration)
        let hours = totalSecs / 3600
        let minutes = (totalSecs % 3600) / 60
        let seconds = totalSecs % 60

        if hours > 0 {
            if minutes > 0 && seconds > 0 {
                return "\(hours)h \(minutes)m \(seconds)s"
            } else if minutes > 0 {
                return "\(hours)h \(minutes)m"
            } else if seconds > 0 {
                return "\(hours)h \(seconds)s"
            } else {
                return "\(hours)h"
            }
        } else if minutes > 0 {
            if seconds > 0 {
                return "\(minutes)m \(seconds)s"
            } else {
                return "\(minutes)m"
            }
        } else {
            return "\(seconds)s"
        }
    }

    static func == (lhs: RouteWaypoint, rhs: RouteWaypoint) -> Bool {
        lhs.id == rhs.id &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.name == rhs.name &&
        lhs.stopDuration == rhs.stopDuration
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
        hasher.combine(name)
        hasher.combine(stopDuration)
    }
}

// MARK: - Route Builder Engine

enum RouteBuilder {
    // MARK: - Road Route (2 Points)

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
            throw NSError(domain: "Locus", code: 1, userInfo: [NSLocalizedDescriptionKey: "No road route found between points."])
        }
        var sampled = sample(polyline: route.polyline, every: mode == .sidewalk ? 7 : 12)
        if mode == .sidewalk {
            sampled = applySidewalkOffset(coordinates: sampled, offsetMeters: 3.2)
        }
        return sampled
    }

    /// Offsets path ~3.2m perpendicular to travel direction so the route follows pedestrian sidewalks rather than street centerlines
    static func applySidewalkOffset(coordinates: [CLLocationCoordinate2D], offsetMeters: Double = 3.2) -> [CLLocationCoordinate2D] {
        guard coordinates.count >= 2 else { return coordinates }
        var result: [CLLocationCoordinate2D] = []
        let earthRadius = 6378137.0 // meters

        for i in 0..<coordinates.count {
            let p = coordinates[i]
            let heading: Double
            if i < coordinates.count - 1 {
                let next = coordinates[i + 1]
                heading = atan2(next.longitude - p.longitude, next.latitude - p.latitude)
            } else {
                let prev = coordinates[i - 1]
                heading = atan2(p.longitude - prev.longitude, p.latitude - prev.latitude)
            }

            // Normal angle 90 degrees to the right for standard sidewalk
            let perpAngle = heading + (.pi / 2.0)
            let latOffset = (offsetMeters * cos(perpAngle)) / earthRadius * (180.0 / .pi)
            let lonOffset = (offsetMeters * sin(perpAngle)) / (earthRadius * cos(p.latitude * .pi / 180.0)) * (180.0 / .pi)

            result.append(CLLocationCoordinate2D(
                latitude: p.latitude + latOffset,
                longitude: p.longitude + lonOffset
            ))
        }
        return result
    }

    // MARK: - Multi-Point Road Route (Points Method)

    static func multiPointRoadRoute(
        waypoints: [CLLocationCoordinate2D],
        mode: TravelMode
    ) async throws -> [CLLocationCoordinate2D] {
        guard waypoints.count >= 2 else { return waypoints }
        if waypoints.count == 2 {
            return try await roadRoute(from: waypoints[0], to: waypoints[1], mode: mode)
        }

        var fullRoute: [CLLocationCoordinate2D] = []
        for i in 0..<(waypoints.count - 1) {
            let start = waypoints[i]
            let end = waypoints[i + 1]
            let leg = try await roadRoute(from: start, to: end, mode: mode)
            if fullRoute.isEmpty {
                fullRoute.append(contentsOf: leg)
            } else {
                // Drop duplicate connecting point
                fullRoute.append(contentsOf: leg.dropFirst())
            }
        }
        return fullRoute
    }

    // MARK: - Multi-Point Straight Route (Points Method)

    static func multiPointStraightRoute(
        waypoints: [CLLocationCoordinate2D],
        every meters: CLLocationDistance = 8
    ) -> [CLLocationCoordinate2D] {
        guard waypoints.count >= 2 else { return waypoints }
        return sample(coordinates: waypoints, every: meters)
    }

    // MARK: - Freehand Path Processor (Freehand Method)

    /// Cleans, smooths, and samples freehand drawn strokes into a simulation-ready path.
    static func processFreehandPath(
        coordinates: [CLLocationCoordinate2D],
        sampleMeters: CLLocationDistance = 6,
        smooth: Bool = true
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count >= 2 else { return coordinates }

        // 1. Remove micro-duplicates (touches closer than 1.5m)
        var deduped: [CLLocationCoordinate2D] = [coordinates[0]]
        for pt in coordinates.dropFirst() {
            let prev = deduped.last!
            let d = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
                .distance(from: CLLocation(latitude: pt.latitude, longitude: pt.longitude))
            if d >= 1.5 {
                deduped.append(pt)
            }
        }
        guard deduped.count >= 2 else { return coordinates }

        // 2. Apply moving average smoothing if requested
        let smoothed: [CLLocationCoordinate2D]
        if smooth && deduped.count >= 4 {
            smoothed = smoothMovingAverage(deduped, window: 3)
        } else {
            smoothed = deduped
        }

        // 3. Resample evenly along the smoothed curve
        return sample(coordinates: smoothed, every: sampleMeters)
    }

    private static func smoothMovingAverage(
        _ points: [CLLocationCoordinate2D],
        window: Int = 3
    ) -> [CLLocationCoordinate2D] {
        guard points.count > window else { return points }
        var result: [CLLocationCoordinate2D] = []
        result.append(points[0])

        let half = window / 2
        for i in 1..<(points.count - 1) {
            let start = max(0, i - half)
            let end = min(points.count - 1, i + half)
            let count = Double(end - start + 1)
            var latSum = 0.0
            var lonSum = 0.0
            for j in start...end {
                latSum += points[j].latitude
                lonSum += points[j].longitude
            }
            result.append(CLLocationCoordinate2D(latitude: latSum / count, longitude: lonSum / count))
        }

        result.append(points.last!)
        return result
    }

    // MARK: - Sampling & Interpolation

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

    // MARK: - Metrics & Formatting

    static func totalDistance(of coordinates: [CLLocationCoordinate2D]) -> CLLocationDistance {
        guard coordinates.count > 1 else { return 0 }
        var total: CLLocationDistance = 0
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            total += CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        }
        return total
    }

    static func formattedDistance(_ meters: CLLocationDistance) -> String {
        if meters < 1000 {
            return String(format: "%.0f m", meters)
        } else {
            return String(format: "%.2f km", meters / 1000.0)
        }
    }

    static func estimatedDuration(distance: CLLocationDistance, speed: CLLocationSpeed) -> TimeInterval {
        guard speed > 0.1 else { return 0 }
        return distance / speed
    }

    static func formattedDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }

    static func formattedETA(_ seconds: TimeInterval) -> String {
        guard seconds > 1 else { return "< 1m" }
        let durationStr = formattedDuration(seconds)
        let arrivalDate = Date().addingTimeInterval(seconds)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let timeStr = formatter.string(from: arrivalDate)
        return "\(durationStr) (\(timeStr))"
    }
}

// MARK: - GPX data model

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

    static func parse(_ url: URL) throws -> [CLLocationCoordinate2D] {
        try parseTrack(url).coordinates
    }

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

    static func export(_ coordinates: [CLLocationCoordinate2D], name: String = "Locus Route") -> String {
        let points = coordinates.map { GPXTrackPoint(coordinate: $0) }
        return export(GPXTrack(name: name, segments: [points]))
    }

    private static func coordinateString(_ value: Double) -> String {
        String(format: "%.7f", value)
    }

    private static func elevationString(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

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
