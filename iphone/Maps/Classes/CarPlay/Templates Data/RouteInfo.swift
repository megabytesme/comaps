/// Possible direction of a single navigation lane.
///
/// > Warning: Raw values MUST match the native ``routing::turns::lanes::LaneWay`` enum
/// > (see libs/routing/lanes/lane_way.hpp for details).
enum LaneWay: UInt8 {
  case none = 0
  case reverseLeft
  case sharpLeft
  case left
  case mergeToLeft
  case slightLeft
  case through
  case slightRight
  case mergeToRight
  case right
  case sharpRight
  case reverseRight

  /// Direction of the lane as a CarPlay angle.
  ///
  /// 0 degrees points straight ahead, negative values turn left and positive values turn right.
  /// Angles from https://developer.apple.com/download/files/CarPlay-Developer-Guide.pdf
  var angle: Measurement<UnitAngle> {
    let degrees: Double
    switch self {
    case .none, .through: degrees = 0
    case .slightLeft, .mergeToLeft: degrees = -45
    case .left: degrees = -90
    case .sharpLeft: degrees = -135
    case .reverseLeft: degrees = -180
    case .slightRight, .mergeToRight: degrees = 45
    case .right: degrees = 90
    case .sharpRight: degrees = 135
    case .reverseRight: degrees = 180
    }
    return Measurement(value: degrees, unit: .degrees)
  }

  /// SF Symbol used to draw this lane direction in the CarPlay lane strip.
  /// Approximate: sharp/normal turns share a glyph
  var symbolName: String {
    switch self {
    case .none, .through: return "arrow.up"
    case .slightLeft, .mergeToLeft: return "arrow.up.left"
    case .left, .sharpLeft: return "arrow.turn.up.left"
    case .reverseLeft: return "arrow.uturn.left"
    case .slightRight, .mergeToRight: return "arrow.up.right"
    case .right, .sharpRight: return "arrow.turn.up.right"
    case .reverseRight: return "arrow.uturn.right"
    }
  }
}

/// A single navigation lane: the directions it allows and, optionally, the recommended one.
@objc(MWMLaneInfo)
final class LaneInfo: NSObject {
  /// Directions this lane allows, as ``LaneWay`` raw values.
  let laneWays: [UInt8]
  /// Recommended direction (``LaneWay/none`` raw value when this lane is not recommended).
  let recommendedWay: UInt8

  @objc init(laneWays: [NSNumber], recommendedWay: UInt8) {
    self.laneWays = laneWays.map { $0.uint8Value }
    self.recommendedWay = recommendedWay
  }
}

@objc(MWMRouteInfo)
class RouteInfo: NSObject {
  let timeToTarget: TimeInterval
  let targetDistance: Double
  let targetUnits: UnitLength
  let distanceToTurn: Double
  let turnUnits: UnitLength
  let streetName: String
  let turnImageName: String?
  let nextTurnImageName: String?
  let speedMps: Double
  let speedLimitMps: Double?
  let roundExitNumber: Int
  let lanes: [LaneInfo]

  @objc init(timeToTarget: TimeInterval,
             targetDistance: Double,
             targetUnitsIndex: UInt8,
             distanceToTurn: Double,
             turnUnitsIndex: UInt8,
             streetName: String,
             turnImageName: String?,
             nextTurnImageName: String?,
             speedMps: Double,
             speedLimitMps: Double,
             roundExitNumber: Int,
             lanes: [LaneInfo]) {
    self.timeToTarget = timeToTarget
    self.targetDistance = targetDistance
    self.targetUnits = RouteInfo.unitLength(for: targetUnitsIndex)
    self.distanceToTurn = distanceToTurn
    self.turnUnits = RouteInfo.unitLength(for: turnUnitsIndex)
    self.streetName = streetName;
    self.turnImageName = turnImageName
    self.nextTurnImageName = nextTurnImageName
    self.speedMps = speedMps
    // speedLimitMps >= 0 means known limited speed.
    self.speedLimitMps = speedLimitMps < 0 ? nil : speedLimitMps
    self.roundExitNumber = roundExitNumber
    self.lanes = lanes
  }


  /// > Warning: Order of enum values MUST BE the same with
  /// > native ``Distance::Units`` enum (see platform/distance.hpp for details).
  class func unitLength(for targetUnitsIndex: UInt8) -> UnitLength {
    switch targetUnitsIndex {
    case 0:
      return .meters
    case 1:
      return .kilometers
    case 2:
      return .feet
    case 3:
      return .miles
    default:
      return .meters
    }
  }
}
