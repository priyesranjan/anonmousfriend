import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/call_service.dart';
import '../../services/socket_service.dart';
import '../../models/call_model.dart';
import '../../ui/skeleton_loading_ui/recent_chat_skeleton.dart';

class RecentsScreen extends StatefulWidget {
  const RecentsScreen({super.key});

  @override
  State<RecentsScreen> createState() => _RecentsScreenState();
}

class _RecentsScreenState extends State<RecentsScreen> {
  final CallService _callService = CallService();
  final SocketService _socketService = SocketService();

  bool _isLoading = true;
  String? _error;
  List<Call> _callHistory = [];
  StreamSubscription<Map<String, dynamic>>? _userPresenceSubscription;
  Timer? _lastSeenTicker;
  final Map<String, bool> _callerOnlineMap = {};
  final Map<String, DateTime?> _callerLastSeenMap = {};

  @override
  void initState() {
    super.initState();
    unawaited(_initializePresence());
    _loadCallHistory();
  }

  Future<void> _loadCallHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _callService.getListenerCallHistory(limit: 50);

      if (result.success) {
        setState(() {
          _callHistory = result.calls;
          _syncPresenceFromHistory(result.calls);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = result.error;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load call history';
        _isLoading = false;
      });
    }
  }

  Future<void> _initializePresence() async {
    if (_socketService.userOnlineMap.isNotEmpty) {
      _callerOnlineMap.addAll(_socketService.userOnlineMap);
    }
    if (_socketService.userLastSeenMap.isNotEmpty) {
      _callerLastSeenMap.addAll(_socketService.userLastSeenMap);
    }

    try {
      await _socketService.connect();
    } catch (_) {
      // Presence can still fall back to history values if socket isn't ready.
    }

    _userPresenceSubscription?.cancel();
    _userPresenceSubscription = _socketService.onUserPresence.listen((event) {
      if (!mounted) return;
      final userId = event['userId']?.toString();
      if (userId == null || userId.isEmpty) return;

      final isOnline = event['online'] == true;
      DateTime? timestamp;
      final rawTimestamp = event['timestamp'];
      if (rawTimestamp is int) {
        timestamp = DateTime.fromMillisecondsSinceEpoch(rawTimestamp);
      } else if (rawTimestamp is String) {
        final millis = int.tryParse(rawTimestamp);
        if (millis != null) {
          timestamp = DateTime.fromMillisecondsSinceEpoch(millis);
        } else {
          timestamp = DateTime.tryParse(rawTimestamp);
        }
      }

      final currentOnline = _callerOnlineMap[userId];
      final currentLastSeen = _callerLastSeenMap[userId];
      final nextLastSeen = isOnline
          ? currentLastSeen
          : (timestamp ?? DateTime.now());
      final changed =
          currentOnline != isOnline || currentLastSeen != nextLastSeen;

      if (!changed) return;

      _callerOnlineMap[userId] = isOnline;
      if (!isOnline) {
        _callerLastSeenMap[userId] = nextLastSeen;
      }
      setState(() {});
    });

    _lastSeenTicker?.cancel();
    _lastSeenTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _syncPresenceFromHistory(List<Call> calls) {
    for (final call in calls) {
      final callerId = call.callerId;
      if (callerId.isEmpty) continue;

      if (!_callerOnlineMap.containsKey(callerId)) {
        _callerOnlineMap[callerId] = call.callerOnline ?? false;
      }

      final historyLastSeen = call.callerLastSeen;
      if (historyLastSeen != null) {
        final existing = _callerLastSeenMap[callerId];
        if (existing == null || existing.isBefore(historyLastSeen)) {
          _callerLastSeenMap[callerId] = historyLastSeen;
        }
      }
    }
  }

  String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    final local = dateTime.toLocal();
    return DateFormat('h:mm a').format(local);
  }

  String _formatDate(DateTime? dateTime) {
    if (dateTime == null) return '';
    final local = dateTime.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final callDate = DateTime(local.year, local.month, local.day);

    if (callDate == today) {
      return 'Today';
    } else if (callDate == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('MMM d, yyyy').format(local);
    }
  }

  String _formatLastSeen(DateTime? dateTime) {
    if (dateTime == null) return 'recently';
    final now = DateTime.now();
    final local = dateTime.toLocal();
    final diff = now.difference(local);

    if (diff.inSeconds < 30) return 'just now';
    if (diff.inMinutes < 1) return 'less than a minute ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d, h:mm a').format(local);
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'missed':
        return 'Missed';
      case 'rejected':
        return 'Declined';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'missed':
        return Colors.red;
      case 'rejected':
        return Colors.orange;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  int _calculateTotalMinutes(int? durationSeconds) {
    if (durationSeconds == null || durationSeconds <= 0) return 0;
    return (durationSeconds / 60).ceil();
  }

  // Group calls by date
  Map<String, List<Call>> _groupCallsByDate() {
    final Map<String, List<Call>> grouped = {};
    for (final call in _callHistory) {
      final dateKey = _formatDate(call.createdAt);
      if (!grouped.containsKey(dateKey)) {
        grouped[dateKey] = [];
      }
      grouped[dateKey]!.add(call);
    }
    return grouped;
  }

  @override
  void dispose() {
    _userPresenceSubscription?.cancel();
    _lastSeenTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFEEBF1), Color(0xFFF7F3FD)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            _buildCustomHeader(context),
            Expanded(
              child: _isLoading
                  ? ListView.builder(
                      itemCount: 10,
                      itemBuilder: (context, index) =>
                          const RecentChatSkeleton(),
                    )
                  : _error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loadCallHistory,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : _callHistory.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: _loadCallHistory,
                      child: _buildCallList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.call_received, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No recent calls',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Calls from users will appear here',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildCallList() {
    final groupedCalls = _groupCallsByDate();
    final dateKeys = groupedCalls.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: dateKeys.length,
      itemBuilder: (context, index) {
        final dateKey = dateKeys[index];
        final calls = groupedCalls[dateKey]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                dateKey,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  fontSize: 14,
                ),
              ),
            ),
            ...calls.map((call) => _buildRecentItemCard(call)),
          ],
        );
      },
    );
  }

  /// -------- Custom Header with Back Button ----------
  Widget _buildCustomHeader(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 16, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Back Button
            Row(children: [_buildBackButton(context)]),

            // Title and Refresh
            Row(
              children: [
                const Text(
                  'Recents',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 26,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadCallHistory,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// -------- Back Button ----------
  Widget _buildBackButton(BuildContext context) {
    final canPop = Navigator.of(context).canPop();

    if (!canPop) {
      return const SizedBox(width: 48);
    }

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.pop(context),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.6),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6),
          ],
        ),
        child: const Icon(
          Icons.arrow_back_ios_new,
          size: 18,
          color: Colors.black87,
        ),
      ),
    );
  }

  /// -------- Recent Card ----------
  Widget _buildRecentItemCard(Call call) {
    // For listener, show caller info (the user who called them)
    final name = call.callerName ?? 'Unknown User';
    final avatar =
        call.callerAvatar ?? 'https://randomuser.me/api/portraits/lego/1.jpg';
    final status = call.status;
    final totalMinutes = _calculateTotalMinutes(call.durationSeconds);
    final callerId = call.callerId;
    final isOnline = _callerOnlineMap[callerId] ?? call.callerOnline ?? false;
    final lastSeen = _callerLastSeenMap[callerId] ?? call.callerLastSeen;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFEE9F2), Color(0xFFFBEFFF)],
        ),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.pinkAccent.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        child: Row(
          children: [
            // Avatar + Status
            Stack(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundImage: avatar.startsWith('http')
                      ? NetworkImage(avatar)
                      : AssetImage(avatar) as ImageProvider,
                  backgroundColor: Colors.grey.shade200,
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: isOnline ? Colors.green : Colors.grey,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(status),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _getStatusText(status),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 15),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 17,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${call.formattedDuration} - ${_formatTime(call.createdAt)}',
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isOnline ? Colors.green : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          isOnline
                              ? 'Online'
                              : 'Offline - last seen ${_formatLastSeen(lastSeen)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isOnline
                                ? Colors.green[700]
                                : Colors.grey[600],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            _buildMinutesBadge(totalMinutes),
          ],
        ),
      ),
    );
  }

  Widget _buildMinutesBadge(int totalMinutes) {
    return Container(
      constraints: const BoxConstraints(minWidth: 76),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.timer_outlined, size: 16, color: Colors.grey[700]),
          const SizedBox(width: 6),
          Text(
            '$totalMinutes min',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
