import Flutter
import UIKit
import google_mobile_ads
import GoogleMobileAds

class ListTileNativeAdFactory: NSObject, FLTNativeAdFactory {
    func createNativeAd(_ nativeAd: GADNativeAd, customOptions: [AnyHashable : Any]? = nil) -> GADNativeAdView? {
        let adView = GADNativeAdView()
        
        adView.translatesAutoresizingMaskIntoConstraints = false
        adView.heightAnchor.constraint(equalToConstant: 72).isActive = true
        
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        adView.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: adView.topAnchor, constant: 12),
            container.bottomAnchor.constraint(equalTo: adView.bottomAnchor, constant: -12),
            container.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 16),
            container.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -16)
        ])
        
        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.layer.cornerRadius = 24
        iconView.clipsToBounds = true
        iconView.backgroundColor = UIColor(white: 0.9, alpha: 1.0)
        iconView.contentMode = .scaleAspectFill
        container.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 48),
            iconView.heightAnchor.constraint(equalToConstant: 48),
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        adView.iconView = iconView
        
        let ctaButton = UIButton(type: .system)
        ctaButton.translatesAutoresizingMaskIntoConstraints = false
        ctaButton.backgroundColor = UIColor(red: 255/255.0, green: 219/255.0, blue: 178/255.0, alpha: 1.0)
        ctaButton.setTitleColor(.black, for: .normal)
        ctaButton.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        ctaButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        container.addSubview(ctaButton)
        NSLayoutConstraint.activate([
            ctaButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ctaButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ctaButton.heightAnchor.constraint(equalToConstant: 32)
        ])
        adView.callToActionView = ctaButton
        
        let vStack = UIStackView()
        vStack.axis = .vertical
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.spacing = 2
        container.addSubview(vStack)
        NSLayoutConstraint.activate([
            vStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 16),
            vStack.trailingAnchor.constraint(equalTo: ctaButton.leadingAnchor, constant: -16),
            vStack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        
        let headlineView = UILabel()
        headlineView.font = UIFont.boldSystemFont(ofSize: 16)
        headlineView.textColor = UIColor(red: 29/255.0, green: 27/255.0, blue: 32/255.0, alpha: 1.0)
        vStack.addArrangedSubview(headlineView)
        adView.headlineView = headlineView
        
        let hStack = UIStackView()
        hStack.axis = .horizontal
        hStack.spacing = 6
        hStack.alignment = .center
        vStack.addArrangedSubview(hStack)
        
        let badgeView = UILabel()
        badgeView.font = UIFont.boldSystemFont(ofSize: 10)
        badgeView.backgroundColor = UIColor(white: 0.9, alpha: 1.0)
        badgeView.textColor = UIColor(red: 29/255.0, green: 27/255.0, blue: 32/255.0, alpha: 1.0)
        let adLabel = customOptions?["adLabel"] as? String ?? "Ad"
        badgeView.text = " \(adLabel) "
        badgeView.layer.masksToBounds = true
        badgeView.layer.cornerRadius = 2
        hStack.addArrangedSubview(badgeView)
        
        let bodyView = UILabel()
        bodyView.font = UIFont.systemFont(ofSize: 12)
        bodyView.textColor = UIColor(red: 29/255.0, green: 27/255.0, blue: 32/255.0, alpha: 0.6)
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
