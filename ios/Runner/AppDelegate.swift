import Flutter
import UIKit
import GoogleMaps
import google_mobile_ads

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var eventSink: FlutterEventSink?
  private let suiteName = "group.com.answer.app"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsApiKey") as? String {
      GMSServices.provideAPIKey(apiKey)
    }

    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    if let registrar = self.registrar(forPlugin: "MessengerAppPlugin") {
      let messenger = registrar.messenger()

      let shareChannel = FlutterMethodChannel(
        name: "com.answer.messenger/share",
        binaryMessenger: messenger
      )
      let eventChannel = FlutterEventChannel(
        name: "com.answer.messenger/share_events",
        binaryMessenger: messenger
      )

      shareChannel.setMethodCallHandler({ [weak self]
        (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
        guard let self = self else { return }
        if call.method == "getInitialSharedPayload" {
          result(self.getSharedPayload())
        } else if call.method == "clearSharedPayload" {
          self.clearSharedPayload()
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      })

      eventChannel.setStreamHandler(self)
    }

    return result
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.scheme == "messenger-share" {
      if let payload = getSharedPayload() {
        eventSink?(payload)
      }
      return true
    }
    return super.application(app, open: url, options: options)
  }

  private func getSharedPayload() -> [String: Any]? {
    if let userDefaults = UserDefaults(suiteName: suiteName) {
      return userDefaults.dictionary(forKey: "incoming_share_payload")
    }
    return nil
  }

  private func clearSharedPayload() {
    if let userDefaults = UserDefaults(suiteName: suiteName) {
      userDefaults.removeObject(forKey: "incoming_share_payload")
      userDefaults.synchronize()
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let factory = ListTileNativeAdFactory()
    FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
      engineBridge.pluginRegistry,
      factoryId: "listTile",
      nativeAdFactory: factory
    )
  }
}

extension AppDelegate: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }
}

class ListTileNativeAdFactory: NSObject, FLTNativeAdFactory {
  func createNativeAd(_ nativeAd: NativeAd, customOptions: [AnyHashable : Any]? = nil) -> NativeAdView? {
    let adView = NativeAdView()

    adView.translatesAutoresizingMaskIntoConstraints = false
    adView.heightAnchor.constraint(equalToConstant: 120).isActive = true

    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false
    adView.addSubview(container)
    NSLayoutConstraint.activate([
      container.topAnchor.constraint(equalTo: adView.topAnchor, constant: 0),
      container.bottomAnchor.constraint(equalTo: adView.bottomAnchor, constant: 0),
      container.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 12),
      container.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -12)
    ])

    let iconView = UIImageView()
    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.layer.cornerRadius = 20
    iconView.clipsToBounds = true
    iconView.backgroundColor = UIColor(red: 243/255.0, green: 222/255.0, blue: 218/255.0, alpha: 1.0)
    iconView.contentMode = .scaleAspectFill
    container.addSubview(iconView)
    NSLayoutConstraint.activate([
      iconView.widthAnchor.constraint(equalToConstant: 40),
      iconView.heightAnchor.constraint(equalToConstant: 40),
      iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor)
    ])
    adView.iconView = iconView

    let ctaButton = UIButton(type: .system)
    ctaButton.translatesAutoresizingMaskIntoConstraints = false
    ctaButton.backgroundColor = UIColor(red: 243/255.0, green: 222/255.0, blue: 218/255.0, alpha: 1.0)
    ctaButton.setTitleColor(UIColor(red: 58/255.0, green: 9/255.0, blue: 9/255.0, alpha: 1.0), for: .normal)
    ctaButton.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
    ctaButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
    ctaButton.layer.cornerRadius = 15
    ctaButton.layer.masksToBounds = true
    ctaButton.isUserInteractionEnabled = false
    container.addSubview(ctaButton)
    NSLayoutConstraint.activate([
      ctaButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      ctaButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      ctaButton.heightAnchor.constraint(equalToConstant: 28),
      ctaButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 52)
    ])
    adView.callToActionView = ctaButton

    let adChoicesView = AdChoicesView()
    adChoicesView.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(adChoicesView)
    NSLayoutConstraint.activate([
      adChoicesView.topAnchor.constraint(equalTo: container.topAnchor),
      adChoicesView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      adChoicesView.widthAnchor.constraint(equalToConstant: 16),
      adChoicesView.heightAnchor.constraint(equalToConstant: 16)
    ])
    adView.adChoicesView = adChoicesView

    adView.clipsToBounds = false
    container.clipsToBounds = false

    let mediaView = GADMediaView()
    mediaView.translatesAutoresizingMaskIntoConstraints = false
    mediaView.alpha = 0.0
    container.addSubview(mediaView)
    container.sendSubviewToBack(mediaView)
    NSLayoutConstraint.activate([
      mediaView.widthAnchor.constraint(equalToConstant: 120),
      mediaView.heightAnchor.constraint(equalToConstant: 120),
      mediaView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 0),
      mediaView.topAnchor.constraint(equalTo: container.topAnchor, constant: 0)
    ])
    adView.mediaView = mediaView

    let vStack = UIStackView()
    vStack.axis = .vertical
    vStack.translatesAutoresizingMaskIntoConstraints = false
    vStack.spacing = 1
    container.addSubview(vStack)
    NSLayoutConstraint.activate([
      vStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
      vStack.trailingAnchor.constraint(equalTo: ctaButton.leadingAnchor, constant: -10),
      vStack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
    ])

    let headlineView = UILabel()
    headlineView.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
    headlineView.textColor = UIColor(red: 26/255.0, green: 10/255.0, blue: 10/255.0, alpha: 1.0)
    headlineView.numberOfLines = 1
    headlineView.lineBreakMode = .byTruncatingTail
    headlineView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    vStack.addArrangedSubview(headlineView)
    adView.headlineView = headlineView

    let hStack = UIStackView()
    hStack.axis = .horizontal
    hStack.spacing = 4
    hStack.alignment = .center
    vStack.addArrangedSubview(hStack)

    let badgeView = UILabel()
    badgeView.font = UIFont.boldSystemFont(ofSize: 10)
    badgeView.backgroundColor = UIColor(red: 240/255.0, green: 222/255.0, blue: 218/255.0, alpha: 1.0)
    badgeView.textColor = UIColor(red: 58/255.0, green: 9/255.0, blue: 9/255.0, alpha: 1.0)
    let adLabel = customOptions?["adLabel"] as? String ?? "Ad"
    badgeView.text = " \(adLabel) "
    badgeView.layer.masksToBounds = true
    badgeView.layer.cornerRadius = 8
    hStack.addArrangedSubview(badgeView)

    let bodyView = UILabel()
    bodyView.font = UIFont.systemFont(ofSize: 11)
    bodyView.textColor = UIColor(red: 92/255.0, green: 64/255.0, blue: 64/255.0, alpha: 0.78)
    bodyView.numberOfLines = 1
    bodyView.lineBreakMode = .byTruncatingTail
    bodyView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    hStack.addArrangedSubview(bodyView)
    adView.bodyView = bodyView

    (adView.headlineView as? UILabel)?.text = nativeAd.headline
    (adView.bodyView as? UILabel)?.text = nativeAd.body
    (adView.callToActionView as? UIButton)?.setTitle(nativeAd.callToAction, for: .normal)
    (adView.iconView as? UIImageView)?.image = nativeAd.icon?.image

    adView.callToActionView?.isHidden = nativeAd.callToAction == nil
    adView.iconView?.isHidden = nativeAd.icon == nil
    adView.bodyView?.isHidden = nativeAd.body == nil

    adView.nativeAd = nativeAd
    return adView
  }
}
