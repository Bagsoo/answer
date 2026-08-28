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

    let groupFactory = GroupCardNativeAdFactory()
    FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
      engineBridge.pluginRegistry,
      factoryId: "groupTile",
      nativeAdFactory: groupFactory
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

    let mediaView = MediaView()
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

class GroupCardNativeAdFactory: NSObject, FLTNativeAdFactory {
  func createNativeAd(_ nativeAd: NativeAd, customOptions: [AnyHashable : Any]? = nil) -> NativeAdView? {
    let adView = NativeAdView()
    let isDark = (customOptions?["themeBrightness"] as? String) == "dark"
    let bgColor = isDark
      ? UIColor(red: 42/255.0, green: 32/255.0, blue: 30/255.0, alpha: 1.0)
      : UIColor(red: 255/255.0, green: 252/255.0, blue: 250/255.0, alpha: 1.0)
    let borderColor = isDark
      ? UIColor(white: 1.0, alpha: 0.16)
      : UIColor(white: 0.0, alpha: 0.07)
    let iconBg = isDark
      ? UIColor(red: 74/255.0, green: 55/255.0, blue: 51/255.0, alpha: 1.0)
      : UIColor(red: 244/255.0, green: 225/255.0, blue: 220/255.0, alpha: 1.0)
    let attributionBg = isDark
      ? UIColor(red: 74/255.0, green: 55/255.0, blue: 51/255.0, alpha: 1.0)
      : UIColor(red: 234/255.0, green: 221/255.0, blue: 212/255.0, alpha: 1.0)
    let attributionText = isDark
      ? UIColor(red: 250/255.0, green: 240/255.0, blue: 235/255.0, alpha: 1.0)
      : UIColor(red: 107/255.0, green: 43/255.0, blue: 30/255.0, alpha: 1.0)
    let headlineText = isDark
      ? UIColor(red: 255/255.0, green: 246/255.0, blue: 241/255.0, alpha: 1.0)
      : UIColor(red: 35/255.0, green: 24/255.0, blue: 21/255.0, alpha: 1.0)
    let bodyText = isDark
      ? UIColor(red: 244/255.0, green: 231/255.0, blue: 225/255.0, alpha: 0.82)
      : UIColor(red: 35/255.0, green: 24/255.0, blue: 21/255.0, alpha: 0.6)
    let ctaBg = isDark
      ? UIColor(red: 99/255.0, green: 74/255.0, blue: 67/255.0, alpha: 1.0)
      : UIColor(red: 230/255.0, green: 203/255.0, blue: 184/255.0, alpha: 1.0)
    let ctaText = isDark
      ? UIColor(red: 255/255.0, green: 249/255.0, blue: 246/255.0, alpha: 1.0)
      : UIColor(red: 74/255.0, green: 24/255.0, blue: 14/255.0, alpha: 1.0)

    adView.translatesAutoresizingMaskIntoConstraints = false
    adView.heightAnchor.constraint(equalToConstant: 152).isActive = true

    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false
    container.backgroundColor = bgColor
    container.layer.cornerRadius = 22
    container.layer.borderWidth = 1
    container.layer.borderColor = borderColor.cgColor
    adView.addSubview(container)
    NSLayoutConstraint.activate([
      container.topAnchor.constraint(equalTo: adView.topAnchor, constant: 0),
      container.bottomAnchor.constraint(equalTo: adView.bottomAnchor, constant: 0),
      container.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 0),
      container.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: 0)
    ])

    let iconView = UIImageView()
    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.layer.cornerRadius = 22
    iconView.clipsToBounds = true
    iconView.backgroundColor = iconBg
    iconView.contentMode = .scaleAspectFill
    container.addSubview(iconView)
    NSLayoutConstraint.activate([
      iconView.widthAnchor.constraint(equalToConstant: 44),
      iconView.heightAnchor.constraint(equalToConstant: 44),
      iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
      iconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 14)
    ])
    adView.iconView = iconView

    let adChoicesView = AdChoicesView()
    adChoicesView.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(adChoicesView)
    NSLayoutConstraint.activate([
      adChoicesView.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
      adChoicesView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
      adChoicesView.widthAnchor.constraint(equalToConstant: 16),
      adChoicesView.heightAnchor.constraint(equalToConstant: 16)
    ])
    adView.adChoicesView = adChoicesView

    let headline = UILabel()
    headline.translatesAutoresizingMaskIntoConstraints = false
    headline.font = UIFont.systemFont(ofSize: 16, weight: .bold)
    headline.textColor = headlineText
    headline.numberOfLines = 1
    container.addSubview(headline)
    NSLayoutConstraint.activate([
      headline.topAnchor.constraint(equalTo: iconView.topAnchor),
      headline.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
      headline.trailingAnchor.constraint(lessThanOrEqualTo: adChoicesView.leadingAnchor, constant: -8)
    ])
    adView.headlineView = headline

    let attribution = PaddingLabel()
    attribution.translatesAutoresizingMaskIntoConstraints = false
    attribution.text = (customOptions?["adLabel"] as? String) ?? "Ad"
    attribution.textColor = attributionText
    attribution.backgroundColor = attributionBg
    attribution.font = UIFont.systemFont(ofSize: 9, weight: .bold)
    attribution.layer.cornerRadius = 6
    attribution.layer.masksToBounds = true
    container.addSubview(attribution)
    NSLayoutConstraint.activate([
      attribution.topAnchor.constraint(equalTo: headline.bottomAnchor, constant: 4),
      attribution.leadingAnchor.constraint(equalTo: headline.leadingAnchor),
      attribution.heightAnchor.constraint(equalToConstant: 16)
    ])

    let body = UILabel()
    body.translatesAutoresizingMaskIntoConstraints = false
    body.font = UIFont.systemFont(ofSize: 12, weight: .regular)
    body.textColor = bodyText
    body.numberOfLines = 2
    container.addSubview(body)
    NSLayoutConstraint.activate([
      body.topAnchor.constraint(equalTo: attribution.bottomAnchor, constant: 3),
      body.leadingAnchor.constraint(equalTo: headline.leadingAnchor),
      body.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14)
    ])
    adView.bodyView = body

    let ctaButton = UIButton(type: .system)
    ctaButton.translatesAutoresizingMaskIntoConstraints = false
    ctaButton.backgroundColor = ctaBg
    ctaButton.setTitleColor(ctaText, for: .normal)
    ctaButton.titleLabel?.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
    ctaButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
    ctaButton.layer.cornerRadius = 15
    ctaButton.layer.masksToBounds = true
    ctaButton.isUserInteractionEnabled = false
    container.addSubview(ctaButton)
    NSLayoutConstraint.activate([
      ctaButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
      ctaButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
      ctaButton.heightAnchor.constraint(equalToConstant: 30),
      ctaButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 52)
    ])
    adView.callToActionView = ctaButton

    let divider = UIView()
    divider.translatesAutoresizingMaskIntoConstraints = false
    divider.backgroundColor = isDark ? UIColor(white: 1.0, alpha: 0.08) : UIColor(white: 0.0, alpha: 0.06)
    container.addSubview(divider)
    NSLayoutConstraint.activate([
      divider.leadingAnchor.constraint(equalTo: iconView.leadingAnchor),
      divider.trailingAnchor.constraint(equalTo: ctaButton.leadingAnchor, constant: -10),
      divider.bottomAnchor.constraint(equalTo: ctaButton.centerYAnchor),
      divider.heightAnchor.constraint(equalToConstant: 1)
    ])

    adView.setNativeAd(nativeAd)
    return adView
  }
}

final class PaddingLabel: UILabel {
  override func drawText(in rect: CGRect) {
    super.drawText(in: rect.inset(by: UIEdgeInsets(top: 1, left: 6, bottom: 1, right: 6)))
  }

  override var intrinsicContentSize: CGSize {
    let size = super.intrinsicContentSize
    return CGSize(width: size.width + 12, height: size.height + 2)
  }
}
