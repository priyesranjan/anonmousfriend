import 'package:flutter/material.dart';

/// AdMob Ad Service — manages ad loading, showing, and lifecycle.
///
/// This service scaffolds the ad placements defined in the product blueprint:
/// - Rewarded video before random call (mandatory for free users)
/// - Interstitial after call ends (before recharge prompt)
/// - Banner ad on home screen bottom (always for free users)
///
/// **NOTE:** Requires `google_mobile_ads` package.
/// Add to pubspec.yaml: `google_mobile_ads: ^5.2.0`
/// Also add your AdMob App ID to:
/// - Android: `android/app/src/main/AndroidManifest.xml`
/// - iOS: `ios/Runner/Info.plist`
///
/// Replace test ad unit IDs below with production IDs before release.
class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  // ===== TEST AD UNIT IDs (Replace with production IDs) =====
  // Android test IDs from Google
  static const String _testBannerAdId = 'ca-app-pub-3940256099942544/6300978111';
  static const String _testInterstitialAdId = 'ca-app-pub-3940256099942544/1033173712';
  static const String _testRewardedAdId = 'ca-app-pub-3940256099942544/5224354917';

  // Production ad unit IDs — replace these with your actual AdMob IDs
  static const String bannerAdUnitId = _testBannerAdId;
  static const String interstitialAdUnitId = _testInterstitialAdId;
  static const String rewardedAdUnitId = _testRewardedAdId;

  bool _isInitialized = false;

  /// Initialize the AdMob SDK
  /// Call this in main.dart before runApp()
  Future<void> initialize() async {
    if (_isInitialized) return;
    // When google_mobile_ads is added, uncomment:
    // await MobileAds.instance.initialize();
    _isInitialized = true;
    debugPrint('[AdService] AdMob SDK initialized (placeholder)');
  }

  /// Show a rewarded video ad (before random call for free users)
  /// Returns true if the user earned the reward (watched fully)
  Future<bool> showRewardedAd() async {
    debugPrint('[AdService] Rewarded ad requested (placeholder — will use AdMob)');
    // Placeholder: simulate a successful ad watch with delay
    await Future.delayed(const Duration(seconds: 1));
    return true;

    // When google_mobile_ads is added, implement:
    // final completer = Completer<bool>();
    // RewardedAd.load(
    //   adUnitId: rewardedAdUnitId,
    //   request: const AdRequest(),
    //   rewardedAdLoadCallback: RewardedAdLoadCallback(
    //     onAdLoaded: (ad) {
    //       ad.fullScreenContentCallback = FullScreenContentCallback(
    //         onAdDismissedFullScreenContent: (ad) { ad.dispose(); completer.complete(false); },
    //       );
    //       ad.show(onUserEarnedReward: (ad, reward) { completer.complete(true); });
    //     },
    //     onAdFailedToLoad: (err) { completer.complete(false); },
    //   ),
    // );
    // return completer.future;
  }

  /// Show an interstitial ad (after call ends, before recharge prompt)
  Future<void> showInterstitialAd() async {
    debugPrint('[AdService] Interstitial ad requested (placeholder — will use AdMob)');
    await Future.delayed(const Duration(milliseconds: 500));

    // When google_mobile_ads is added, implement:
    // InterstitialAd.load(
    //   adUnitId: interstitialAdUnitId,
    //   request: const AdRequest(),
    //   adLoadCallback: InterstitialAdLoadCallback(
    //     onAdLoaded: (ad) { ad.show(); },
    //     onAdFailedToLoad: (err) { debugPrint('Interstitial load failed: $err'); },
    //   ),
    // );
  }

  /// Check if user should see ads
  /// Returns false for premium users and wallet users with balance
  Future<bool> shouldShowAds(bool isPremium) async {
    return !isPremium;
  }
}
