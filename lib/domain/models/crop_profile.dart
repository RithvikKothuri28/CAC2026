import '../../core/utilities/json_utils.dart';

/// Agronomic and economic assumptions for one crop the farmer can plant.
///
/// Every field here is a farmer-supplied (or demo dataset) assumption.
/// FarmTwin never invents these numbers — the engines only combine them.
class CropProfile {
  const CropProfile({
    required this.id,
    required this.name,
    required this.yieldUnit,
    required this.expectedYieldPerAcre,
    required this.pricePerUnit,
    required this.seedCostPerAcre,
    required this.fertilizerCostPerAcre,
    required this.chemicalCostPerAcre,
    required this.laborCostPerAcre,
    required this.fuelCostPerAcre,
    required this.equipmentCostPerAcre,
    required this.waterAcreInchesPerAcre,
    required this.waterCostPerAcreInch,
    required this.nitrogenLbsPerAcre,
    this.compatibleSoilTypes = const <String>{},
    this.requiresIrrigation = false,
    this.cannotFollow = const <String>{},
    this.minYearsBetweenPlantings = 0,
    this.isLegume = false,
    this.providesSoilCover = false,
    this.inputTags = const <String>{},
  });

  /// Stable identifier used by allocations, history and constraints.
  final String id;
  final String name;

  /// Unit the yield is expressed in, e.g. `bu` or `ton`.
  final String yieldUnit;

  /// Baseline yield on an average field, before the field's own multiplier.
  final double expectedYieldPerAcre;

  /// Assumed commodity price, in dollars per [yieldUnit].
  final double pricePerUnit;

  final double seedCostPerAcre;
  final double fertilizerCostPerAcre;
  final double chemicalCostPerAcre;
  final double laborCostPerAcre;
  final double fuelCostPerAcre;
  final double equipmentCostPerAcre;

  /// Applied irrigation depth. Only charged on irrigated fields — a dryland
  /// field draws no water and instead carries a lower yield multiplier.
  final double waterAcreInchesPerAcre;
  final double waterCostPerAcreInch;

  /// Applied nitrogen, in pounds per acre.
  final double nitrogenLbsPerAcre;

  /// Soils this crop can be grown on. Empty means "any soil".
  final Set<String> compatibleSoilTypes;

  /// When true the crop can only be assigned to an irrigated field.
  final bool requiresIrrigation;

  /// Crop ids this crop must not directly follow, e.g. corn after corn.
  final Set<String> cannotFollow;

  /// Rest period required before this crop returns to the same field.
  /// `2` means it may not appear in either of the two preceding seasons.
  final int minYearsBetweenPlantings;

  final bool isLegume;
  final bool providesSoilCover;

  /// Practice tags such as `synthetic_nitrogen`, matched by the
  /// `restrictedInput` constraint.
  final Set<String> inputTags;

  /// Revenue per acre on an average field, before the field multiplier.
  double get revenuePerAcre => expectedYieldPerAcre * pricePerUnit;

  /// Water cost per acre, charged only where irrigation is actually applied.
  double waterCostPerAcre({required bool irrigated}) =>
      irrigated ? waterAcreInchesPerAcre * waterCostPerAcreInch : 0;

  /// Non-water variable cost per acre.
  double get nonWaterVariableCostPerAcre =>
      seedCostPerAcre +
      fertilizerCostPerAcre +
      chemicalCostPerAcre +
      laborCostPerAcre +
      fuelCostPerAcre +
      equipmentCostPerAcre;

  /// Total variable cost per acre for a field of the given irrigation status.
  double variableCostPerAcre({required bool irrigated}) =>
      nonWaterVariableCostPerAcre + waterCostPerAcre(irrigated: irrigated);

  factory CropProfile.fromJson(Map<String, dynamic> json) => CropProfile(
    id: asString(json['id']),
    name: asString(json['name']),
    yieldUnit: asString(json['yieldUnit'], fallback: 'bu'),
    expectedYieldPerAcre: asDouble(json['expectedYieldPerAcre']),
    pricePerUnit: asDouble(json['pricePerUnit']),
    seedCostPerAcre: asDouble(json['seedCostPerAcre']),
    fertilizerCostPerAcre: asDouble(json['fertilizerCostPerAcre']),
    chemicalCostPerAcre: asDouble(json['chemicalCostPerAcre']),
    laborCostPerAcre: asDouble(json['laborCostPerAcre']),
    fuelCostPerAcre: asDouble(json['fuelCostPerAcre']),
    equipmentCostPerAcre: asDouble(json['equipmentCostPerAcre']),
    waterAcreInchesPerAcre: asDouble(json['waterAcreInchesPerAcre']),
    waterCostPerAcreInch: asDouble(json['waterCostPerAcreInch']),
    nitrogenLbsPerAcre: asDouble(json['nitrogenLbsPerAcre']),
    compatibleSoilTypes: asStringSet(json['compatibleSoilTypes']),
    requiresIrrigation: asBool(json['requiresIrrigation']),
    cannotFollow: asStringSet(json['cannotFollow']),
    minYearsBetweenPlantings: asInt(json['minYearsBetweenPlantings']),
    isLegume: asBool(json['isLegume']),
    providesSoilCover: asBool(json['providesSoilCover']),
    inputTags: asStringSet(json['inputTags']),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'yieldUnit': yieldUnit,
    'expectedYieldPerAcre': expectedYieldPerAcre,
    'pricePerUnit': pricePerUnit,
    'seedCostPerAcre': seedCostPerAcre,
    'fertilizerCostPerAcre': fertilizerCostPerAcre,
    'chemicalCostPerAcre': chemicalCostPerAcre,
    'laborCostPerAcre': laborCostPerAcre,
    'fuelCostPerAcre': fuelCostPerAcre,
    'equipmentCostPerAcre': equipmentCostPerAcre,
    'waterAcreInchesPerAcre': waterAcreInchesPerAcre,
    'waterCostPerAcreInch': waterCostPerAcreInch,
    'nitrogenLbsPerAcre': nitrogenLbsPerAcre,
    'compatibleSoilTypes': compatibleSoilTypes.toList()..sort(),
    'requiresIrrigation': requiresIrrigation,
    'cannotFollow': cannotFollow.toList()..sort(),
    'minYearsBetweenPlantings': minYearsBetweenPlantings,
    'isLegume': isLegume,
    'providesSoilCover': providesSoilCover,
    'inputTags': inputTags.toList()..sort(),
  };

  CropProfile copyWith({
    double? expectedYieldPerAcre,
    double? pricePerUnit,
    double? fertilizerCostPerAcre,
    double? fuelCostPerAcre,
    double? laborCostPerAcre,
    double? waterCostPerAcreInch,
    double? waterAcreInchesPerAcre,
  }) => CropProfile(
    id: id,
    name: name,
    yieldUnit: yieldUnit,
    expectedYieldPerAcre: expectedYieldPerAcre ?? this.expectedYieldPerAcre,
    pricePerUnit: pricePerUnit ?? this.pricePerUnit,
    seedCostPerAcre: seedCostPerAcre,
    fertilizerCostPerAcre: fertilizerCostPerAcre ?? this.fertilizerCostPerAcre,
    chemicalCostPerAcre: chemicalCostPerAcre,
    laborCostPerAcre: laborCostPerAcre ?? this.laborCostPerAcre,
    fuelCostPerAcre: fuelCostPerAcre ?? this.fuelCostPerAcre,
    equipmentCostPerAcre: equipmentCostPerAcre,
    waterAcreInchesPerAcre:
        waterAcreInchesPerAcre ?? this.waterAcreInchesPerAcre,
    waterCostPerAcreInch: waterCostPerAcreInch ?? this.waterCostPerAcreInch,
    nitrogenLbsPerAcre: nitrogenLbsPerAcre,
    compatibleSoilTypes: compatibleSoilTypes,
    requiresIrrigation: requiresIrrigation,
    cannotFollow: cannotFollow,
    minYearsBetweenPlantings: minYearsBetweenPlantings,
    isLegume: isLegume,
    providesSoilCover: providesSoilCover,
    inputTags: inputTags,
  );

  @override
  String toString() => 'CropProfile($id)';
}
