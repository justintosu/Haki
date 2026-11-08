//
//  PlacesPlace.swift
//  Haki
//
//  A restaurant, café or store found with Apple Maps search: the details the
//  places list and the menu screen show, and the `FoodPlaceQuery` Haki's AI
//  uses to look up its menu. The `MKMapItem` itself isn't kept (it isn't
//  Hashable or Sendable); `makeMapItem()` rebuilds one to open Apple Maps.
//

import CoreLocation
import Foundation
import MapKit

struct PlacesPlace: Hashable, Identifiable {
    var id: String
    var name: String
    var address: String?
    var latitude: Double
    var longitude: Double
    var phone: String?
    var url: URL?
    var categoryTitle: String?
    /// SF Symbol for the place's kind (fork and knife, coffee cup, cart...).
    var systemImage: String
    /// Meters from the person when the search ran, if their location was known.
    var distanceMeters: Double?
    /// What Haki's AI is asked about to find the menu.
    var query: FoodPlaceQuery

    init(
        id: String? = nil,
        name: String,
        address: String? = nil,
        latitude: Double,
        longitude: Double,
        phone: String? = nil,
        url: URL? = nil,
        categoryTitle: String? = nil,
        systemImage: String = "fork.knife",
        distanceMeters: Double? = nil,
        city: String? = nil,
        region: String? = nil,
        country: String? = nil
    ) {
        self.id = id ?? PlacesPlace.makeID(name: name, latitude: latitude, longitude: longitude)
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.phone = phone
        self.url = url
        self.categoryTitle = categoryTitle
        self.systemImage = systemImage
        self.distanceMeters = distanceMeters
        self.query = FoodPlaceQuery(
            placeName: name,
            address: address,
            city: city,
            region: region,
            country: country,
            latitude: latitude,
            longitude: longitude,
            website: url?.absoluteString
        )
    }

    /// Builds a place from an Apple Maps search result. `userLocation` (when
    /// known) sets the distance shown in the list and on the menu screen.
    init(mapItem: MKMapItem, userLocation: CLLocation?) {
        let placemark = mapItem.placemark
        let coordinate = placemark.coordinate
        let trimmedName = (mapItem.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = PlacesPlace.kind(for: mapItem.pointOfInterestCategory)

        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let addressParts = [street, placemark.locality ?? ""].filter { !$0.isEmpty }
        let address = addressParts.isEmpty ? nil : addressParts.joined(separator: ", ")

        var distance: Double?
        if let userLocation {
            let placeLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            distance = placeLocation.distance(from: userLocation)
        }

        let phone = mapItem.phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines)

        self.init(
            name: trimmedName.isEmpty ? "Unnamed place" : trimmedName,
            address: address,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            phone: (phone?.isEmpty ?? true) ? nil : phone,
            url: PlacesPlace.webURL(mapItem.url),
            categoryTitle: kind.title,
            systemImage: kind.systemImage,
            distanceMeters: distance,
            city: placemark.locality,
            region: placemark.administrativeArea,
            country: placemark.isoCountryCode
        )
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// "350 m" / "1.2 mi", in the person's units.
    var distanceText: String? {
        guard let distanceMeters, distanceMeters.isFinite, distanceMeters >= 0 else { return nil }
        return PlacesFormat.distance(distanceMeters)
    }

    /// "Restaurant · 350 m", or nil when neither is known.
    var detailLine: String? {
        let parts = [categoryTitle, distanceText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// A `tel:` link for the phone number, if there is one.
    var phoneURL: URL? {
        guard let phone else { return nil }
        let dialable = phone.filter { ($0.isASCII && $0.isNumber) || $0 == "+" }
        guard dialable.count >= 3 else { return nil }
        return URL(string: "tel:\(dialable)")
    }

    /// A fresh map item for Apple Maps (directions), with the name, phone and website.
    func makeMapItem() -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        item.phoneNumber = phone
        item.url = url
        return item
    }

    /// Opens Apple Maps with directions to the place.
    func openDirections() {
        let item = makeMapItem()
        _ = item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }

    // MARK: Helpers

    /// Same business at the same spot gets the same id across searches.
    private static func makeID(name: String, latitude: Double, longitude: Double) -> String {
        let key = name.lowercased().filter { $0.isLetter || $0.isNumber }
        return "\(key)|\(String(format: "%.5f", latitude)),\(String(format: "%.5f", longitude))"
    }

    /// Only web links (no other schemes) are offered as "Website".
    private static func webURL(_ url: URL?) -> URL? {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        return url
    }

    private static func kind(for category: MKPointOfInterestCategory?) -> (title: String?, systemImage: String) {
        guard let category else { return (nil, "fork.knife") }
        if category == .restaurant { return ("Restaurant", "fork.knife") }
        if category == .cafe { return ("Café", "cup.and.saucer.fill") }
        if category == .bakery { return ("Bakery", "birthday.cake.fill") }
        if category == .foodMarket { return ("Grocery store", "cart.fill") }
        if category == .brewery { return ("Brewery", "mug.fill") }
        if category == .winery { return ("Winery", "wineglass.fill") }
        return (nil, "mappin")
    }
}

extension PlacesPlace {
    /// A sample place for previews (matches `FoodAIPreviewSamples.menu`).
    static let preview = PlacesPlace(
        name: "Green Fork Kitchen",
        address: "214 Market St, San Francisco",
        latitude: 37.7925,
        longitude: -122.3969,
        phone: "+1 415 555 0142",
        url: URL(string: "https://example.com"),
        categoryTitle: "Restaurant",
        systemImage: "fork.knife",
        distanceMeters: 450,
        city: "San Francisco",
        region: "CA",
        country: "US"
    )
}

/// Formatting shared by the places screens.
enum PlacesFormat {
    private static let distanceFormatter: MKDistanceFormatter = {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        return formatter
    }()

    /// "350 m", "1.2 mi" — in the units the person's locale uses.
    static func distance(_ meters: Double) -> String {
        distanceFormatter.string(fromDistance: meters)
    }
}
