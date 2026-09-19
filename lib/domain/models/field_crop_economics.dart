/// Economics of planting one specific crop on one specific field.
///
/// These cells are precomputed once per optimisation run — there are only
/// `fields × crops` of them — and every candidate plan is then scored by
/// summing the cells it selects. That is what keeps a 15,625-plan search
/// fast enough to run on a phone.
class FieldCropEconomics {
  const FieldCropEconomics({
    required this.fieldId,
    required this.cropId,
    required this.acres,
    required this.yieldPerAcre,
    required this.pricePerUnit,
    required this.revenue,
    required this.seedCost,
    required this.fertilizerCost,
    required this.chemicalCost,
    required this.waterCost,
    required this.laborCost,
    required this.fuelCost,
    required this.equipmentCost,
    required this.waterAcreInches,
    required this.nitrogenLbs,
    required this.irrigated,
  });

  final String fieldId;
  final String cropId;
  final double acres;

  /// Crop baseline yield adjusted by the field's productivity multiplier.
  final double yieldPerAcre;
  final double pricePerUnit;

  /// Total production from this field, in the crop's yield unit.
  double get production => yieldPerAcre * acres;

  final double revenue;

  final double seedCost;
  final double fertilizerCost;
  final double chemicalCost;
  final double waterCost;
  final double laborCost;
  final double fuelCost;
  final double equipmentCost;

  final double waterAcreInches;
  final double nitrogenLbs;
  final bool irrigated;

  double get variableCost =>
      seedCost +
      fertilizerCost +
      chemicalCost +
      waterCost +
      laborCost +
      fuelCost +
      equipmentCost;

  /// Revenue less the variable cost of growing it — the amount this field
  /// contributes toward fixed costs and debt service.
  double get contributionMargin => revenue - variableCost;

  double get contributionMarginPerAcre =>
      acres > 0 ? contributionMargin / acres : 0;

  @override
  String toString() => 'FieldCropEconomics($fieldId/$cropId)';
}
