import MapKit
import SwiftUI

struct WayTaskMapView: UIViewRepresentable {
    let stores: [MapStore]
    let products: [MapProduct]
    let selectedStoreID: UUID?
    let cameraTarget: MKCoordinateRegion?
    let onSelectStore: (UUID) -> Void
    let onMapCenterChanged: (CLLocationCoordinate2D) -> Void
    let onUserLocationChanged: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.pointOfInterestFilter = .includingAll
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.storeReuseIdentifier)
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.productReuseIdentifier)
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        mapView.setRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 32.0853, longitude: 34.7818),
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            ),
            animated: false
        )
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyAnnotations(to: mapView)

        if let cameraTarget,
           !context.coordinator.isSameRegion(cameraTarget, as: context.coordinator.lastCameraTarget) {
            context.coordinator.lastCameraTarget = cameraTarget
            mapView.setRegion(cameraTarget, animated: true)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        static let storeReuseIdentifier = "StoreAnnotation"
        static let productReuseIdentifier = "ProductAnnotation"

        var parent: WayTaskMapView
        var lastCameraTarget: MKCoordinateRegion?

        init(_ parent: WayTaskMapView) {
            self.parent = parent
        }

        @MainActor
        func applyAnnotations(to mapView: MKMapView) {
            let existingAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
            mapView.removeAnnotations(existingAnnotations)
            mapView.removeOverlays(mapView.overlays)

            let storeAnnotations = parent.stores.map(StoreAnnotation.init(store:))
            let productAnnotations = parent.products.map(ProductAnnotation.init(product:))
            mapView.addAnnotations(storeAnnotations + productAnnotations)

            for store in parent.stores {
                let circle = MKCircle(center: store.coordinate, radius: store.radius)
                mapView.addOverlay(circle)
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.onMapCenterChanged(mapView.region.center)
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard let coordinate = userLocation.location?.coordinate else {
                return
            }

            parent.onUserLocationChanged(coordinate)
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let storeAnnotation = annotation as? StoreAnnotation {
                parent.onSelectStore(storeAnnotation.store.id)
                return
            }

            if let productAnnotation = annotation as? ProductAnnotation {
                parent.onSelectStore(productAnnotation.product.storeID)
                return
            }

            if let cluster = annotation as? MKClusterAnnotation {
                let region = MKCoordinateRegion(
                    center: cluster.coordinate,
                    span: MKCoordinateSpan(
                        latitudeDelta: max(mapView.region.span.latitudeDelta / 2, 0.002),
                        longitudeDelta: max(mapView.region.span.longitudeDelta / 2, 0.002)
                    )
                )
                mapView.setRegion(region, animated: true)
                mapView.deselectAnnotation(cluster, animated: false)
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }

            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier,
                    for: cluster
                ) as? MKMarkerAnnotationView
                view?.markerTintColor = .systemOrange
                view?.glyphText = "\(cluster.memberAnnotations.count)"
                view?.displayPriority = .required
                return view
            }

            if annotation is StoreAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: Self.storeReuseIdentifier,
                    for: annotation
                ) as? MKMarkerAnnotationView
                view?.canShowCallout = false
                view?.markerTintColor = .systemOrange
                view?.glyphImage = UIImage(systemName: "storefront.fill")
                view?.clusteringIdentifier = "stores"
                view?.displayPriority = .required
                return view
            }

            if annotation is ProductAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: Self.productReuseIdentifier,
                    for: annotation
                ) as? MKMarkerAnnotationView
                view?.canShowCallout = false
                view?.markerTintColor = .systemBlue
                view?.glyphImage = UIImage(systemName: "shippingbox.fill")
                view?.clusteringIdentifier = "products"
                view?.displayPriority = .defaultLow
                return view
            }

            return nil
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let circle = overlay as? MKCircle else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKCircleRenderer(circle: circle)
            renderer.fillColor = UIColor.systemOrange.withAlphaComponent(0.13)
            renderer.strokeColor = UIColor.systemOrange.withAlphaComponent(0.55)
            renderer.lineWidth = 1.5
            return renderer
        }

        func isSameRegion(_ lhs: MKCoordinateRegion, as rhs: MKCoordinateRegion?) -> Bool {
            guard let rhs else {
                return false
            }

            return abs(lhs.center.latitude - rhs.center.latitude) < 0.000001
                && abs(lhs.center.longitude - rhs.center.longitude) < 0.000001
                && abs(lhs.span.latitudeDelta - rhs.span.latitudeDelta) < 0.000001
                && abs(lhs.span.longitudeDelta - rhs.span.longitudeDelta) < 0.000001
        }
    }
}
