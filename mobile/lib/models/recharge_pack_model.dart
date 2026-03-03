class RechargePack {
  final String id;
  final double amount;
  final double extraPercentOrAmount;
  final String? badgeText;
  final int sortOrder;
  final bool isUnlimited;
  final int unlimitedDays;
  final bool isFirstTimeOnly;

  RechargePack({
    required this.id,
    required this.amount,
    required this.extraPercentOrAmount,
    this.badgeText,
    required this.sortOrder,
    this.isUnlimited = false,
    this.unlimitedDays = 0,
    this.isFirstTimeOnly = false,
  });

  factory RechargePack.fromJson(Map<String, dynamic> json) {
    return RechargePack(
      id: json['id'],
      amount: double.parse(json['amount'].toString()),
      extraPercentOrAmount: double.parse(json['extra_percent_or_amount'].toString()),
      badgeText: json['badge_text'],
      sortOrder: json['sort_order'] ?? 0,
      isUnlimited: json['is_unlimited'] ?? false,
      unlimitedDays: json['unlimited_days'] ?? 0,
      isFirstTimeOnly: json['is_first_time_only'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'amount': amount,
      'extra_percent_or_amount': extraPercentOrAmount,
      'badge_text': badgeText,
      'sort_order': sortOrder,
      'is_unlimited': isUnlimited,
      'unlimited_days': unlimitedDays,
      'is_first_time_only': isFirstTimeOnly,
    };
  }
}
