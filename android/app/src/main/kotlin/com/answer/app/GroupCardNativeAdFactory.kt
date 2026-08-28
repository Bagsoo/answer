package com.answer.app

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.LayoutInflater
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import com.google.android.gms.ads.nativead.AdChoicesView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin.NativeAdFactory

class GroupCardNativeAdFactory(private val context: Context) : NativeAdFactory {
    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?
    ): NativeAdView {
        val adView = LayoutInflater.from(context)
            .inflate(R.layout.group_native_ad, null) as NativeAdView

        val headlineView = adView.findViewById<TextView>(R.id.ad_headline)
        val bodyView = adView.findViewById<TextView>(R.id.ad_body)
        val iconView = adView.findViewById<ImageView>(R.id.ad_app_icon)
        val callToActionView = adView.findViewById<Button>(R.id.ad_call_to_action)
        val attributionView = adView.findViewById<TextView>(R.id.ad_attribution)
        val adChoicesView = adView.findViewById<AdChoicesView>(R.id.ad_choices_view)

        adView.headlineView = headlineView
        adView.bodyView = bodyView
        adView.iconView = iconView
        adView.callToActionView = callToActionView
        adView.adChoicesView = adChoicesView

        val isDark = (customOptions?.get("themeBrightness") as? String) == "dark"
        val backgroundColor = if (isDark) Color.parseColor("#2A201E") else Color.parseColor("#FFFCFA")
        val borderColor = if (isDark) Color.parseColor("#26FFFFFF") else Color.parseColor("#12000000")
        val iconBackground = if (isDark) Color.parseColor("#4A3732") else Color.parseColor("#F4E1DA")
        val attributionBackground = if (isDark) Color.parseColor("#4A3732") else Color.parseColor("#EADACF")
        val attributionTextColor = if (isDark) Color.parseColor("#FAF0EB") else Color.parseColor("#6B2B1E")
        val headlineColor = if (isDark) Color.parseColor("#FFF6F1") else Color.parseColor("#231815")
        val bodyColor = if (isDark) Color.parseColor("#E0F4E7E1") else Color.parseColor("#99231815")
        val ctaBackground = if (isDark) Color.parseColor("#634A43") else Color.parseColor("#E6CBB8")
        val ctaTextColor = if (isDark) Color.parseColor("#FFF9F6") else Color.parseColor("#4A180E")

        val background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = 22f * context.resources.displayMetrics.density
            setColor(backgroundColor)
            setStroke((1f * context.resources.displayMetrics.density).toInt().coerceAtLeast(1), borderColor)
        }
        adView.background = background

        val adLabel = customOptions?.get("adLabel") as? String
        attributionView.text = adLabel ?: "Ad"
        attributionView.background = roundedRect(attributionBackground, 6f)
        attributionView.setTextColor(attributionTextColor)
        headlineView.setTextColor(headlineColor)
        bodyView.setTextColor(bodyColor)
        callToActionView.background = roundedRect(ctaBackground, 15f)
        callToActionView.setTextColor(ctaTextColor)
        iconView.background = circle(iconBackground)

        headlineView.text = nativeAd.headline

        if (nativeAd.body == null) {
            bodyView.visibility = View.INVISIBLE
        } else {
            bodyView.visibility = View.VISIBLE
            bodyView.text = nativeAd.body
        }

        if (nativeAd.icon == null) {
            iconView.visibility = View.GONE
        } else {
            iconView.visibility = View.VISIBLE
            iconView.setImageDrawable(nativeAd.icon?.drawable)
        }

        if (nativeAd.callToAction == null) {
            callToActionView.visibility = View.INVISIBLE
        } else {
            callToActionView.visibility = View.VISIBLE
            callToActionView.text = nativeAd.callToAction
        }

        adView.setNativeAd(nativeAd)
        return adView
    }

    private fun roundedRect(color: Int, radiusDp: Float): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = radiusDp * context.resources.displayMetrics.density
            setColor(color)
        }
    }

    private fun circle(color: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(color)
        }
    }
}
