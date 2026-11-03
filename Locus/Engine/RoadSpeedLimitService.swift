import CoreLocation
import Foundation
import SwiftUI

// MARK: - Road Speed Limit Model

public struct RoadSpeedInfo: Equatable, Codable {
    public let speedLimitMPS: Double
    public let speedLimitMPH: Double
    public let speedLimitKMH: Double
    public let roadName: String
    public let roadType: String
    public let isExplicit: Bool // Explicitly signed maxspeed vs inferred road type default
    public let timestamp: Date

    public func formatted(unit: SpeedUnit) -> String {
        switch unit {
        case .mph:
            return "\(Int(round(speedLimitMPH))) MPH"
        case .kmh:
            return "\(Int(round(speedLimitKMH))) KM/H"
        case .mps:
            return String(format: "%.1f m/s", speedLimitMPS)
        }
    }
}

// MARK: - Road Speed Limit Service

@MainActor
public final class RoadSpeedLimitService: ObservableObject {
    public static let shared = RoadSpeedLimitService()

    @Published public var currentRoadSpeed: RoadSpeedInfo? = nil
    @Published public var isFetching: Bool = false
    @Published public var lastQueriedCoordinate: CLLocationCoordinate2D? = nil

    // Cache: grid key (latitude & longitude rounded to ~100m) -> RoadSpeedInfo
    private var cache: [String: RoadSpeedInfo] = [:]
    private var activeTask: Task<Void, Never>? = nil
    private var lastFetchTime: Date = .distantPast

    private init() {}

    /// Queries the posted or statutory speed limit for the given coordinate.
    public func fetchSpeedLimit(at coordinate: CLLocationCoordinate2D, force: Bool = false) {
        let key = cacheKey(for: coordinate)

        // 1. Check in-memory cache
        if let cached = cache[key] {
            if self.currentRoadSpeed != cached {
                self.currentRoadSpeed = cached
            }
            return
        }

        // Throttle network queries during rapid traversal (min 2.5 seconds between remote API hits)
        if !force && Date().timeIntervalSince(lastFetchTime) < 2.5 {
            return
        }

        activeTask?.cancel()
        activeTask = Task { [weak self] in
            guard let self else { return }
            self.isFetching = true
            self.lastFetchTime = Date()
            self.lastQueriedCoordinate = coordinate

            let info = await self.performLookup(coordinate: coordinate)
            if !Task.isCancelled {
                self.cache[key] = info
                self.currentRoadSpeed = info
                self.isFetching = false
            }
        }
    }

    private func cacheKey(for coord: CLLocationCoordinate2D) -> String {
        let latBucket = Int(round(coord.latitude * 1000.0))
        let lonBucket = Int(round(coord.longitude * 1000.0))
        return "\(latBucket)_\(lonBucket)"
    }

    // MARK: - Remote Lookup with OSM Nominatim & Overpass Fallback

    private func performLookup(coordinate: CLLocationCoordinate2D) async -> RoadSpeedInfo {
        // Try Nominatim reverse lookup with extratags
        if let result = await fetchFromNominatim(coordinate: coordinate) {
            return result
        }

        // Fallback: Default reasonable city road speed if offline or unreachable
        return RoadSpeedInfo(
            speedLimitMPS: 11.176, // 25 mph
            speedLimitMPH: 25.0,
            speedLimitKMH: 40.0,
            roadName: "Local Road",
            roadType: "residential",
            isExplicit: false,
            timestamp: Date()
        )
    }

    private func fetchFromNominatim(coordinate: CLLocationCoordinate2D) async -> RoadSpeedInfo? {
        let latStr = String(format: "%.6f", coordinate.latitude)
        let lonStr = String(format: "%.6f", coordinate.longitude)
        let urlString = "https://nominatim.openstreetmap.org/reverse?lat=\(latStr)&lon=\(lonStr)&format=json&extratags=1&zoom=17"

        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0
        request.setValue("Locus-iOS-SpeedLimit/1.0 (com.chrismack.locus)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            let roadName = (json["address"] as? [String: Any])?["road"] as? String
                ?? (json["name"] as? String)
                ?? "Road"
            let highwayType = json["type"] as? String ?? (json["addresstype"] as? String ?? "residential")
            let countryCode = (json["address"] as? [String: Any])?["country_code"] as? String ?? "us"
            let isMetric = countryCode.lowercased() != "us" && countryCode.lowercased() != "gb"

            let extratags = json["extratags"] as? [String: Any] ?? [:]
            let rawMaxspeed = extratags["maxspeed"] as? String

            if let rawMaxspeed, let parsed = parseMaxspeed(rawMaxspeed) {
                return RoadSpeedInfo(
                    speedLimitMPS: parsed.mps,
                    speedLimitMPH: parsed.mph,
                    speedLimitKMH: parsed.kmh,
                    roadName: roadName,
                    roadType: highwayType,
                    isExplicit: true,
                    timestamp: Date()
                )
            }

            // Statutorily inferred speed limit based on road classification
            let defaultMPH = inferDefaultSpeedMPH(highwayType: highwayType, isMetric: isMetric)
            let defaultMPS = defaultMPH * 0.44704
            let defaultKMH = defaultMPH * 1.60934

            return RoadSpeedInfo(
                speedLimitMPS: defaultMPS,
                speedLimitMPH: defaultMPH,
                speedLimitKMH: defaultKMH,
                roadName: roadName,
                roadType: highwayType,
                isExplicit: false,
                timestamp: Date()
            )
        } catch {
            return nil
        }
    }

    private func parseMaxspeed(_ raw: String) -> (mps: Double, mph: Double, kmh: Double)? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleaned.contains("none") || cleaned.contains("signals") { return nil }

        let isExplicitMPH = cleaned.contains("mph")
        let isExplicitKMH = cleaned.contains("km/h") || cleaned.contains("kmh") || cleaned.contains("kph")

        let digits = cleaned.filter { "0123456789.".contains($0) }
        guard let num = Double(digits), num > 0 else { return nil }

        if isExplicitMPH {
            let mps = num * 0.44704
            let kmh = num * 1.60934
            return (mps, num, kmh)
        } else if isExplicitKMH {
            let mps = num / 3.6
            let mph = num / 1.60934
            return (mps, mph, num)
        } else {
            // Default to MPH if < 80 and numeric, or KMH if > 80
            if num <= 75 {
                let mps = num * 0.44704
                let kmh = num * 1.60934
                return (mps, num, kmh)
            } else {
                let mps = num / 3.6
                let mph = num / 1.60934
                return (mps, mph, num)
            }
        }
    }

    private func inferDefaultSpeedMPH(highwayType: String, isMetric: Bool) -> Double {
        switch highwayType.lowercased() {
        case "motorway", "motorway_link":
            return isMetric ? 68.3 : 65.0 // ~110 km/h or 65 mph
        case "trunk", "trunk_link":
            return isMetric ? 55.9 : 55.0 // ~90 km/h or 55 mph
        case "primary", "primary_link":
            return isMetric ? 43.5 : 40.0 // ~70 km/h or 40 mph
        case "secondary", "secondary_link":
            return isMetric ? 31.0 : 30.0 // ~50 km/h or 30 mph
        case "tertiary", "tertiary_link":
            return isMetric ? 25.0 : 25.0 // ~40 km/h or 25 mph
        case "residential", "unclassified":
            return isMetric ? 25.0 : 25.0 // ~40 km/h or 25 mph
        case "living_street", "service":
            return isMetric ? 12.4 : 15.0 // ~20 km/h or 15 mph
        default:
            return 25.0
        }
    }
}
