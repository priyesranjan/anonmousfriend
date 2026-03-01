import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../actions/calling.dart';
import '../nav/profile/wallet.dart';
import '../../services/socket_service.dart';
import '../../services/storage_service.dart';
import '../../services/call_service.dart';
import '../../services/listener_service.dart';
import '../../services/subscription_service.dart';
import '../../services/ad_service.dart';
import '../../models/listener_model.dart' as model;

class RandomCallScreen extends StatefulWidget {
  const RandomCallScreen({super.key, this.onBackToHome});

  /// Optional hook used when this screen is shown inside a BottomNavBar tab.
  /// If provided, pressing back will switch to Home instead of trying to pop.
  final VoidCallback? onBackToHome;

  @override
  State<RandomCallScreen> createState() => _RandomCallScreenState();
}

class _RandomCallScreenState extends State<RandomCallScreen>
    with TickerProviderStateMixin {
  bool isSearching = false;
  Map<String, String>? matchedUser;
  final SocketService _socketService = SocketService();
  final StorageService _storage = StorageService();
  final ListenerService _listenerService = ListenerService();
  final SubscriptionService _subscriptionService = SubscriptionService();
  final AdService _adService = AdService();
  final AudioPlayer _searchAudioPlayer = AudioPlayer();

  // Subscription state
  bool _isPremium = false;
  bool _adRequired = false;
  int _freeCallsUsed = 0;
  int _freeCallsLimit = 2;
  int? _maxMinutes;

  late AnimationController _pulseController;
  late AnimationController _orbitController;

  // Female profile avatars for the visual effect
  final List<String> _dummyAvatars = [
    'assets/images/female_profile/avatar2.jpg',
    'assets/images/female_profile/avatar3.jpg',
    'assets/images/female_profile/avatar4.jpg',
    'assets/images/female_profile/avatar5.jpg',
    'assets/images/female_profile/avatar6.jpg',
    'assets/images/female_profile/avatar7.jpg',
    'assets/images/female_profile/avatar8.jpg',
    'assets/images/female_profile/avatar9.jpg',
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _stopSearchSound();
    _searchAudioPlayer.dispose();
    _pulseController.dispose();
    _orbitController.dispose();
    super.dispose();
  }

  Future<void> _startSearchSound() async {
    try {
      await _searchAudioPlayer.stop();
      await _searchAudioPlayer.setReleaseMode(ReleaseMode.loop);
      await _searchAudioPlayer.play(AssetSource('voice/random.mp3'));
    } catch (e) {
      debugPrint('RandomCall: search sound error: $e');
    }
  }

  Future<void> _stopSearchSound() async {
    try {
      await _searchAudioPlayer.stop();
    } catch (_) {}
  }

  void findRandomPerson() async {
    // ===== SUBSCRIPTION GATE =====
    final gateResult = await _subscriptionService.checkRandomCall();
    if (gateResult['allowed'] != true) {
      if (mounted) {
        _showDailyLimitDialog(gateResult['message'] ?? 'Daily limit reached');
      }
      return;
    }

    setState(() {
      _isPremium = gateResult['isPremium'] == true;
      _adRequired = gateResult['adRequired'] == true;
      _maxMinutes = gateResult['maxMinutes'];
      _freeCallsUsed = gateResult['freeCallsUsed'] ?? 0;
      _freeCallsLimit = gateResult['freeCallsLimit'] ?? 2;
    });

    // Free user must watch rewarded ad before proceeding
    if (_adRequired && mounted) {
      final adWatched = await _showAdDialog();
      if (adWatched != true) return;
    }

    setState(() {
      isSearching = true;
      matchedUser = null;
    });

    _startSearchSound();

    // Minimum search animation time for better UX
    final minSearchTime = Future.delayed(const Duration(seconds: 2));

    try {
      // Ensure socket is connected to get real-time online status
      await _socketService.connect();

      int maxRetries = 3;
      int retryCount = 0;
      List<model.Listener> onlineListeners = [];

      // Retry logic to find online listeners
      while (retryCount < maxRetries && onlineListeners.isEmpty) {
        // Use Smart Matching API for ranked listener results
        var result = await _listenerService.getSmartMatchListeners();

        // Fallback to basic fetch if smart-match fails
        if (!result.success || result.listeners.isEmpty) {
          result = await _listenerService.getListeners(
            isOnline: true,
            isBusy: false,
            limit: 50,
          );
        }

        if (result.success && result.listeners.isNotEmpty) {
          // Get real-time online status from socket
          final socketOnlineMap = _socketService.listenerOnlineMap;
          final backendEligibleListeners = result.listeners.where((listener) {
            // Hard filter from backend status so busy/unavailable listeners
            // are never shown in random matching.
            return !listener.isBusy && listener.isAvailable;
          }).toList();

          // Prefer socket-confirmed online status, with backend as fallback.
          onlineListeners = backendEligibleListeners.where((listener) {
            if (socketOnlineMap.isEmpty) {
              return listener.isOnline;
            }
            final socketOnline = socketOnlineMap[listener.userId];
            return socketOnline ?? listener.isOnline;
          }).toList();

          // If socket map is stale/empty for these users, still trust backend
          // online + busy status.
          if (onlineListeners.isEmpty && backendEligibleListeners.isNotEmpty) {
            onlineListeners = backendEligibleListeners
                .where((listener) => listener.isOnline)
                .toList();
          }
        }

        if (onlineListeners.isEmpty) {
          retryCount++;
          if (retryCount < maxRetries) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
      }

      // Wait for minimum search time
      await minSearchTime;

      if (onlineListeners.isNotEmpty) {
        // Shuffle and pick random listener
        onlineListeners.shuffle();
        final randomListener = onlineListeners.first;

        await _stopSearchSound();
        setState(() {
          isSearching = false;
          matchedUser = {
            'id': randomListener.userId,
            'listener_id': randomListener.listenerId,
            'name': randomListener.professionalName ?? 'Unknown',
            'city': randomListener.city ?? 'Unknown',
            'topic': randomListener.specialties.isNotEmpty
                ? randomListener.specialties.first
                : 'General',
            'image':
                randomListener.avatarUrl ??
                'assets/images/female_profile/avatar2.jpg',
          };
        });
      } else {
        await _stopSearchSound();
        setState(() {
          isSearching = false;
          matchedUser = null;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No Experts online right now. Please try again later.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      print('Error finding random listener: $e');
      await _stopSearchSound();
      await minSearchTime;
      setState(() {
        isSearching = false;
        matchedUser = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to find Experts: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void startCall(Map<String, String> user) async {
    // Connect to socket and wait for connection
    final connected = await _socketService.connect();

    if (!connected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to connect. Please try again.')),
        );
      }
      return;
    }

    // Get current user info
    final userName = await _storage.getDisplayName() ?? 'You';
    final userAvatar = await _storage.getAvatarUrl();
    final userGender = await _storage.getGender();

    final listenerId = user['id'];

    // Create call record in database first
    final callService = CallService();
    final callResult = await callService.initiateCall(
      listenerId: user['listener_id'] ?? listenerId ?? '',
      callType: 'audio',
    );

    if (!callResult.success) {
      final error = callResult.error ?? 'Failed to initiate call';
      final isBalanceError = error.toLowerCase().contains('insufficient') ||
          error.toLowerCase().contains('low balance');

      if (mounted) {
        if (isBalanceError) {
          _showLowBalanceDialog(error);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error)),
          );
        }
      }
      return;
    }

    final callId = callResult.call!.callId;

    // Notify listener via socket
    if (listenerId != null) {
      print('Caller: Initiating call to Experts userId: $listenerId');
      _socketService.initiateCall(
        callId: callId,
        listenerId: listenerId,
        callerName: userName,
        callerAvatar: userAvatar,
        topic: user['topic'],
        gender: userGender,
      );
    } else {
      print('Warning: No Experts userId available for call');
    }

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Calling(
          callerName: user['name']!,
          callerAvatar: user['image']!,
          userName: userName,
          userAvatar: userAvatar,
          channelName: callId,
          listenerId: listenerId,
        ),
      ),
    );
  }

  /// Shows a professional low-balance bottom sheet with animated icon,
  /// then navigates to the Wallet screen so the user can recharge.
  void _showLowBalanceDialog(String errorMessage) {
    showModalBottomSheet(
      context: context,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _LowBalanceSheet(
        errorMessage: errorMessage,
        onAddBalance: () {
          Navigator.of(ctx).pop();
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const WalletScreen()),
          );
        },
        onDismiss: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  /// Shows the daily limit reached dialog with premium upgrade CTA
  void _showDailyLimitDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.timer_off, color: Colors.orangeAccent, size: 28),
            SizedBox(width: 8),
            Text('Daily Limit Reached', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: const TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.workspace_premium, color: Colors.yellowAccent, size: 24),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Premium — ₹999/year\nUnlimited calls • Gender filter • No ads',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Later', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              _purchasePremium();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEC4899)),
            child: const Text('Upgrade Now'),
          ),
        ],
      ),
    );
  }

  /// Shows the ad dialog and triggers rewarded ad via AdService
  Future<bool?> _showAdDialog() async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.play_circle_fill, color: Colors.greenAccent, size: 28),
            SizedBox(width: 8),
            Flexible(child: Text('Free Call', style: TextStyle(color: Colors.white, fontSize: 18))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Watch a short ad to unlock your free call (${_freeCallsUsed}/${_freeCallsLimit} used today).\n\nFree calls are limited to $_maxMinutes minutes.',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.smart_display, color: Colors.greenAccent, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tap "Watch Ad" to start the rewarded video',
                      style: TextStyle(color: Colors.greenAccent, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              // Trigger rewarded ad via AdService
              final rewarded = await _adService.showRewardedAd();
              if (ctx.mounted) {
                Navigator.of(ctx).pop(rewarded);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Watch Ad'),
          ),
        ],
      ),
    );
  }

  /// Purchase the premium subscription from wallet
  Future<void> _purchasePremium() async {
    final result = await _subscriptionService.purchaseSubscription();
    if (!mounted) return;

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Premium activated! Unlimited random calls unlocked.'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() => _isPremium = true);
    } else {
      final error = result['error'] ?? 'Purchase failed';
      if (error.toString().contains('Insufficient')) {
        _showLowBalanceDialog(error.toString());
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _handleBack() {
    _stopSearchSound();
    if (isSearching) {
      setState(() {
        isSearching = false;
        matchedUser = null;
      });
    }

    // If this page was pushed on the Navigator stack, pop it.
    // Otherwise (e.g. when embedded as a BottomNavBar tab), redirect to Home.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    if (widget.onBackToHome != null) {
      widget.onBackToHome!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBack();
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: const Color(0xFF0B1220),
        appBar: AppBar(
          leading: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 18,
              ),
            ),
            onPressed: _handleBack,
          ),
          title: const Text(
            "Random Match",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
        ),
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0B1220), Color(0xFF111827), Color(0xFF312E81)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            bottom: true,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              child: isSearching
                  ? _orbitSearchingView(size)
                  : matchedUser != null
                  ? _matchedCard(matchedUser!, size)
                  : _idleView(size),
            ),
          ),
        ),
      ),
    );
  }

  /// ---------------- Idle View ----------------
  Widget _idleView(Size size) {
    // Responsive sizes based on screen
    final circleSize = size.width * 0.4;
    final maxCircleSize = circleSize > 180 ? 180.0 : circleSize;
    final iconSize = maxCircleSize * 0.44;

    return SingleChildScrollView(
      key: const ValueKey('idle'),
      physics: const BouncingScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight:
              size.height -
              MediaQuery.of(context).padding.top -
              kToolbarHeight -
              MediaQuery.of(context).padding.bottom,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: size.width * 0.06,
            vertical: size.height * 0.02,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: size.height * 0.05),
              // Pulsing Radar Effect
              Stack(
                alignment: Alignment.center,
                children: [
                  // Outer glow rings
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Container(
                        width:
                            maxCircleSize * 1.55 +
                            (_pulseController.value * 40),
                        height:
                            maxCircleSize * 1.55 +
                            (_pulseController.value * 40),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.pinkAccent.withOpacity(
                              0.1 - (_pulseController.value * 0.1),
                            ),
                            width: 1,
                          ),
                        ),
                      );
                    },
                  ),
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Container(
                        width:
                            maxCircleSize * 1.22 +
                            (_pulseController.value * 30),
                        height:
                            maxCircleSize * 1.22 +
                            (_pulseController.value * 30),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.pinkAccent.withOpacity(0.05),
                        ),
                      );
                    },
                  ),
                  // Main Circle
                  Container(
                    width: maxCircleSize,
                    height: maxCircleSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.pinkAccent.withOpacity(0.4),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.person_search_rounded,
                      size: iconSize,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              SizedBox(height: size.height * 0.04),
              Text(
                "Find Your Match",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size.width * 0.062,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.4,
                ),
              ),
              SizedBox(height: size.height * 0.015),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: size.width * 0.05),
                child: Text(
                  "Connect instantly with a verified Experts for a random voice conversation.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.72),
                    fontSize: size.width * 0.037,
                    height: 1.6,
                  ),
                ),
              ),
              SizedBox(height: size.height * 0.02),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: size.width * 0.04,
                  vertical: size.height * 0.008,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.verified_rounded,
                      color: Colors.white.withOpacity(0.8),
                      size: size.width * 0.04,
                    ),
                    SizedBox(width: size.width * 0.02),
                    Text(
                      "Verified Experts only",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: size.width * 0.032,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: size.height * 0.05),
              // Start Matching Button
              Container(
                height: size.height * 0.065,
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 56, minHeight: 48),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEC4899).withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: findRandomPerson,
                    borderRadius: BorderRadius.circular(28),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.mic,
                          color: Colors.white,
                          size: size.width * 0.052,
                        ),
                        SizedBox(width: size.width * 0.02),
                        Text(
                          "Start Matching",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: size.width * 0.039,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(height: size.height * 0.02),

              // Premium Upgrade CTA
              if (!_isPremium)
                GestureDetector(
                  onTap: _purchasePremium,
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      horizontal: size.width * 0.04,
                      vertical: size.height * 0.015,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [Colors.amber.shade800, Colors.orange.shade700],
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.workspace_premium, color: Colors.yellowAccent, size: 20),
                        SizedBox(width: size.width * 0.02),
                        Text(
                          "Unlock Premium — ₹999/year",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: size.width * 0.035,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_isPremium)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.workspace_premium, color: Colors.greenAccent, size: 16),
                      SizedBox(width: 6),
                      Text('Premium Active', style: TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              SizedBox(height: size.height * 0.03),
            ],
          ),
        ),
      ),
    );
  }

  /// ---------------- Orbit/Radar Searching View ----------------
  Widget _orbitSearchingView(Size size) {
    final baseRadius = size.width * 0.2;
    final avatarRadius = size.width * 0.045;

    return SizedBox(
      key: const ValueKey('searching'),
      width: double.infinity,
      height: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background Radar Circles
          ...List.generate(4, (index) {
            final double radarSize =
                (baseRadius * 1.5) + (index * baseRadius * 0.8);
            return Container(
              width: radarSize,
              height: radarSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.07),
                  width: 1,
                ),
              ),
            );
          }),

          // Orbiting Avatars
          AnimatedBuilder(
            animation: _orbitController,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: _dummyAvatars.asMap().entries.map((entry) {
                  final index = entry.key;
                  final imagePath = entry.value;

                  // Calculate different orbit paths - responsive
                  final double radius =
                      baseRadius + ((index % 3) * baseRadius * 0.6);
                  final double speed = 1.0 + ((index % 3) * 0.5);
                  final bool clockwise = index % 2 == 0;

                  final double initialAngle =
                      (index * (2 * math.pi / _dummyAvatars.length));
                  final double currentAngle =
                      initialAngle +
                      (_orbitController.value *
                          2 *
                          math.pi *
                          speed *
                          (clockwise ? 1 : -1));

                  return Transform.translate(
                    offset: Offset(
                      math.cos(currentAngle) * radius,
                      math.sin(currentAngle) * radius,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.5),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.pinkAccent.withOpacity(0.3),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: avatarRadius,
                        backgroundImage: AssetImage(imagePath),
                        backgroundColor: Colors.grey[800],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),

          // Center Glowing Core
          Container(
            width: size.width * 0.15,
            height: size.width * 0.15,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.pinkAccent.withOpacity(0.2),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: size.width * 0.025,
                height: size.width * 0.025,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.pinkAccent.withOpacity(0.8),
                ),
              ),
            ),
          ),

          // Bottom Text
          Positioned(
            bottom: size.height * 0.12,
            left: size.width * 0.05,
            right: size.width * 0.05,
            child: Column(
              children: [
                Text(
                  "Finding available Experts...",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: size.width * 0.043,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                SizedBox(height: size.height * 0.01),
                Text(
                  "Scanning online profiles",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: size.width * 0.034,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ---------------- Matched User Card ----------------
  Widget _matchedCard(Map<String, String> user, Size size) {
    final avatarRadius = size.width * 0.13;
    final maxAvatarRadius = avatarRadius > 60 ? 60.0 : avatarRadius;

    return SingleChildScrollView(
      key: const ValueKey('matched'),
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: size.width * 0.05,
          vertical: size.height * 0.02,
        ),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(size.width * 0.05),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF111827), Color(0xFF1F2937)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 40,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Success Badge
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: size.width * 0.04,
                  vertical: size.height * 0.01,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.withOpacity(0.45)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: Colors.greenAccent,
                      size: size.width * 0.038,
                    ),
                    SizedBox(width: size.width * 0.02),
                    Text(
                      "Match Found!",
                      style: TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: size.width * 0.034,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: size.height * 0.025),

              // Avatar with Glow
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.pinkAccent.withOpacity(0.5),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: maxAvatarRadius,
                  backgroundImage: AssetImage(user['image']!),
                  backgroundColor: Colors.grey[800],
                ),
              ),
              SizedBox(height: size.height * 0.02),

              // User Details
              Text(
                user['name']!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size.width * 0.058,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: size.height * 0.008),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.location_on,
                    color: Colors.white.withOpacity(0.6),
                    size: size.width * 0.04,
                  ),
                  SizedBox(width: size.width * 0.01),
                  Text(
                    user['city']!,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: size.width * 0.038,
                    ),
                  ),
                ],
              ),
              SizedBox(height: size.height * 0.02),

              // Tags
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: size.width * 0.04,
                  vertical: size.height * 0.01,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.topic_rounded,
                      color: const Color(0xFF8B5CF6),
                      size: size.width * 0.045,
                    ),
                    SizedBox(width: size.width * 0.02),
                    Text(
                      user['topic']!,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: size.width * 0.034,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: size.height * 0.03),

              // Actions
              SizedBox(
                width: double.infinity,
                height: size.height * 0.06,
                child: ElevatedButton(
                  onPressed: () => startCall(user),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEC4899),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      vertical: size.height * 0.015,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    elevation: 4,
                    shadowColor: const Color(0xFFEC4899).withOpacity(0.4),
                  ),
                  child: Text(
                    "Start Call Now",
                    style: TextStyle(
                      fontSize: size.width * 0.041,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              SizedBox(height: size.height * 0.012),
              TextButton(
                onPressed: findRandomPerson,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: size.height * 0.01),
                  foregroundColor: Colors.white.withOpacity(0.7),
                ),
                child: Text(
                  "Find Another Match",
                  style: TextStyle(fontSize: size.width * 0.037),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Professional Low Balance Bottom Sheet
// ══════════════════════════════════════════════════════════════════

class _LowBalanceSheet extends StatefulWidget {
  final String errorMessage;
  final VoidCallback onAddBalance;
  final VoidCallback onDismiss;

  const _LowBalanceSheet({
    required this.errorMessage,
    required this.onAddBalance,
    required this.onDismiss,
  });

  @override
  State<_LowBalanceSheet> createState() => _LowBalanceSheetState();
}

class _LowBalanceSheetState extends State<_LowBalanceSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _iconBounce;
  late final Animation<double> _fadeSlide;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _iconBounce = CurvedAnimation(
      parent: _animCtrl,
      curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
    );
    _fadeSlide = CurvedAnimation(
      parent: _animCtrl,
      curve: const Interval(0.25, 1.0, curve: Curves.easeOut),
    );
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bottomPad = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF111827),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 14, 24, 20 + bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Drag handle ──
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 22),

            // ── Animated wallet icon ──
            ScaleTransition(
              scale: _iconBounce,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      Colors.red.shade800.withOpacity(0.35),
                      Colors.red.shade600.withOpacity(0.18),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: Colors.redAccent.withOpacity(0.3),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.redAccent.withOpacity(0.15),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: Colors.redAccent,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 18),

            // ── Title & subtitle ──
            FadeTransition(
              opacity: _fadeSlide,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.15),
                  end: Offset.zero,
                ).animate(_fadeSlide),
                child: Column(
                  children: [
                    const Text(
                      'Insufficient Balance',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.red.shade900.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.redAccent.withOpacity(0.15),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: Colors.redAccent.withOpacity(0.8),
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.errorMessage,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 13.5,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Please recharge your wallet to continue making calls.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 26),

            // ── Add Balance button ──
            FadeTransition(
              opacity: _fadeSlide,
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFEC4899).withOpacity(0.3),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.onAddBalance,
                      borderRadius: BorderRadius.circular(14),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_circle_outline,
                              color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Add Balance',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Maybe Later ──
            FadeTransition(
              opacity: _fadeSlide,
              child: TextButton(
                onPressed: widget.onDismiss,
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                ),
                child: Text(
                  'Maybe Later',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
