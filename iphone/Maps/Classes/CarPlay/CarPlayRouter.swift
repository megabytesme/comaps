import AVFoundation
import CarPlay
import Contacts

protocol CarPlayRouterListener: AnyObject {
  func didCreateRoute(routeInfo: RouteInfo,
                      trip: CPTrip)
  func didUpdateRouteInfo(_ routeInfo: RouteInfo, forTrip trip: CPTrip)
  func didFailureBuildRoute(forTrip trip: CPTrip, code: RouterResultCode, countries: [String])
  func routeDidFinish(_ trip: CPTrip)
}


@objc(MWMCarPlayRouter)
final class CarPlayRouter: NSObject {
  private let listenerContainer: ListenerContainer<CarPlayRouterListener>
  private var routeSession: CPNavigationSession?
  private var initialSpeedCamSettings: SpeedCameraManagerMode
  var currentTrip: CPTrip? {
    return routeSession?.trip
  }
  var previewTrip: CPTrip?
  var speedCameraMode: SpeedCameraManagerMode {
    return RoutingManager.routingManager.speedCameraMode
  }

  override init() {
    listenerContainer = ListenerContainer<CarPlayRouterListener>()
    initialSpeedCamSettings = RoutingManager.routingManager.speedCameraMode
    super.init()
  }

  func addListener(_ listener: CarPlayRouterListener) {
    listenerContainer.addListener(listener)
  }

  func removeListener(_ listener: CarPlayRouterListener) {
    listenerContainer.removeListener(listener)
  }

  func subscribeToEvents() {
    RoutingManager.routingManager.add(self)
  }

  func unsubscribeFromEvents() {
    RoutingManager.routingManager.remove(self)
  }

  func completeRouteAndRemovePoints() {
    let manager = RoutingManager.routingManager
    manager.stopRoutingAndRemoveRoutePoints(true)
    manager.deleteSavedRoutePoints()
    manager.apply(routeType: .vehicle)
    previewTrip = nil
  }

  func rebuildRoute() {
    guard let trip = previewTrip else { return }
    do {
      try RoutingManager.routingManager.buildRoute()
    } catch let error as NSError {
      listenerContainer.forEach({
        let code = RouterResultCode(rawValue: UInt(error.code)) ?? .internalError
        $0.didFailureBuildRoute(forTrip: trip, code: code, countries: [])
      })
    }
  }

  func buildRoute(trip: CPTrip) {
    completeRouteAndRemovePoints()
    previewTrip = trip
    guard let info = trip.userInfo as? [String: MWMRoutePoint] else {
      listenerContainer.forEach({
        $0.didFailureBuildRoute(forTrip: trip, code: .routeNotFound, countries: [])
      })
      return
    }
    guard let startPoint = info[CPConstants.Trip.start],
      let endPoint = info[CPConstants.Trip.end] else {
        listenerContainer.forEach({
          var code: RouterResultCode!
          if info[CPConstants.Trip.end] == nil {
            code = .endPointNotFound
          } else {
            code = .startPointNotFound
          }
          $0.didFailureBuildRoute(forTrip: trip, code: code, countries: [])
        })
        return
    }

    let manager = RoutingManager.routingManager
    manager.add(routePoint: startPoint)
    manager.add(routePoint: endPoint)

    do {
      try manager.buildRoute()
    } catch let error as NSError {
      listenerContainer.forEach({
        let code = RouterResultCode(rawValue: UInt(error.code)) ?? .internalError
        $0.didFailureBuildRoute(forTrip: trip, code: code, countries: [])
      })
    }
  }

  func updateStartPointAndRebuild(trip: CPTrip) {
    let manager = RoutingManager.routingManager
    previewTrip = trip
    guard let info = trip.userInfo as? [String: MWMRoutePoint] else {
      listenerContainer.forEach({
        $0.didFailureBuildRoute(forTrip: trip, code: .routeNotFound, countries: [])
      })
      return
    }
    guard let startPoint = info[CPConstants.Trip.start] else {
        listenerContainer.forEach({
          $0.didFailureBuildRoute(forTrip: trip, code: .startPointNotFound, countries: [])
        })
        return
    }
    manager.add(routePoint: startPoint)
    manager.apply(routeType: .vehicle)
    do {
      try manager.buildRoute()
    } catch let error as NSError {
      listenerContainer.forEach({
        let code = RouterResultCode(rawValue: UInt(error.code)) ?? .internalError
        $0.didFailureBuildRoute(forTrip: trip, code: code, countries: [])
      })
    }
  }

  func startRoute() {
    let manager = RoutingManager.routingManager
    manager.startRoute()
  }

  func setupCarPlaySpeedCameraMode() {
    if case .auto = initialSpeedCamSettings {
      RoutingManager.routingManager.speedCameraMode = .always
    }
  }

  func setupInitialSpeedCameraMode() {
    RoutingManager.routingManager.speedCameraMode = initialSpeedCamSettings
  }

  func updateSpeedCameraMode(_ mode: SpeedCameraManagerMode) {
    initialSpeedCamSettings = mode
    RoutingManager.routingManager.speedCameraMode = mode
  }

  func restoreTripPreviewOnCarplay(beforeRootTemplateDidAppear: Bool) {
    guard MWMRouter.isRestoreProcessCompleted() else {
      DispatchQueue.main.async { [weak self] in
        self?.restoreTripPreviewOnCarplay(beforeRootTemplateDidAppear: false)
      }
      return
    }
    let manager = RoutingManager.routingManager
    MWMRouter.hideNavigationMapControls()
    guard manager.isRoutingActive,
      let startPoint = manager.startPoint,
      let endPoint = manager.endPoint else {
        completeRouteAndRemovePoints()
        return
    }
    let trip = createTrip(startPoint: startPoint,
                          endPoint: endPoint,
                          routeInfo: manager.routeInfo)
    previewTrip = trip
    if manager.type != .vehicle {
      CarPlayService.shared.showRecoverRouteAlert(trip: trip, isTypeCorrect: false)
      return
    }
    if !startPoint.isMyPosition {
      CarPlayService.shared.showRecoverRouteAlert(trip: trip, isTypeCorrect: true)
      return
    }
    if beforeRootTemplateDidAppear {
      CarPlayService.shared.preparedToPreviewTrips = [trip]
    } else {
      CarPlayService.shared.preparePreview(trips: [trip])
    }
  }

  func restoredNavigationSession() -> (CPTrip, RouteInfo)? {
    let manager = RoutingManager.routingManager
    if manager.isOnRoute,
      manager.type == .vehicle,
      let startPoint = manager.startPoint,
      let endPoint = manager.endPoint,
      let routeInfo = manager.routeInfo {
      MWMRouter.hideNavigationMapControls()
      let trip = createTrip(startPoint: startPoint,
                            endPoint: endPoint,
                            routeInfo: routeInfo)
      previewTrip = trip
      return (trip, routeInfo)
    }
    return nil
  }
}

// MARK: - Navigation session management
extension CarPlayRouter {
  func startNavigationSession(forTrip trip: CPTrip, template: CPMapTemplate) {
    guard routeSession == nil else {
      let errorMessage = "Route session is already running."
      LOG(.error, errorMessage)
      Toast.show(withText: errorMessage, alignment: .top)
      return
    }
    LOG(.info, "Starting a new navigation session")
    routeSession = template.startNavigationSession(for: trip)
    routeSession?.pauseTrip(for: .loading, description: nil)
    updateUpcomingManeuvers()
    RoutingManager.routingManager.setOnNewTurnCallback { [weak self] in
      self?.updateUpcomingManeuvers()
    }
  }

  func cancelNavigationSession() {
    LOG(.info, "Cancelling navigation session")
    routeSession?.cancelTrip()
    routeSession = nil
    RoutingManager.routingManager.resetOnNewTurnCallback()
  }

  func cancelTrip() {
    LOG(.info, "Cancelling trip")
    cancelNavigationSession()
    completeRouteAndRemovePoints()
  }

  func finishTrip() {
    LOG(.info, "Finishing trip")
    routeSession?.finishTrip()
    routeSession = nil
    completeRouteAndRemovePoints()
    RoutingManager.routingManager.resetOnNewTurnCallback()
  }

  func updateUpcomingManeuvers() {
    let maneuvers = createUpcomingManeuvers()
    routeSession?.upcomingManeuvers = maneuvers
  }

  func updateEstimates() {
    guard let routeSession = routeSession,
          let routeInfo = RoutingManager.routingManager.routeInfo,
          let primaryManeuver = routeSession.upcomingManeuvers.first,
          let estimates = createEstimates(routeInfo) else {
      return
    }
    routeSession.updateEstimates(estimates, for: primaryManeuver)
  }

  private func createEstimates(_ routeInfo: RouteInfo) -> CPTravelEstimates? {
    let measurement = Measurement(value: routeInfo.distanceToTurn, unit: routeInfo.turnUnits)
    return CPTravelEstimates(distanceRemaining: measurement, timeRemaining: 0.0)
  }

  private func createUpcomingManeuvers() -> [CPManeuver] {
    guard let routeInfo = RoutingManager.routingManager.routeInfo else {
      return []
    }
    var maneuvers = [CPManeuver]()
    let primaryManeuver = CPManeuver()
    primaryManeuver.userInfo = CPConstants.Maneuvers.primary
    var instructionVariant = routeInfo.streetName
    if routeInfo.roundExitNumber != 0 {
      let ordinalExitNumber = NumberFormatter.localizedString(from: NSNumber(value: routeInfo.roundExitNumber),
                                                              number: .ordinal)
      let exitNumber = String(format: L("carplay_roundabout_exit"),
                              arguments: [ordinalExitNumber])
      instructionVariant = instructionVariant.isEmpty ? exitNumber : (exitNumber + ", " + instructionVariant)
    }
    primaryManeuver.instructionVariants = [instructionVariant]
    if let imageName = routeInfo.turnImageName,
      let symbol = UIImage(named: imageName) {
      primaryManeuver.symbolImage = symbol
    }
    if let estimates = createEstimates(routeInfo) {
      primaryManeuver.initialTravelEstimates = estimates
    }
    // Lane guidance for the instrument cluster / any surface that consumes it (not the app screen).
    if #available(iOS 18.0, *), !routeInfo.lanes.isEmpty {
      primaryManeuver.linkedLaneGuidance = laneGuidance(for: routeInfo)
    }
    maneuvers.append(primaryManeuver)
    // Lanes must always be the second maneuver supplied to CarPlay, per Developer guidance 2026
    // https://developer.apple.com/download/files/CarPlay-Developer-Guide.pdf
    if !routeInfo.lanes.isEmpty, let laneImages = laneImageSet(for: routeInfo.lanes) {
      let laneManeuver = CPManeuver()
      laneManeuver.userInfo = CPConstants.Maneuvers.lanes
      laneManeuver.instructionVariants = []
      laneManeuver.symbolSet = laneImages
      maneuvers.append(laneManeuver)
    }
    // Always provide the next upcoming turn, as you should provide as many meaneuvers as possible
    if let imageName = routeInfo.nextTurnImageName,
      let symbol = UIImage(named: imageName) {
      let secondaryManeuver = CPManeuver()
      secondaryManeuver.userInfo = CPConstants.Maneuvers.secondary
      secondaryManeuver.instructionVariants = [L("then_turn")]
      secondaryManeuver.symbolImage = symbol
      maneuvers.append(secondaryManeuver)
    }
    return maneuvers
  }

  /// Lane strip for the symbol-only second maneuver, as a `CPImageSet`.
  /// The guidance card is a fixed dark green (`guidanceBackgroundColor`) in both CarPlay light and
  /// dark modes, so white glyphs are used for both image variants to match the white card text.
  private func laneImageSet(for lanes: [LaneInfo]) -> CPImageSet? {
    guard !lanes.isEmpty, let image = laneStripImage(for: lanes, tint: .white) else {
      return nil
    }
    return CPImageSet(lightContentImage: image, darkContentImage: image)
  }

  /// Draws the upcoming turn's lanes as one horizontal strip, centered in a 120x18pt canvas (max per Apple).
  /// The recommended lane(s) use `tint` at full opacity; others are dimmed, mirroring Android.
  private func laneStripImage(for lanes: [LaneInfo], tint: UIColor) -> UIImage? {
    guard !lanes.isEmpty else { return nil }
    let maxWidth: CGFloat = 120
    let height: CGFloat = 18
    let count = CGFloat(lanes.count)
    let cell = min(height, maxWidth / count)
    let xOffset = (maxWidth - cell * count) / 2
    let config = UIImage.SymbolConfiguration(pointSize: cell * 0.85, weight: .semibold)
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: maxWidth, height: height))
    return renderer.image { _ in
      for (i, lane) in lanes.enumerated() {
        let recommended = LaneWay(rawValue: lane.recommendedWay)
        let isActive = recommended != nil && recommended != LaneWay.none
        let way = isActive ? recommended!
          : (lane.laneWays.compactMap { LaneWay(rawValue: $0) }.first ?? .through)
        let color = isActive ? tint : tint.withAlphaComponent(0.38)
        guard let symbol = UIImage(systemName: way.symbolName, withConfiguration: config)?
          .withTintColor(color, renderingMode: .alwaysOriginal) else { continue }
        let cellRect = CGRect(x: xOffset + CGFloat(i) * cell, y: 0, width: cell, height: height)
        symbol.draw(in: AVMakeRect(aspectRatio: symbol.size, insideRect: cellRect))
      }
    }
  }

  @available(iOS 18.0, *)
  private func laneGuidance(for routeInfo: RouteInfo) -> CPLaneGuidance {
    let guidance = CPLaneGuidance()
    guidance.lanes = routeInfo.lanes.map { lane in
      let angles = lane.laneWays.compactMap { LaneWay(rawValue: $0)?.angle }
      // CPLane requires at least one angle; fall back to "straight" for unmarked lanes.
      let safeAngles = angles.isEmpty ? [Measurement(value: 0, unit: UnitAngle.degrees)] : angles
      if let recommended = LaneWay(rawValue: lane.recommendedWay), recommended != .none {
        return CPLane(angles: safeAngles, highlightedAngle: recommended.angle, isPreferred: true)
      }
      return CPLane(angles: safeAngles)
    }
    guidance.instructionVariants = [routeInfo.streetName]
    return guidance
  }

  func createTrip(startPoint: MWMRoutePoint, endPoint: MWMRoutePoint, routeInfo: RouteInfo? = nil) -> CPTrip {
    let startPlacemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: startPoint.latitude,
                                                                        longitude: startPoint.longitude))
    let endPlacemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: endPoint.latitude,
                                                                      longitude: endPoint.longitude),
                                   addressDictionary: [CNPostalAddressStreetKey: endPoint.subtitle ?? ""])
    let startItem = MKMapItem(placemark: startPlacemark)
    let endItem = MKMapItem(placemark: endPlacemark)
    endItem.name = endPoint.title

    let routeChoice = CPRouteChoice(summaryVariants: [" "], additionalInformationVariants: [], selectionSummaryVariants: [])
    routeChoice.userInfo = routeInfo

    let trip = CPTrip(origin: startItem, destination: endItem, routeChoices: [routeChoice])
    trip.userInfo = [CPConstants.Trip.start: startPoint, CPConstants.Trip.end: endPoint]
    return trip
  }
}

// MARK: - RoutingManagerListener implementation
extension CarPlayRouter: RoutingManagerListener {
  func updateCameraInfo(isCameraOnRoute: Bool, speedLimitMps limit: Double) {
    CarPlayService.shared.updateCameraUI(isCameraOnRoute: isCameraOnRoute, speedLimitMps: limit < 0 ? nil : limit)
  }

  func processRouteBuilderEvent(with code: RouterResultCode, countries: [String]) {
    guard let trip = previewTrip else {
      return
    }
    switch code {
    case .noError, .hasWarnings:
      let manager = RoutingManager.routingManager
      if manager.isRouteFinished {
        listenerContainer.forEach({
          $0.routeDidFinish(trip)
        })
        return
      }
      if let info = manager.routeInfo {
        previewTrip?.routeChoices.first?.userInfo = info
        if routeSession == nil {
          listenerContainer.forEach({
            $0.didCreateRoute(routeInfo: info,
                              trip: trip)
          })
        } else {
          listenerContainer.forEach({
            $0.didUpdateRouteInfo(info, forTrip: trip)
          })
          updateUpcomingManeuvers()
        }
      }
    default:
      listenerContainer.forEach({
        $0.didFailureBuildRoute(forTrip: trip, code: code, countries: countries)
      })
    }
  }

  func didLocationUpdate(_ notifications: [String]) {
    guard let trip = previewTrip else { return }

    let manager = RoutingManager.routingManager
    if manager.isRouteFinished {
      listenerContainer.forEach({
        $0.routeDidFinish(trip)
      })
      return
    }

    guard let routeInfo = manager.routeInfo,
      manager.isRoutingActive else { return }
    listenerContainer.forEach({
      $0.didUpdateRouteInfo(routeInfo, forTrip: trip)
    })

    let tts = MWMTextToSpeech.tts()!
    if manager.isOnRoute && tts.active {
      tts.playTurnNotifications(notifications)
      tts.playWarningSound()
    }
  }
}
