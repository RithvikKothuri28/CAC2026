import '../../core/utilities/json_utils.dart';

/// A single debt obligation carried by the farm.
class Debt {
  const Debt({
    required this.id,
    required this.name,
    required this.principal,
    required this.annualInterestRate,
    required this.annualPayment,
    required this.remainingYears,
  });

  final String id;
  final String name;

  /// Outstanding balance at the start of the plan year.
  final double principal;

  /// Nominal annual rate as a fraction, e.g. `0.0635` for 6.35%.
  final double annualInterestRate;

  /// Scheduled annual payment covering interest and principal.
  final double annualPayment;

  final int remainingYears;

  /// Interest portion of this year's payment.
  double get annualInterest => principal * annualInterestRate;

  /// Principal portion of this year's payment, floored at zero so an
  /// interest-only obligation does not report negative amortisation.
  double get annualPrincipal {
    final double reduction = annualPayment - annualInterest;
    return reduction > 0 ? reduction : 0;
  }

  /// Balance carried into the following year.
  double get endingPrincipal {
    final double remaining = principal - annualPrincipal;
    return remaining > 0 ? remaining : 0;
  }

  /// This debt rolled forward one year, for multi-year modelling.
  Debt advanceOneYear() => Debt(
    id: id,
    name: name,
    principal: endingPrincipal,
    annualInterestRate: annualInterestRate,
    annualPayment: remainingYears <= 1 ? 0 : annualPayment,
    remainingYears: remainingYears > 0 ? remainingYears - 1 : 0,
  );

  factory Debt.fromJson(Map<String, dynamic> json) => Debt(
    id: asString(json['id']),
    name: asString(json['name']),
    principal: asDouble(json['principal']),
    annualInterestRate: asDouble(json['annualInterestRate']),
    annualPayment: asDouble(json['annualPayment']),
    remainingYears: asInt(json['remainingYears']),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'principal': principal,
    'annualInterestRate': annualInterestRate,
    'annualPayment': annualPayment,
    'remainingYears': remainingYears,
  };

  Debt copyWith({double? annualInterestRate, double? annualPayment}) => Debt(
    id: id,
    name: name,
    principal: principal,
    annualInterestRate: annualInterestRate ?? this.annualInterestRate,
    annualPayment: annualPayment ?? this.annualPayment,
    remainingYears: remainingYears,
  );

  @override
  String toString() => 'Debt($id)';
}
