import 'dart:math' as math;

/// Physical resources a farm plan consumes in one season.
class PlanResources {
  const PlanResources({
    required this.totalAcres,
    required this.waterAcreInches,
    required this.nitrogenLbs,
    required this.soilCoverAcres,
    required this.irrigatedAcresPlanted,
    required this.acresByCrop,
    required this.acresByInputTag,
  });

  final double totalAcres;

  /// Applied irrigation across the farm, in acre-inches.
  final double waterAcreInches;

  /// Applied nitrogen across the farm, in pounds.
  final double nitrogenLbs;

  /// Acres planted to a crop that provides soil cover.
  final double soilCoverAcres;

  /// Acres on irrigated ground that actually draw water this season.
  final double irrigatedAcresPlanted;

  final Map<String, double> acresByCrop;

  /// Acres carrying each practice tag, e.g. `synthetic_nitrogen`.
  final Map<String, double> acresByInputTag;

  double get waterPerAcre => totalAcres > 0 ? waterAcreInches / totalAcres : 0;
  double get nitrogenPerAcre => totalAcres > 0 ? nitrogenLbs / totalAcres : 0;

  /// Acre-feet, the unit many water rights are written in.
  double get waterAcreFeet => waterAcreInches / 12.0;

  double get soilCoverShare => totalAcres > 0 ? soilCoverAcres / totalAcres : 0;

  /// Herfindahl-Hirschman index of acreage concentration, 0..1.
  /// 1 means the whole farm is one crop.
  double get concentrationIndex {
    if (totalAcres <= 0) return 0;
    double sum = 0;
    for (final double acres in acresByCrop.values) {
      final double share = acres / totalAcres;
      sum += share * share;
    }
    return sum;
  }

  /// Shannon evenness of the crop mix, 0..1, where 1 is a perfectly even
  /// split across every crop planted. Used as the diversification objective
  /// because it rewards both more crops and a more balanced split.
  double get diversityIndex {
    if (totalAcres <= 0 || acresByCrop.length < 2) return 0;
    double entropy = 0;
    for (final double acres in acresByCrop.values) {
      if (acres <= 0) continue;
      final double share = acres / totalAcres;
      entropy -= share * math.log(share);
    }
    final double maxEntropy = math.log(acresByCrop.length);
    if (maxEntropy <= 0) return 0;
    return (entropy / maxEntropy).clamp(0.0, 1.0).toDouble();
  }

  @override
  String toString() =>
      'PlanResources(water=${waterAcreInches.toStringAsFixed(0)}ac-in, '
      'N=${nitrogenLbs.toStringAsFixed(0)}lb)';
}
