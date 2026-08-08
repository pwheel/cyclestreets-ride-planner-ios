//
//  PlaceTests.swift
//  CycleStreets Ride PlannerTests
//

import Testing
import MapKit
@testable import CycleStreets_Ride_Planner

struct PlaceTests {

    @Test func initFromMapItemUsesNameAndCoordinate() {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 52.2053, longitude: 0.1218))
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = "Cambridge Market"
        let place = Place(mapItem: mapItem)
        #expect(place.name == "Cambridge Market")
        #expect(place.coordinate.latitude == 52.2053)
        #expect(place.coordinate.longitude == 0.1218)
    }

    @Test func initFromMapItemCombinesLocalityAndAdministrativeAreaIntoNear() {
        let placemark = MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: 51.5034, longitude: -0.1275),
            addressDictionary: ["City": "London", "State": "England"]
        )
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = "Downing Street"
        let place = Place(mapItem: mapItem)
        #expect(place.near == "London, England")
    }

    @Test func initFromMapItemWithNoLocalityLeavesNearNil() {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0))
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = "Null Island"
        let place = Place(mapItem: mapItem)
        #expect(place.near == nil)
    }

    @Test func initFromMapItemWithNilNameFallsBackToPlaceholder() {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 1))
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = ""
        let place = Place(mapItem: mapItem)
        #expect(place.name == "Unknown location")
    }

    @Test func initFromMapItemAssignsAFreshIdentifier() {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 1))
        let first = Place(mapItem: MKMapItem(placemark: placemark))
        let second = Place(mapItem: MKMapItem(placemark: placemark))
        #expect(first.id != second.id)
    }
}
