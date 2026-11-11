import Flutter
import UIKit
import CoreLocation

/// Foreground speed and user-initiated icon actions. Coordinates never cross the channel.
public final class PlatformFeaturesPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, CLLocationManagerDelegate {
  private let methods: FlutterMethodChannel
  private let events: FlutterEventChannel
  private let location = CLLocationManager()
  private var sink: FlutterEventSink?
  private var authorization: FlutterResult?
  private var observers: [NSObjectProtocol] = []
  private let presets = ["standard": "", "material": "IconMaterial", "midnight": "IconMidnight", "volt": "IconVolt"]

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = PlatformFeaturesPlugin(messenger: registrar.messenger())
    registrar.publish(instance)
  }

  private init(messenger: FlutterBinaryMessenger) {
    methods = FlutterMethodChannel(name: "escooter/platform", binaryMessenger: messenger)
    events = FlutterEventChannel(name: "escooter/phone_speed", binaryMessenger: messenger)
    super.init()
    location.delegate = self
    location.desiredAccuracy = kCLLocationAccuracyBest
    location.distanceFilter = kCLDistanceFilterNone
    location.activityType = .otherNavigation
    location.pausesLocationUpdatesAutomatically = false
    methods.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
    events.setStreamHandler(self)
    observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.location.stopUpdatingLocation() })
    observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.startLocation() })
  }
  deinit { observers.forEach(NotificationCenter.default.removeObserver); location.stopUpdatingLocation() }

  private func fail(_ result: FlutterResult, _ message: String) { result(FlutterError(code: "platform", message: message, details: nil)) }
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "authorizeLocation":
      switch location.authorizationStatus {
      case .authorizedWhenInUse, .authorizedAlways: result(nil)
      case .notDetermined:
        guard authorization == nil else { fail(result, "A location request is already open."); return }
        authorization = result
        location.requestWhenInUseAuthorization()
      default: fail(result, "Allow location access in Settings to use phone speed.")
      }
    case "iconInfo":
      let selected = UIApplication.shared.alternateIconName ?? ""
      result(["name": presets.first { $0.value == selected }?.key ?? "standard", "canChange": UIApplication.shared.supportsAlternateIcons])
    case "setIcon":
      guard let name = args["name"] as? String, let icon = presets[name], UIApplication.shared.supportsAlternateIcons else { fail(result, "This icon is unavailable on this device."); return }
      guard UIApplication.shared.applicationState == .active else { fail(result, "Return to the app before changing its icon."); return }
      let desired: String? = icon.isEmpty ? nil : icon
      if UIApplication.shared.alternateIconName == desired { result(nil); return }
      UIApplication.shared.setAlternateIconName(desired) { error in
        DispatchQueue.main.async { if let error = error { result(FlutterError(code: "icon", message: error.localizedDescription, details: nil)) } else { result(nil) } }
      }
    default: result(FlutterMethodNotImplemented)
    }
  }
  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    startLocation()
    return nil
  }
  public func onCancel(withArguments arguments: Any?) -> FlutterError? { location.stopUpdatingLocation(); sink = nil; return nil }
  private func startLocation() {
    guard sink != nil, UIApplication.shared.applicationState == .active else { return }
    guard CLLocationManager.locationServicesEnabled() else { sink?(FlutterError(code: "location_disabled", message: "Turn on Location Services for phone speed.", details: nil)); return }
    guard location.authorizationStatus == .authorizedWhenInUse || location.authorizationStatus == .authorizedAlways else { sink?(FlutterError(code: "location_permission", message: "Allow location access in phone settings.", details: nil)); return }
    location.startUpdatingLocation()
  }
  public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    switch manager.authorizationStatus {
    case .authorizedWhenInUse, .authorizedAlways:
      let reply = authorization; authorization = nil; reply?(nil); startLocation()
    case .denied, .restricted:
      location.stopUpdatingLocation()
      let error = FlutterError(code: "location_permission", message: "Allow location access in phone settings.", details: nil)
      let reply = authorization; authorization = nil; reply?(error); sink?(error)
    default: break
    }
  }
  public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard UIApplication.shared.applicationState == .active, let point = locations.last else { return }
    let accuracy: Any = point.speedAccuracy >= 0 ? point.speedAccuracy as Any : NSNull()
    sink?(["speed": point.speed, "speedAccuracy": accuracy, "accuracy": point.horizontalAccuracy, "ageMs": Int(Date().timeIntervalSince(point.timestamp) * 1000)])
  }
  public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    if let clError = error as? CLError, clError.code == .locationUnknown { return }
    sink?(FlutterError(code: "location", message: "Phone speed is unavailable. Check Location Services and try outdoors.", details: nil))
  }
}
