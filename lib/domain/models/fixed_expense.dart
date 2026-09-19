import '../../core/utilities/json_utils.dart';

/// A farm-level cost that does not vary with the crop allocation.
///
/// Variable costs live on [CropProfile] because they follow the acre; these
/// are the obligations the farm carries regardless of what gets planted.
class FixedExpense {
  const FixedExpense({
    required this.id,
    required this.name,
    required this.annualAmount,
    this.category = 'general',
    this.inflationRate = 0,
  });

  final String id;
  final String name;
  final double annualAmount;

  /// Grouping label for reporting, e.g. `insurance` or `depreciation`.
  final String category;

  /// Annual escalation used by the five-year model, as a fraction.
  final double inflationRate;

  factory FixedExpense.fromJson(Map<String, dynamic> json) => FixedExpense(
    id: asString(json['id']),
    name: asString(json['name']),
    annualAmount: asDouble(json['annualAmount']),
    category: asString(json['category'], fallback: 'general'),
    inflationRate: asDouble(json['inflationRate']),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'annualAmount': annualAmount,
    'category': category,
    'inflationRate': inflationRate,
  };

  FixedExpense copyWith({double? annualAmount, double? inflationRate}) =>
      FixedExpense(
        id: id,
        name: name,
        annualAmount: annualAmount ?? this.annualAmount,
        category: category,
        inflationRate: inflationRate ?? this.inflationRate,
      );

  @override
  String toString() => 'FixedExpense($id)';
}
