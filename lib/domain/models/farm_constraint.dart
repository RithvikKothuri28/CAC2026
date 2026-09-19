import '../../core/utilities/json_utils.dart';

/// How strictly a farmer wants a constraint applied.
enum ConstraintMode {
  /// Any plan that violates this is removed from the feasible set outright.
  hard,

  /// Violations are allowed but count against the plan's practice alignment.
  preference,

  /// Ignored entirely by the engines.
  disabled;

  static ConstraintMode parse(String raw) => ConstraintMode.values.firstWhere(
    (ConstraintMode m) => m.name == raw,
    orElse: () => ConstraintMode.disabled,
  );
}

/// Whether the farmer's number is a ceiling or a floor.
enum ConstraintDirection { maximum, minimum }

/// The operating rules FarmTwin knows how to evaluate.
enum ConstraintType {
  /// Total applied irrigation across the farm, in acre-inches.
  maxWaterAcreInches(ConstraintDirection.maximum, 'acre-in'),

  /// Total applied nitrogen across the farm, in pounds.
  maxNitrogenLbs(ConstraintDirection.maximum, 'lb N'),

  /// Total operating expense, variable plus fixed.
  maxOperatingExpense(ConstraintDirection.maximum, r'$'),

  /// Operating income before debt service.
  minOperatingIncome(ConstraintDirection.minimum, r'$'),

  /// Cash remaining after scheduled debt payments.
  minCashAfterDebtService(ConstraintDirection.minimum, r'$'),

  /// Operating income divided by debt service.
  minDebtServiceCoverage(ConstraintDirection.minimum, 'x'),

  /// Largest share of farm acres any single crop may occupy, as a fraction.
  maxCropConcentration(ConstraintDirection.maximum, 'share'),

  /// Distinct crops the plan must include.
  minCropCount(ConstraintDirection.minimum, 'crops'),

  /// Crop rotation rules declared on each crop profile must be honoured.
  /// The measured value is the number of fields breaking a rule, so the
  /// farmer's threshold is the count of conflicts they will tolerate —
  /// normally zero.
  rotationRequired(ConstraintDirection.maximum, 'conflicts'),

  /// Minimum share of acres carrying a soil-covering crop.
  minSoilCoverShare(ConstraintDirection.minimum, 'share'),

  /// No crop carrying the tag in `textValue` may be planted.
  restrictedInput(ConstraintDirection.maximum, 'acres');

  const ConstraintType(this.direction, this.unit);

  final ConstraintDirection direction;
  final String unit;

  static ConstraintType? tryParse(String raw) {
    for (final ConstraintType type in ConstraintType.values) {
      if (type.name == raw) return type;
    }
    return null;
  }
}

/// A farmer-defined operating rule.
class FarmConstraint {
  const FarmConstraint({
    required this.id,
    required this.type,
    required this.mode,
    this.numericValue = 0,
    this.textValue = '',
    this.label = '',
  });

  final String id;
  final ConstraintType type;
  final ConstraintMode mode;

  /// The farmer's threshold, interpreted per `type.direction` and `type.unit`.
  final double numericValue;

  /// Extra qualifier, currently the tag used by [ConstraintType.restrictedInput].
  final String textValue;

  /// Farmer-facing description; falls back to a generated one.
  final String label;

  bool get isActive => mode != ConstraintMode.disabled;
  bool get isHard => mode == ConstraintMode.hard;
  bool get isPreference => mode == ConstraintMode.preference;

  String get displayLabel => label.isNotEmpty ? label : type.name;

  /// Whether [actual] satisfies this constraint.
  ///
  /// Comparisons carry a small relative tolerance so that a plan landing
  /// exactly on the farmer's limit is not rejected by floating-point drift.
  bool isSatisfiedBy(double actual) {
    const double relativeTolerance = 1e-9;
    final double slack =
        (numericValue.abs() * relativeTolerance) + relativeTolerance;
    return switch (type.direction) {
      ConstraintDirection.maximum => actual <= numericValue + slack,
      ConstraintDirection.minimum => actual >= numericValue - slack,
    };
  }

  factory FarmConstraint.fromJson(Map<String, dynamic> json) {
    final ConstraintType? type = ConstraintType.tryParse(
      asString(json['type']),
    );
    if (type == null) {
      throw FormatException('Unknown constraint type: ${json['type']}');
    }
    return FarmConstraint(
      id: asString(json['id']),
      type: type,
      mode: ConstraintMode.parse(asString(json['mode'])),
      numericValue: asDouble(json['numericValue']),
      textValue: asString(json['textValue']),
      label: asString(json['label']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'type': type.name,
    'mode': mode.name,
    'numericValue': numericValue,
    'textValue': textValue,
    'label': label,
  };

  FarmConstraint copyWith({ConstraintMode? mode, double? numericValue}) =>
      FarmConstraint(
        id: id,
        type: type,
        mode: mode ?? this.mode,
        numericValue: numericValue ?? this.numericValue,
        textValue: textValue,
        label: label,
      );

  @override
  String toString() => 'FarmConstraint(${type.name}, ${mode.name})';
}

/// A constraint that a specific plan failed to satisfy.
class ConstraintViolation {
  const ConstraintViolation({
    required this.constraint,
    required this.actual,
    this.detail = '',
  });

  final FarmConstraint constraint;

  /// The value the plan actually produced, in the constraint's own unit.
  final double actual;

  /// Optional specifics, e.g. which field broke a rotation rule.
  final String detail;

  ConstraintType get type => constraint.type;
  bool get isHard => constraint.isHard;
  double get limit => constraint.numericValue;

  /// How far past the limit the plan landed, always non-negative.
  double get overage => switch (constraint.type.direction) {
    ConstraintDirection.maximum => actual - limit,
    ConstraintDirection.minimum => limit - actual,
  };

  @override
  String toString() =>
      'ConstraintViolation(${constraint.type.name}: $actual vs $limit)';
}
