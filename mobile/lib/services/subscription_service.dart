import '../services/api_service.dart';

class SubscriptionService {
  final ApiService _apiService = ApiService();

  /// Check the user's subscription status
  /// Returns: { isPremium, freeCallsUsed, freeCallsLimit, maxFreeCallMinutes, subscription }
  Future<Map<String, dynamic>> getSubscriptionStatus() async {
    try {
      final response = await _apiService.get('/subscriptions/status');
      if (response.isSuccess) {
        return response.data;
      }
      return {'isPremium': false, 'freeCallsUsed': 0, 'freeCallsLimit': 2, 'maxFreeCallMinutes': 3};
    } catch (e) {
      print('Error checking subscription status: $e');
      return {'isPremium': false, 'freeCallsUsed': 0, 'freeCallsLimit': 2, 'maxFreeCallMinutes': 3};
    }
  }

  /// Check if the user can make a random call (gating check)
  /// Returns: { allowed, isPremium, adRequired, maxMinutes, filtersEnabled, reason, message }
  Future<Map<String, dynamic>> checkRandomCall() async {
    try {
      final response = await _apiService.post('/subscriptions/check-random-call');
      if (response.isSuccess) {
        return response.data;
      }
      return {'allowed': false, 'reason': 'error', 'message': 'Failed to check eligibility'};
    } catch (e) {
      print('Error checking random call: $e');
      return {'allowed': false, 'reason': 'error', 'message': 'Network error. Please try again.'};
    }
  }

  /// Purchase the ₹999/year premium subscription (deducted from wallet)
  Future<Map<String, dynamic>> purchaseSubscription() async {
    try {
      final response = await _apiService.post('/subscriptions/purchase');
      if (response.isSuccess) {
        return response.data;
      }
      return {'success': false, 'error': 'Failed to purchase subscription'};
    } catch (e) {
      print('Error purchasing subscription: $e');
      return {'success': false, 'error': 'Network error. Please try again.'};
    }
  }
}
