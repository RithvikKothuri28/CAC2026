/// The full financial picture of one farm plan for one season.
///
/// Every value is derived arithmetically from farmer-supplied assumptions.
/// Nothing here is estimated by a model.
class PlanFinancials {
  const PlanFinancials({
    required this.totalAcres,
    required this.totalRevenue,
    required this.seedExpense,
    required this.fertilizerExpense,
    required this.chemicalExpense,
    required this.waterExpense,
    required this.laborExpense,
    required this.fuelExpense,
    required this.equipmentExpense,
    required this.fixedExpense,
    required this.debtService,
    required this.debtInterest,
    required this.acresByCrop,
    required this.revenueByCrop,
    required this.contributionMarginByCrop,
    required this.productionByCrop,
    required this.breakEvenPriceByCrop,
    required this.breakEvenYieldByCrop,
  });

  final double totalAcres;
  final double totalRevenue;

  final double seedExpense;
  final double fertilizerExpense;
  final double chemicalExpense;
  final double waterExpense;
  final double laborExpense;
  final double fuelExpense;
  final double equipmentExpense;

  /// Farm-level costs that do not follow the crop allocation.
  final double fixedExpense;

  /// Scheduled principal and interest for the season.
  final double debtService;

  /// Interest portion of [debtService], reported separately because coverage
  /// ratios and multi-year models treat principal differently.
  final double debtInterest;

  /// Acres planted to each crop, keyed by crop id.
  final Map<String, double> acresByCrop;
  final Map<String, double> revenueByCrop;
  final Map<String, double> contributionMarginByCrop;

  /// Total production per crop, in that crop's own yield unit.
  final Map<String, double> productionByCrop;

  /// Price at which each crop's acreage covers its variable cost plus its
  /// acreage-weighted share of fixed cost and debt service.
  final Map<String, double> breakEvenPriceByCrop;

  /// Yield per acre needed to cover the same costs at the assumed price.
  final Map<String, double> breakEvenYieldByCrop;

  /// Costs that follow the acre.
  double get variableExpense =>
      seedExpense +
      fertilizerExpense +
      chemicalExpense +
      waterExpense +
      laborExpense +
      fuelExpense +
      equipmentExpense;

  /// Variable plus fixed cost. Debt service is excluded — it is a financing
  /// obligation, not an operating expense.
  double get totalOperatingExpense => variableExpense + fixedExpense;

  /// Revenue less variable cost: what is available to cover fixed costs.
  double get contributionMargin => totalRevenue - variableExpense;

  /// Earnings from operations, before financing.
  double get operatingIncome => contributionMargin - fixedExpense;

  /// What is left once the bank is paid.
  double get cashAfterDebtService => operatingIncome - debtService;

  double get marginPerAcre => totalAcres > 0 ? operatingIncome / totalAcres : 0;

  double get contributionMarginPerAcre =>
      totalAcres > 0 ? contributionMargin / totalAcres : 0;

  double get revenuePerAcre => totalAcres > 0 ? totalRevenue / totalAcres : 0;

  /// Operating income as a share of revenue — the cushion the plan carries
  /// before a price or yield shortfall turns into a loss.
  double get operatingMarginRatio =>
      totalRevenue > 0 ? operatingIncome / totalRevenue : 0;

  /// Contribution margin as a share of revenue.
  double get contributionMarginRatio =>
      totalRevenue > 0 ? contributionMargin / totalRevenue : 0;

  /// Operating income divided by debt service.
  ///
  /// With no debt the ratio is undefined; [debtServiceCoverageRatio] reports
  /// [double.infinity] there so callers can decide how to present it.
  double get debtServiceCoverageRatio {
    if (debtService <= 0) return double.infinity;
    return operatingIncome / debtService;
  }

  /// Coverage clamped into a finite range, for scoring and charting.
  double clampedCoverage({double cap = 3.0}) {
    if (debtService <= 0) return operatingIncome > 0 ? cap : 0;
    final double ratio = operatingIncome / debtService;
    if (ratio.isNaN) return 0;
    return ratio.clamp(-cap, cap).toDouble();
  }

  /// Distinct crops in the plan.
  int get cropCount => acresByCrop.keys.length;

  /// Share of farm acres held by the single largest crop.
  double get maxCropConcentration {
    if (totalAcres <= 0 || acresByCrop.isEmpty) return 0;
    double largest = 0;
    for (final double acres in acresByCrop.values) {
      if (acres > largest) largest = acres;
    }
    return largest / totalAcres;
  }

  @override
  String toString() =>
      'PlanFinancials(income=${operatingIncome.toStringAsFixed(0)}, '
      'cash=${cashAfterDebtService.toStringAsFixed(0)})';
}
