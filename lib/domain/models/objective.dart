import '../../core/utilities/json_utils.dart';

/// The goals FarmTwin can optimise for simultaneously.
///
/// Every objective is expressed so that **larger is better**. Objectives that
/// are naturally costs — water drawn, nitrogen applied — are stored negated,
/// which lets dominance and normalisation treat all six uniformly.
enum ObjectiveType {
  /// Cash remaining after debt service, in dollars.
  expectedProfit('Expected Profit'),

  /// Deterministic proxy for how much shock the plan absorbs, combining
  /// margin cushion with debt-service coverage.
  financialResilience('Financial Resilience'),

  /// Negated total irrigation, so less water scores higher.
  waterEfficiency('Water Efficiency'),

  /// Negated applied nitrogen and chemical spend.
  inputEfficiency('Input Efficiency'),

  /// Share of the farmer's preference constraints the plan satisfies.
  practiceAlignment('Practice Alignment'),

  /// Evenness of the crop mix.
  diversification('Crop Diversification');

  const ObjectiveType(this.label);

  final String label;

  static ObjectiveType? tryParse(String raw) {
    for (final ObjectiveType t in ObjectiveType.values) {
      if (t.name == raw) return t;
    }
    return null;
  }
}

/// Relative importance the farmer assigns to each objective.
///
/// Weights are normalised to sum to 1, so the farmer can enter them as
/// percentages, ratios or raw priorities without changing the outcome.
class ObjectiveWeights {
  ObjectiveWeights(Map<ObjectiveType, double> weights)
    : _weights = _normalise(weights);

  /// The default mix from the product spec: profit-led but not profit-only.
  factory ObjectiveWeights.balanced() =>
      ObjectiveWeights(const <ObjectiveType, double>{
        ObjectiveType.expectedProfit: 0.35,
        ObjectiveType.financialResilience: 0.25,
        ObjectiveType.waterEfficiency: 0.15,
        ObjectiveType.inputEfficiency: 0.10,
        ObjectiveType.practiceAlignment: 0.10,
        ObjectiveType.diversification: 0.05,
      });

  /// Weights that chase income alone, used for the "Profit Focus"
  /// representative plan.
  factory ObjectiveWeights.single(ObjectiveType objective) =>
      ObjectiveWeights(<ObjectiveType, double>{objective: 1.0});

  final Map<ObjectiveType, double> _weights;

  static Map<ObjectiveType, double> _normalise(Map<ObjectiveType, double> raw) {
    double total = 0;
    for (final double w in raw.values) {
      if (w > 0) total += w;
    }
    if (total <= 0) {
      // Degenerate input: fall back to an equal split so the optimiser still
      // produces a defensible ranking rather than dividing by zero.
      final double share = 1 / ObjectiveType.values.length;
      return <ObjectiveType, double>{
        for (final ObjectiveType t in ObjectiveType.values) t: share,
      };
    }
    final Map<ObjectiveType, double> result = <ObjectiveType, double>{};
    for (final ObjectiveType t in ObjectiveType.values) {
      final double w = raw[t] ?? 0;
      if (w > 0) result[t] = w / total;
    }
    return Map<ObjectiveType, double>.unmodifiable(result);
  }

  double weightOf(ObjectiveType type) => _weights[type] ?? 0;

  /// Objectives carrying non-zero weight, in enum order.
  List<ObjectiveType> get activeObjectives => ObjectiveType.values
      .where((ObjectiveType t) => weightOf(t) > 0)
      .toList(growable: false);

  Map<ObjectiveType, double> get asMap => _weights;

  ObjectiveWeights copyWith(Map<ObjectiveType, double> overrides) =>
      ObjectiveWeights(<ObjectiveType, double>{..._weights, ...overrides});

  factory ObjectiveWeights.fromJson(Map<String, dynamic> json) {
    final Map<ObjectiveType, double> parsed = <ObjectiveType, double>{};
    asJsonMap(json).forEach((String key, Object? value) {
      final ObjectiveType? type = ObjectiveType.tryParse(key);
      if (type != null) parsed[type] = asDouble(value);
    });
    return ObjectiveWeights(parsed);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    for (final MapEntry<ObjectiveType, double> e in _weights.entries)
      e.key.name: e.value,
  };

  @override
  String toString() => 'ObjectiveWeights($_weights)';
}
