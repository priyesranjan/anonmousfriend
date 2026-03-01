import '../services/api_service.dart';

class ReportService {
  final ApiService _apiService = ApiService();

  /// Submit a post-call report against a listener
  /// [reportType] must be one of: 'silent', 'rude', 'fake', 'boring'
  Future<Map<String, dynamic>> submitReport({
    required String listenerId,
    required String reportType,
    String? callId,
    String? description,
  }) async {
    try {
      final response = await _apiService.post('/reports', body: {
        'listener_id': listenerId,
        'report_type': reportType,
        if (callId != null) 'call_id': callId,
        if (description != null) 'description': description,
      });
      if (response.isSuccess) {
        return response.data;
      }
      return {'success': false, 'error': 'Failed to submit report'};
    } catch (e) {
      print('Error submitting report: $e');
      return {'success': false, 'error': 'Network error. Please try again.'};
    }
  }
}
