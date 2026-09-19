import '../../core/utilities/json_utils.dart';

/// How much each assumption is allowed to move in a simulation.
///
/// Standard deviations are expressed as fractions of the expected value, so
/// `0.18` means a one-standard-deviation yield swing of 18%.
class UncertaintyModel {
  const UncertaintyModel({
    required this.weatherYieldStdDev,
    required this.cropYieldStdDev,
    required this.cropPriceStdDev,
    required this.fertilizerPriceStdDev,
    required this.fuelPriceStdDev,
    required this.priceYieldElasticity,
    required this.equipmentFailureProbability,
    required this.equipmentFailureCost,
    this.minYieldFactor = 0.30,
    this.maxYieldFactor = 1.55,
    this.minPriceFactor = 0.55,
    this.maxPriceFactor = 1.85,
  });

  /// Region-wide growing conditions, applied to every crop in a trial. This
  /// is the shock that matters most: a dry year hits the whole farm at once,
  /// which is exactly what independent per-crop draws would hide.
  final double weatherYieldStdDev;

  /// Crop-specific yield variation on top of the shared weather draw.
  final double cropYieldStdDev;

  /// Commodity price variation, independent of yield.
  final double cropPriceStdDev;

  final double fertilizerPriceStdDev;
  final double fuelPriceStdDev;

  /// How strongly a regional yield shortfall lifts commodity price.
  ///
  /// `0.6` means a 10% region-wide yield loss is accompanied by roughly a 6%
  /// price rise. This partial natural hedge is why a farm's income is less
  /// volatile than its yield, and omitting it would overstate downside risk.
  final double priceYieldElasticity;

  /// Chance of a significant unplanned equipment cost in the season.
  final double equipmentFailureProbability;

  /// Size of that cost when it happens.
  final double equipmentFailureCost;

  final double minYieldFactor;
  final double maxYieldFactor;
  final double minPriceFactor;
  final double maxPriceFactor;

  /// A moderate, broadly representative set of assumptions for row-crop
  /// agriculture. These are defaults to be edited, not measurements — the
  /// farmer should replace them with their own history.
  factory UncertaintyModel.standard() => const UncertaintyModel(
    weatherYieldStdDev: 0.14,
    cropYieldStdDev: 0.07,
    cropPriceStdDev: 0.16,
    fertilizerPriceStdDev: 0.18,
    fuelPriceStdDev: 0.20,
    priceYieldElasticity: 0.60,
    equipmentFailureProbability: 0.18,
    equipmentFailureCost: 32000,
  );

  /// Everything held still. Used to prove that the simulation collapses to
  /// the deterministic result when no uncertainty is supplied.
  factory UncertaintyModel.none() => const UncertaintyModel(
    weatherYieldStdDev: 0,
    cropYieldStdDev: 0,
    cropPriceStdDev: 0,
    fertilizerPriceStdDev: 0,
    fuelPriceStdDev: 0,
    priceYieldElasticity: 0,
    equipmentFailureProbability: 0,
    equipmentFailureCost: 0,
  );

  UncertaintyModel copyWith({
    double? weatherYieldStdDev,
    double? cropPriceStdDev,
    double? fertilizerPriceStdDev,
    double? fuelPriceStdDev,
    double? equipmentFailureProbability,
  }) => UncertaintyModel(
    weatherYieldStdDev: weatherYieldStdDev ?? this.weatherYieldStdDev,
    cropYieldStdDev: cropYieldStdDev,
    cropPriceStdDev: cropPriceStdDev ?? this.cropPriceStdDev,
    fertilizerPriceStdDev: fertilizerPriceStdDev ?? this.fertilizerPriceStdDev,
    fuelPriceStdDev: fuelPriceStdDev ?? this.fuelPriceStdDev,
    priceYieldElasticity: priceYieldElasticity,
    equipmentFailureProbability:
        equipmentFailureProbability ?? this.equipmentFailureProbability,
    equipmentFailureCost: equipmentFailureCost,
    minYieldFactor: minYieldFactor,
    maxYieldFactor: maxYieldFactor,
    minPriceFactor: minPriceFactor,
    maxPriceFactor: maxPriceFactor,
  );

  factory UncertaintyModel.fromJson(Map<String, dynamic> json) =>
      UncertaintyModel(
        weatherYieldStdDev: asDouble(json['weatherYieldStdDev']),
        cropYieldStdDev: asDouble(json['cropYieldStdDev']),
        cropPriceStdDev: asDouble(json['cropPriceStdDev']),
        fertilizerPriceStdDev: asDouble(json['fertilizerPriceStdDev']),
        fuelPriceStdDev: asDouble(json['fuelPriceStdDev']),
        priceYieldElasticity: asDouble(json['priceYieldElasticity']),
        equipmentFailureProbability: asDouble(
          json['equipmentFailureProbability'],
        ),
        equipmentFailureCost: asDouble(json['equipmentFailureCost']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'weatherYieldStdDev': weatherYieldStdDev,
    'cropYieldStdDev': cropYieldStdDev,
    'cropPriceStdDev': cropPriceStdDev,
    'fertilizerPriceStdDev': fertilizerPriceStdDev,
    'fuelPriceStdDev': fuelPriceStdDev,
    'priceYieldElasticity': priceYieldElasticity,
    'equipmentFailureProbability': equipmentFailureProbability,
    'equipmentFailureCost': equipmentFailureCost,
  };
}
