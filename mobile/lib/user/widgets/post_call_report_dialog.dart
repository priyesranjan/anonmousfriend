import 'package:flutter/material.dart';
import '../../services/report_service.dart';

/// Post-call report dialog shown after a call ends.
/// Allows users to report listeners: Silent, Rude, Fake, Boring.
class PostCallReportDialog extends StatefulWidget {
  final String listenerId;
  final String? callId;
  final String listenerName;

  const PostCallReportDialog({
    super.key,
    required this.listenerId,
    this.callId,
    required this.listenerName,
  });

  /// Show the post-call report dialog as a bottom sheet
  static Future<void> show(BuildContext context, {
    required String listenerId,
    String? callId,
    required String listenerName,
  }) {
    return showModalBottomSheet(
      context: context,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => PostCallReportDialog(
        listenerId: listenerId,
        callId: callId,
        listenerName: listenerName,
      ),
    );
  }

  @override
  State<PostCallReportDialog> createState() => _PostCallReportDialogState();
}

class _PostCallReportDialogState extends State<PostCallReportDialog> {
  final ReportService _reportService = ReportService();
  String? _selectedType;
  bool _isSubmitting = false;

  final List<Map<String, dynamic>> _reportOptions = [
    {'type': 'silent', 'icon': Icons.volume_off, 'label': 'Silent', 'color': Colors.grey},
    {'type': 'rude', 'icon': Icons.warning_amber, 'label': 'Rude', 'color': Colors.red},
    {'type': 'fake', 'icon': Icons.person_off, 'label': 'Fake', 'color': Colors.orange},
    {'type': 'boring', 'icon': Icons.sentiment_dissatisfied, 'label': 'Boring', 'color': Colors.blueGrey},
  ];

  Future<void> _submit() async {
    if (_selectedType == null) return;

    setState(() => _isSubmitting = true);

    final result = await _reportService.submitReport(
      listenerId: widget.listenerId,
      reportType: _selectedType!,
      callId: widget.callId,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    Navigator.of(context).pop();

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report submitted. Thank you for your feedback.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1F2937),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          const Row(
            children: [
              Icon(Icons.flag, color: Colors.orangeAccent, size: 22),
              SizedBox(width: 8),
              Text(
                'Report Issue',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Had a bad experience with ${widget.listenerName}?',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 20),

          // Report type options
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _reportOptions.map((option) {
              final isSelected = _selectedType == option['type'];
              return GestureDetector(
                onTap: () => setState(() => _selectedType = option['type'] as String),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (option['color'] as Color).withOpacity(0.2)
                        : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? (option['color'] as Color) : Colors.white12,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        option['icon'] as IconData,
                        color: isSelected ? (option['color'] as Color) : Colors.white54,
                        size: 28,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        option['label'] as String,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white54,
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // Buttons row
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Skip', style: TextStyle(color: Colors.white54, fontSize: 15)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _selectedType != null && !_isSubmitting ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    disabledBackgroundColor: Colors.grey.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Submit Report', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
