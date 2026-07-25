import MapKit

final class RoutePolyline: MKPolyline {
    static func from(journey: Journey) -> RoutePolyline {
        let coords = journey.allCoordinates
        return RoutePolyline(coordinates: coords, count: coords.count)
    }
}
