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
        title: String? = nil,
        stopDuration: TimeInterval = 0
    ) {
        self.id = id
        self.coordinate = coordinate
        self.name = title ?? (name.isEmpty ? "" : name)
        self.stopDuration = stopDuration
    }

    var title: String {
        get { name }
        set { name = newValue }
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

    /// Offsets path perpendicular to geodesic travel direction so routes follow sidewalks cleanly across all latitudes.
    static func applySidewalkOffset(coordinates: [CLLocationCoordinate2D], offsetMeters: Double = 3.2) -> [CLLocationCoordinate2D] {
        let valid = coordinates.filter { RouteSimulationEngine.isValidCoordinate($0) }
        guard valid.count >= 2, offsetMeters.isFinite, abs(offsetMeters) > 1e-4 else { return valid }

        var result: [CLLocationCoordinate2D] = []
        result.reserveCapacity(valid.count)
        var lastValidHeading: Double? = nil

        for i in 0..<valid.count {
            let p = valid[i]
            var heading: Double? = nil

            // Look ahead to the next distinct coordinate so duplicate vertices do not corrupt heading
            if i < valid.count - 1 {
                for j in (i + 1)..<valid.count {
                    if RouteSimulationEngine.haversineDistance(from: p, to: valid[j]) >= 0.05 {
                        heading = RouteSimulationEngine.greatCircleBearing(from: p, to: valid[j])
                        break
                    }
                }
            }
            if heading == nil, i > 0 {
                for j in stride(from: i - 1, through: 0, by: -1) {
                    if RouteSimulationEngine.haversineDistance(from: valid[j], to: p) >= 0.05 {
                        heading = RouteSimulationEngine.greatCircleBearing(from: valid[j], to: p)
                        break
                    }
                }
            }

            let resolvedHeading = heading ?? lastValidHeading ?? 0.0
            lastValidHeading = resolvedHeading

            // 90 degrees clockwise (right-hand sidewalk relative to forward travel)
            let perpBearingRad = ((resolvedHeading + 90.0) * .pi) / 180.0
            let eastOffset = offsetMeters * sin(perpBearingRad)
            let northOffset = offsetMeters * cos(perpBearingRad)
            result.append(RouteSimulationEngine.offsetCoordinate(p, eastMeters: eastOffset, northMeters: northOffset))
        }
        return result
    }

    // MARK: - Multi-Point Road Route (Points Method)

    static func multiPointRoadRoute(
        waypoints: [CLLocationCoordinate2D],
        mode: TravelMode
    ) async throws -> [CLLocationCoordinate2D] {
        let valid = waypoints.filter { RouteSimulationEngine.isValidCoordinate($0) }
        guard valid.count >= 2 else { return valid }
        if valid.count == 2 {
            return try await roadRoute(from: valid[0], to: valid[1], mode: mode)
        }

        var fullRoute: [CLLocationCoordinate2D] = []
        for i in 0..<(valid.count - 1) {
            let start = valid[i]
            let end = valid[i + 1]
            if RouteSimulationEngine.haversineDistance(from: start, to: end) < 0.5 {
                continue
            }
            let leg = try await roadRoute(from: start, to: end, mode: mode)
            if fullRoute.isEmpty {
                fullRoute.append(contentsOf: leg)
            } else {
                fullRoute.append(contentsOf: leg.dropFirst())
            }
        }
        return fullRoute.isEmpty ? valid : fullRoute
    }

    // MARK: - Multi-Point Straight Route (Points Method)

    static func multiPointStraightRoute(
        waypoints: [CLLocationCoordinate2D],
        every meters: CLLocationDistance = 8
    ) -> [CLLocationCoordinate2D] {
        let valid = waypoints.filter { RouteSimulationEngine.isValidCoordinate($0) }
        guard valid.count >= 2 else { return valid }
        return sample(coordinates: valid, every: meters)
    }

    // MARK: - Freehand Path Processor (Freehand Method)

    /// Cleans, smooths, and samples freehand drawn strokes into a simulation-ready path.
    static func processFreehandPath(
        coordinates: [CLLocationCoordinate2D],
        sampleMeters: CLLocationDistance = 6,
        smooth: Bool = true
    ) -> [CLLocationCoordinate2D] {
        let valid = coordinates.filter { RouteSimulationEngine.isValidCoordinate($0) }
        guard valid.count >= 2 else { return valid }

        // 1. Remove micro-duplicates (touches closer than 1.5m)
        var deduped: [CLLocationCoordinate2D] = [valid[0]]
        for pt in valid.dropFirst() {
            if let prev = deduped.last,
               RouteSimulationEngine.haversineDistance(from: prev, to: pt) >= 1.5 {
                deduped.append(pt)
            }
        }
        guard deduped.count >= 2 else { return deduped }

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
        guard points.count > window, window >= 1 else { return points }
        var result: [CLLocationCoordinate2D] = []
        result.reserveCapacity(points.count)
        result.append(points[0])

        let half = window / 2
        for i in 1..<(points.count - 1) {
            let start = max(0, i - half)
            let end = min(points.count - 1, i + half)
            let count = Double(end - start + 1)
            let anchor = points[i]
            var latSum = 0.0
            var dLonSum = 0.0
            for j in start...end {
                latSum += points[j].latitude
                // Unwrap longitude delta relative to anchor so paths crossing +-180° smooth cleanly
                dLonSum += RouteSimulationEngine.normalizeLongitude(points[j].longitude - anchor.longitude)
            }
            let avgLat = min(90.0, max(-90.0, latSum / count))
            let avgLon = RouteSimulationEngine.normalizeLongitude(anchor.longitude + (dLonSum / count))
            result.append(CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon))
        }

        if let last = points.last {
            result.append(last)
        }
        return result
    }

    // MARK: - Sampling & Interpolation

    private static let minimumSampleSpacingMeters: CLLocationDistance = 0.5
    private static let maximumStepsPerSegment: Int = 50_000

    static func sample(polyline: MKPolyline, every meters: CLLocationDistance) -> [CLLocationCoordinate2D] {
        guard polyline.pointCount > 0 else { return [] }
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: polyline.pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        return sample(coordinates: coords, every: meters)
    }

    /// Safely samples a polyline at approximate Great Circle intervals of `meters`.
    /// Validates spacing (zero/negative/NaN/Inf), avoids duplicate points, and prevents Int overflow.
    static func sample(coordinates: [CLLocationCoordinate2D], every meters: CLLocationDistance) -> [CLLocationCoordinate2D] {
        let valid = coordinates.filter { RouteSimulationEngine.isValidCoordinate($0) }
        guard valid.count > 1 else { return valid }

        // Deduplicate micro-identical consecutive vertices first
        var deduped: [CLLocationCoordinate2D] = [valid[0]]
        for pt in valid.dropFirst() {
            if let prev = deduped.last,
               RouteSimulationEngine.haversineDistance(from: prev, to: pt) >= 0.01 {
                deduped.append(pt)
            }
        }
        guard deduped.count > 1 else { return deduped }

        // If spacing is invalid (<= 0, NaN, infinite), do not crash or subdivide blindly:
        // return cleaned, deduplicated vertices safely.
        guard meters.isFinite, meters > 0 else {
            return deduped
        }

        let effectiveSpacing = max(minimumSampleSpacingMeters, meters)
        var sampled: [CLLocationCoordinate2D] = [deduped[0]]

        for (a, b) in zip(deduped, deduped.dropFirst()) {
            let dist = RouteSimulationEngine.haversineDistance(from: a, to: b)
            guard dist.isFinite, dist >= 0.01 else { continue }

            let ratio = dist / effectiveSpacing
            let steps: Int
            if !ratio.isFinite || ratio >= Double(maximumStepsPerSegment) {
                steps = maximumStepsPerSegment
            } else {
                steps = max(1, Int(ceil(ratio)))
            }

            for i in 1...steps {
                let t = Double(i) / Double(steps)
                let interpolated = (i == steps)
                    ? b
                    : RouteSimulationEngine.interpolateGreatCircle(from: a, to: b, fraction: t)
                if let last = sampled.last,
                   RouteSimulationEngine.haversineDistance(from: last, to: interpolated) < 1e-4 {
                    continue
                }
                sampled.append(interpolated)
            }
        }

        return sampled
    }

    /// Samples each continuous coordinate segment independently without connecting separate segments.
    static func sample(coordinateSegments segments: [[CLLocationCoordinate2D]], every meters: CLLocationDistance) -> [[CLLocationCoordinate2D]] {
        segments.compactMap { seg in
            let res = sample(coordinates: seg, every: meters)
            return res.isEmpty ? nil : res
        }
    }

    /// Samples a GPX track per segment while preserving track name and segment boundaries.
    static func sample(track: GPXTrack, every meters: CLLocationDistance) -> GPXTrack {
        let sampledSegments: [[GPXTrackPoint]] = track.segments.compactMap { seg in
            let coords = sample(coordinates: seg.map(\.coordinate), every: meters)
            guard !coords.isEmpty else { return nil }
            return coords.map { GPXTrackPoint(coordinate: $0) }
        }
        return GPXTrack(name: track.name, segments: sampledSegments)
    }

    // MARK: - Metrics & Formatting

    static func totalDistance(of coordinates: [CLLocationCoordinate2D]) -> CLLocationDistance {
        let valid = coordinates.filter { RouteSimulationEngine.isValidCoordinate($0) }
        guard valid.count > 1 else { return 0 }
        var total: CLLocationDistance = 0
        for (a, b) in zip(valid, valid.dropFirst()) {
            let d = RouteSimulationEngine.haversineDistance(from: a, to: b)
            if d.isFinite && d > 0 {
                total += d
            }
        }
        return total
    }

    /// Computes total track distance across disjoint segments without bridging across segment gaps.
    static func totalDistance(ofSegments segments: [[CLLocationCoordinate2D]]) -> CLLocationDistance {
        segments.reduce(0.0) { $0 + totalDistance(of: $1) }
    }

    static func totalDistance(of track: GPXTrack) -> CLLocationDistance {
        totalDistance(ofSegments: track.coordinateSegments)
    }

    static func formattedDistance(_ meters: CLLocationDistance) -> String {
        let safeMeters = (meters.isFinite && meters >= 0) ? meters : 0
        if safeMeters < 1000 {
            return String(format: "%.0f m", safeMeters)
        } else {
            return String(format: "%.2f km", safeMeters / 1000.0)
        }
    }

    static func estimatedDuration(distance: CLLocationDistance, speed: CLLocationSpeed) -> TimeInterval {
        guard distance.isFinite, distance > 0, speed.isFinite, speed > 0.1 else { return 0 }
        let secs = distance / speed
        return secs.isFinite ? secs : 0
    }

    static func formattedDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0s" }
        let clamped = min(Double(Int.max / 2), seconds)
        let totalSeconds = Int(clamped)
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
        guard seconds.isFinite, seconds > 1 else { return "< 1m" }
        let clamped = min(86400.0 * 30.0, seconds)
        let durationStr = formattedDuration(clamped)
        let arrivalDate = Date().addingTimeInterval(clamped)
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
        self.elevation = (elevation?.isFinite == true) ? elevation : nil
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

    var coordinateSegments: [[CLLocationCoordinate2D]] {
        segments.compactMap { seg in
            let coords = seg.map(\.coordinate).filter { RouteSimulationEngine.isValidCoordinate($0) }
            return coords.isEmpty ? nil : coords
        }
    }

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
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Locus" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>\(xmlEscape(track.name?.isEmpty == false ? track.name! : "Locus Route"))</name>

        """
        let nonEmptySegments = track.segments.filter { !$0.isEmpty }
        let segmentsToWrite = nonEmptySegments.isEmpty ? [[]] : nonEmptySegments
        for segment in segmentsToWrite {
            xml += "    <trkseg>\n"
            for point in segment where RouteSimulationEngine.isValidCoordinate(point.coordinate) {
                xml += "      <trkpt lat=\"\(coordinateString(point.coordinate.latitude))\" lon=\"\(coordinateString(point.coordinate.longitude))\">"
                var wroteChild = false
                if let elevation = point.elevation, elevation.isFinite {
                    xml += "\n        <ele>\(elevationString(elevation))</ele>"
                    wroteChild = true
                }
                if let time = point.time {
                    xml += "\n        <time>\(formatter.string(from: time))</time>"
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
        let points = coordinates
            .filter { RouteSimulationEngine.isValidCoordinate($0) }
            .map { GPXTrackPoint(coordinate: $0) }
        return export(GPXTrack(name: name, segments: [points]))
    }

    static func export(coordinateSegments segments: [[CLLocationCoordinate2D]], name: String = "Locus Route") -> String {
        let gpxSegments = segments.compactMap { seg -> [GPXTrackPoint]? in
            let pts = seg.filter { RouteSimulationEngine.isValidCoordinate($0) }.map { GPXTrackPoint(coordinate: $0) }
            return pts.isEmpty ? nil : pts
        }
        return export(GPXTrack(name: name, segments: gpxSegments))
    }

    private static func coordinateString(_ value: Double) -> String {
        String(format: "%.7f", value)
    }

    private static func elevationString(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
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

    // Instance-owned formatters keep concurrent GPXCodec parses completely thread-safe
    private let isoFormatterFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private func flushCurrentSegment() {
        if !currentSegment.isEmpty {
            segments.append(currentSegment)
            currentSegment = []
        }
    }

    func buildTrack() -> GPXTrack {
        flushCurrentSegment()
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
        case "trk", "trkseg":
            flushCurrentSegment()
        case "trkpt":
            insideTrkpt = true
            pendingElevation = nil
            pendingTime = nil
            let latRaw = attributeDict["lat"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let lonRaw = attributeDict["lon"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let lat = Double(latRaw), let lon = Double(lonRaw),
                  lat.isFinite, lon.isFinite,
                  (-90...90).contains(lat), (-180...180).contains(lon) else {
                pendingLat = nil
                pendingLon = nil
                validationError = .invalidCoordinate(
                    lat: latRaw.isEmpty ? "missing" : latRaw,
                    lon: lonRaw.isEmpty ? "missing" : lonRaw
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
            if trackName == nil, elementStack.count >= 2, elementStack[elementStack.count - 2] == "trk", !text.isEmpty {
                trackName = text
            }
        case "ele":
            if insideTrkpt, !text.isEmpty, let value = Double(text), value.isFinite {
                pendingElevation = value
            }
        case "time":
            if insideTrkpt, !text.isEmpty {
                pendingTime = isoFormatterFractional.date(from: text) ?? isoFormatter.date(from: text)
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
        case "trkseg", "trk":
            flushCurrentSegment()
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
