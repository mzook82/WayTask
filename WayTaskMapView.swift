import MapKit
import SwiftUI

struct WayTaskMapView: UIViewRepresentable, Equatable {
    let stores: [MapStore]
    let products: [MapProduct]
    let cameraTarget: MKCoordinateRegion?
    var cameraRequestID = 0
    var cameraShouldAnimate = true
    let onSelectStore: (UUID) -> Void
    var onClearSelection: () -> Void = {}
    let onMapRegionChanged: (MKCoordinateRegion) -> Void
    let onUserLocationChanged: (CLLocationCoordinate2D) -> Void
    var onUserLocationReceived: (CLLocation) -> Void = { _ in }
    var onUserMapInteraction: () -> Void = {}

    static func == (lhs: Self, rhs: Self) -> Bool {
        AnnotationSignature(
            stores: lhs.stores,
            products: ShoppingMissionMapMarkerPolicy.renderedProducts(
                storeIDs: Set(lhs.stores.map(\.id)),
                products: lhs.products
            )
        ) == AnnotationSignature(
            stores: rhs.stores,
            products: ShoppingMissionMapMarkerPolicy.renderedProducts(
                storeIDs: Set(rhs.stores.map(\.id)),
                products: rhs.products
            )
        )
            && MapRegionSignature(lhs.cameraTarget)
                == MapRegionSignature(rhs.cameraTarget)
            && lhs.cameraRequestID == rhs.cameraRequestID
            && lhs.cameraShouldAnimate == rhs.cameraShouldAnimate
    }

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
        let backgroundTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMapBackgroundTap(_:))
        )
        backgroundTap.cancelsTouchesInView = false
        backgroundTap.delegate = context.coordinator
        mapView.addGestureRecognizer(backgroundTap)
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
        context.coordinator.updateAnnotationsIfNeeded(on: mapView)

        if let cameraTarget,
           context.coordinator.lastCameraRequestID != cameraRequestID
            || !context.coordinator.isSameRegion(
                cameraTarget,
                as: context.coordinator.lastCameraTarget
            ) {
            context.coordinator.lastCameraTarget = cameraTarget
            context.coordinator.lastCameraRequestID = cameraRequestID
            mapView.setRegion(
                cameraTarget,
                animated: cameraShouldAnimate
            )
        }
    }

    final class Coordinator:
        NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        static let storeReuseIdentifier = "StoreAnnotation"
        static let productReuseIdentifier = "ProductAnnotation"

        var parent: WayTaskMapView
        var lastCameraTarget: MKCoordinateRegion?
        var lastCameraRequestID: Int?
        private var lastAnnotationSignature: AnnotationSignature?
        private var lastOverlaySignature: OverlaySignature?

        #if DEBUG
        private var updateUIViewCount = 0
        private var annotationRebuildCount = 0
        private var skippedIdenticalUpdateCount = 0
        #endif

        init(_ parent: WayTaskMapView) {
            self.parent = parent
        }

        @MainActor
        func updateAnnotationsIfNeeded(on mapView: MKMapView) {
            #if DEBUG
            updateUIViewCount += 1
            #endif

            let renderedProducts = ShoppingMissionMapMarkerPolicy
                .renderedProducts(
                    storeIDs: Set(parent.stores.map(\.id)),
                    products: parent.products
                )
            let signature = AnnotationSignature(
                stores: parent.stores,
                products: renderedProducts
            )
            guard signature != lastAnnotationSignature else {
                #if DEBUG
                skippedIdenticalUpdateCount += 1
                logCountersIfNeeded()
                #endif
                return
            }

            lastAnnotationSignature = signature
            #if DEBUG
            annotationRebuildCount += 1
            logCountersIfNeeded()
            #endif

            reconcileAnnotations(
                on: mapView,
                stores: parent.stores,
                products: renderedProducts
            )

            let overlaySignature = OverlaySignature(stores: parent.stores)
            if lastOverlaySignature != overlaySignature {
                lastOverlaySignature = overlaySignature
                mapView.removeOverlays(mapView.overlays)
                for store in parent.stores {
                    let circle = MKCircle(
                        center: store.coordinate,
                        radius: store.proximityRadius
                    )
                    mapView.addOverlay(circle)
                }
            }
        }

        @MainActor
        private func reconcileAnnotations(
            on mapView: MKMapView,
            stores: [MapStore],
            products: [MapProduct]
        ) {
            let desiredStores = Dictionary(
                uniqueKeysWithValues: stores.map {
                    ($0.id, StoreAnnotationSignature($0))
                }
            )
            let desiredProducts = Dictionary(
                uniqueKeysWithValues: products.map {
                    ($0.id, ProductAnnotationSignature($0))
                }
            )
            var retainedStoreIDs = Set<UUID>()
            var retainedProductIDs = Set<UUID>()
            var removals: [MKAnnotation] = []

            for annotation in mapView.annotations {
                if let store = annotation as? StoreAnnotation {
                    let id = store.store.id
                    if desiredStores[id] == StoreAnnotationSignature(store.store),
                       retainedStoreIDs.insert(id).inserted {
                        continue
                    }
                    removals.append(annotation)
                } else if let product = annotation as? ProductAnnotation {
                    let id = product.product.id
                    if desiredProducts[id]
                        == ProductAnnotationSignature(product.product),
                       retainedProductIDs.insert(id).inserted {
                        continue
                    }
                    removals.append(annotation)
                }
            }
            if !removals.isEmpty { mapView.removeAnnotations(removals) }

            let newStoreAnnotations = stores.compactMap { store in
                retainedStoreIDs.contains(store.id)
                    ? nil : StoreAnnotation(store: store)
            }
            let newProductAnnotations = products.compactMap { product in
                retainedProductIDs.contains(product.id)
                    ? nil : ProductAnnotation(product: product)
            }
            if !newStoreAnnotations.isEmpty || !newProductAnnotations.isEmpty {
                var additions: [MKAnnotation] = newStoreAnnotations
                additions.append(contentsOf: newProductAnnotations)
                mapView.addAnnotations(additions)
            }
        }

        #if DEBUG
        private func logCountersIfNeeded() {
            guard updateUIViewCount == 1 || updateUIViewCount.isMultiple(of: 25) else {
                return
            }

            print("[WayTask Map Performance] updateUIView=\(updateUIViewCount) annotationRebuilds=\(annotationRebuildCount) skippedIdentical=\(skippedIdenticalUpdateCount)")
        }
        #endif

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.onMapRegionChanged(mapView.region)
        }

        func mapView(
            _ mapView: MKMapView,
            regionWillChangeAnimated animated: Bool
        ) {
            let userInitiated = mapView.gestureRecognizers?.contains {
                $0.state == .began || $0.state == .changed
            } == true
            if userInitiated { parent.onUserMapInteraction() }
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard let location = userLocation.location else {
                return
            }

            parent.onUserLocationChanged(location.coordinate)
            parent.onUserLocationReceived(location)
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let storeAnnotation = annotation as? StoreAnnotation {
                parent.onSelectStore(storeAnnotation.store.id)
                mapView.deselectAnnotation(annotation, animated: false)
                return
            }

            if let productAnnotation = annotation as? ProductAnnotation {
                parent.onSelectStore(productAnnotation.product.storeID)
                mapView.deselectAnnotation(annotation, animated: false)
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

        @objc func handleMapBackgroundTap(
            _ recognizer: UITapGestureRecognizer
        ) {
            guard recognizer.state == .ended else { return }
            parent.onClearSelection()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            var touchedView: UIView? = touch.view
            while let current = touchedView {
                if current is MKAnnotationView { return false }
                touchedView = current.superview
            }
            return true
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

private struct AnnotationSignature: Equatable {
    let stores: [StoreAnnotationSignature]
    let products: [ProductAnnotationSignature]

    @MainActor
    init(stores: [MapStore], products: [MapProduct]) {
        self.stores = stores.map(StoreAnnotationSignature.init).sorted {
            $0.id.uuidString < $1.id.uuidString
        }
        self.products = products.map(ProductAnnotationSignature.init).sorted {
            $0.id.uuidString < $1.id.uuidString
        }
    }
}

private struct OverlaySignature: Equatable {
    let stores: [StoreOverlaySignature]

    @MainActor
    init(stores: [MapStore]) {
        self.stores = stores.map(StoreOverlaySignature.init).sorted {
            $0.id.uuidString < $1.id.uuidString
        }
    }
}

private struct StoreOverlaySignature: Equatable {
    let id: UUID
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    let radius: CLLocationDistance

    init(_ store: MapStore) {
        id = store.id
        latitude = store.coordinate.latitude
        longitude = store.coordinate.longitude
        radius = store.proximityRadius
    }
}

private struct MapRegionSignature: Equatable {
    let latitude: CLLocationDegrees?
    let longitude: CLLocationDegrees?
    let latitudeDelta: CLLocationDegrees?
    let longitudeDelta: CLLocationDegrees?

    init(_ region: MKCoordinateRegion?) {
        latitude = region?.center.latitude
        longitude = region?.center.longitude
        latitudeDelta = region?.span.latitudeDelta
        longitudeDelta = region?.span.longitudeDelta
    }
}

private struct StoreAnnotationSignature: Equatable {
    let id: UUID
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    let radius: CLLocationDistance
    let title: String

    init(_ store: MapStore) {
        id = store.id
        latitude = store.coordinate.latitude
        longitude = store.coordinate.longitude
        radius = store.radius
        title = store.title
    }
}

private struct ProductAnnotationSignature: Equatable {
    let id: UUID
    let storeID: UUID
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    let name: String

    init(_ product: MapProduct) {
        id = product.id
        storeID = product.storeID
        latitude = product.coordinate.latitude
        longitude = product.coordinate.longitude
        name = product.name
    }
}
