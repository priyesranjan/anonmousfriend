import 'package:flutter/material.dart';
import '../../services/listener_service.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  bool _isLoading = true;
  List<dynamic> _topListeners = [];
  Map<String, dynamic>? _myStats;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _fetchLeaderboard();
  }

  Future<void> _fetchLeaderboard() async {
    try {
      final listenerService = ListenerService();
      // For now, we'll try to get the leaderboard data from a new backend endpoint
      // If it doesn't exist yet, we'll handle the connection mock or error gracefully
      final response = await listenerService.getLeaderboard();
      
      if (mounted) {
        if (response['success'] == true) {
          setState(() {
            _topListeners = response['leaderboard'] ?? [];
            _myStats = response['myStats'];
            _isLoading = false;
          });
        } else {
          setState(() {
            _error = response['error'] ?? 'Failed to load leaderboard';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text(
          'Top Listeners 🏆',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? _buildErrorView()
              : _buildLeaderboard(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 60, color: Colors.red),
          const SizedBox(height: 16),
          Text(_error, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _isLoading = true;
                _error = '';
              });
              _fetchLeaderboard();
            },
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboard() {
    return Column(
      children: [
        if (_myStats != null) _buildMyStatsBanner(),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text(
                'Top Performers (This Week)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _topListeners.length,
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final listener = _topListeners[index];
              return _buildLeaderboardCard(listener, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMyStatsBanner() {
    final rank = _myStats!['rank'] ?? '-';
    final calls = _myStats!['total_calls'] ?? 0;
    final mins = _myStats!['total_minutes'] ?? 0;
    final streak = _myStats!['daily_streak_days'] ?? 0;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE91E63), Color(0xFFF06292)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.pink.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'My Current Rank',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              Text(
                '#$rank',
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('Calls', calls.toString()),
              _buildStatItem('Minutes', mins.toString()),
              _buildStatItem('Streak', '$streak Days', highlight: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, {bool highlight = false}) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: highlight ? Colors.yellow : Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildLeaderboardCard(dynamic listener, int index) {
    final isTop3 = index < 3;
    Color medalColor;
    if (index == 0) medalColor = const Color(0xFFFFD700); // Gold
    else if (index == 1) medalColor = const Color(0xFFC0C0C0); // Silver
    else if (index == 2) medalColor = const Color(0xFFCD7F32); // Bronze
    else medalColor = Colors.grey.shade300;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isTop3 ? medalColor : Colors.transparent, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Stack(
          alignment: Alignment.bottomRight,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: medalColor.withOpacity(0.2),
              backgroundImage: listener['profile_image'] != null
                  ? NetworkImage(listener['profile_image'])
                  : const AssetImage('assets/images/female_profile/avatar15.jpg') as ImageProvider,
            ),
            if (isTop3)
              Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.star, color: medalColor, size: 16),
              ),
          ],
        ),
        title: Text(
          listener['professional_name'] ?? 'Awesome Listener',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text('${listener['total_calls']} Calls • ${listener['total_minutes']} Mins'),
        trailing: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: medalColor.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isTop3 ? medalColor : Colors.grey.shade600,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
