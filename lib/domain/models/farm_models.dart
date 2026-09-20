import 'dart:math' as math;

const currentSchemaVersion = 1;
const numericTolerance = 1e-9;

abstract class DomainFailure implements Exception {
  final String message;
  final Map<String, Object?> details;
  const DomainFailure(this.message, [this.details = const {}]);
  @override
  String toString() => message;
}

class ValidationFailure extends DomainFailure {
  const ValidationFailure(super.message, [super.details]);
}

class DataUnavailableFailure extends DomainFailure {
  const DataUnavailableFailure(super.message, [super.details]);
}

class OptimizationFailure extends DomainFailure {
  const OptimizationFailure(super.message, [super.details]);
}

class SimulationFailure extends DomainFailure {
  const SimulationFailure(super.message, [super.details]);
}

enum DataSourceType {
  userEntered,
  imported,
  externalProvider,
  configuredDefault,
  sample,
}

enum ConstraintKind {
  maxWater,
  maxNitrogen,
  maxOperatingExpense,
  minOperatingIncome,
  maxConcentration,
  minDiversity,
  rotation,
  restrictedInputs,
  minLiquidity,
  minDebtCoverage,
  minSoilCover,
  maxDebt,
}

enum ConstraintMode { hard, preference, disabled }

enum Objective {
  profit,
  resilience,
  waterEfficiency,
  inputEfficiency,
  practiceAlignment,
  diversification,
}

enum AlertSeverity { information, warning, critical }

double _number(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num || !value.toDouble().isFinite) {
    throw ValidationFailure('A finite number is required for $key.');
  }
  return value.toDouble();
}

int _integer(Map<String, dynamic> json, String key) {
  final n = _number(json, key);
  if (n != n.truncateToDouble()) {
    throw ValidationFailure('$key must be an integer.');
  }
  return n.toInt();
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) throw ValidationFailure('Text is required for $key.');
  return value;
}

bool _boolean(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) {
    throw ValidationFailure('A boolean is required for $key.');
  }
  return value;
}

Map<String, dynamic> _object(Object? value, String key) {
  if (value is! Map) throw ValidationFailure('An object is required for $key.');
  return Map<String, dynamic>.from(value);
}

List<dynamic> _list(Map<String, dynamic> json, String key) {
  if (json[key] is! List) {
    throw ValidationFailure('A list is required for $key.');
  }
  return json[key] as List<dynamic>;
}

T _enum<T extends Enum>(List<T> values, Object? value, String key) =>
    values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw ValidationFailure('Unknown $key: $value.'),
    );
void _finite(
  double value,
  String name, {
  double? min,
  double? max,
  bool positive = false,
}) {
  if (!value.isFinite ||
      (min != null && value < min) ||
      (max != null && value > max) ||
      (positive && value <= 0)) {
    throw ValidationFailure('Invalid $name.', {
      'value': value,
      'minimum': min,
      'maximum': max,
    });
  }
}

void _text(String value, String name) {
  if (value.trim().isEmpty) throw ValidationFailure('$name is required.');
}

void _unique(Iterable<String> ids, String name) {
  final all = ids.toList();
  if (all.toSet().length != all.length) {
    throw ValidationFailure('Duplicate $name identifiers.');
  }
}

class Provenance {
  final DataSourceType source;
  final DateTime updatedAt;
  final String? provider;
  final DateTime? retrievedAt;
  final DateTime? effectiveDate;
  final String? quality;
  Provenance({
    required this.source,
    required this.updatedAt,
    this.provider,
    this.retrievedAt,
    this.effectiveDate,
    this.quality,
  });
  factory Provenance.fromJson(Map<String, dynamic> json) {
    try {
      return Provenance(
        source: _enum(DataSourceType.values, json['source'], 'source'),
        updatedAt: DateTime.parse(_string(json, 'updatedAt')),
        provider: json['provider'] as String?,
        retrievedAt: json['retrievedAt'] == null
            ? null
            : DateTime.parse(_string(json, 'retrievedAt')),
        effectiveDate: json['effectiveDate'] == null
            ? null
            : DateTime.parse(_string(json, 'effectiveDate')),
        quality: json['quality'] as String?,
      );
    } on DomainFailure {
      rethrow;
    } catch (e) {
      throw ValidationFailure('Invalid Provenance data.', {
        'cause': e.toString(),
      });
    }
  }
  Map<String, dynamic> toJson() => {
    'source': source.name,
    'updatedAt': updatedAt.toIso8601String(),
    'provider': provider,
    'retrievedAt': retrievedAt?.toIso8601String(),
    'effectiveDate': effectiveDate?.toIso8601String(),
    'quality': quality,
  };
  Provenance copyWith({
    DataSourceType? source,
    DateTime? updatedAt,
    String? provider,
    DateTime? retrievedAt,
    DateTime? effectiveDate,
    String? quality,
  }) => Provenance(
    source: source ?? this.source,
    updatedAt: updatedAt ?? this.updatedAt,
    provider: provider ?? this.provider,
    retrievedAt: retrievedAt ?? this.retrievedAt,
    effectiveDate: effectiveDate ?? this.effectiveDate,
    quality: quality ?? this.quality,
  );
}

class Field {
  final String id;
  final String name;
  final double acres;
  final String currentCropId;
  final List<String> compatibleCropIds;
  final List<String> cropHistory;
  final bool irrigated;
  final String soilType;
  final double yieldMultiplier;
  final Provenance provenance;
  Field({
    required this.id,
    required this.name,
    required this.acres,
    required this.currentCropId,
    required List<String> compatibleCropIds,
    List<String> cropHistory = const [],
    this.irrigated = true,
    this.soilType = '',
    this.yieldMultiplier = 1,
    required this.provenance,
  }) : compatibleCropIds = List.unmodifiable(compatibleCropIds),
       cropHistory = List.unmodifiable(cropHistory);
  factory Field.fromJson(Map<String, dynamic> json) {
    try {
      return Field(
        id: _string(json, 'id'),
        name: _string(json, 'name'),
        acres: _number(json, 'acres'),
        currentCropId: _string(json, 'currentCropId'),
        compatibleCropIds: _list(
          json,
          'compatibleCropIds',
        ).map((v) => _string({'value': v}, 'value')).toList(),
        cropHistory: json.containsKey('cropHistory')
            ? _list(
                json,
                'cropHistory',
              ).map((v) => _string({'value': v}, 'value')).toList()
            : const [],
        irrigated: json.containsKey('irrigated')
            ? _boolean(json, 'irrigated')
            : true,
        soilType: json.containsKey('soilType') ? _string(json, 'soilType') : '',
        yieldMultiplier: json.containsKey('yieldMultiplier')
            ? _number(json, 'yieldMultiplier')
            : 1,
        provenance: Provenance.fromJson(
          _object(json['provenance'], 'provenance'),
        ),
      );
    } on DomainFailure {
      rethrow;
    } catch (e) {
      throw ValidationFailure('Invalid Field data.', {'cause': e.toString()});
    }
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'acres': acres,
    'currentCropId': currentCropId,
    'compatibleCropIds': compatibleCropIds,
    'cropHistory': cropHistory,
    'irrigated': irrigated,
    'soilType': soilType,
    'yieldMultiplier': yieldMultiplier,
    'provenance': provenance.toJson(),
  };
  Field copyWith({
    String? id,
    String? name,
    double? acres,
    String? currentCropId,
    List<String>? compatibleCropIds,
    List<String>? cropHistory,
    bool? irrigated,
    String? soilType,
    double? yieldMultiplier,
    Provenance? provenance,
  }) => Field(
    id: id ?? this.id,
    name: name ?? this.name,
    acres: acres ?? this.acres,
    currentCropId: currentCropId ?? this.currentCropId,
    compatibleCropIds: compatibleCropIds ?? this.compatibleCropIds,
    cropHistory: cropHistory ?? this.cropHistory,
    irrigated: irrigated ?? this.irrigated,
    soilType: soilType ?? this.soilType,
    yieldMultiplier: yieldMultiplier ?? this.yieldMultiplier,
    provenance: provenance ?? this.provenance,
  );
  void validate() {
    _text(id, 'Field id');
    _text(name, 'Field name');
    _finite(acres, 'Acreage', positive: true);
    _finite(yieldMultiplier, 'Field yield multiplier', min: 0);
    _unique(compatibleCropIds, 'compatible crop');
  }
}

class CropProfile {
  final String id;
  final String name;
  final double yieldPerAcre;
  final double pricePerUnit;
  final String yieldUnit;
  final double seedCostPerAcre;
  final double fertilizerCostPerAcre;
  final double chemicalCostPerAcre;
  final double waterCostPerAcre;
  final double laborCostPerAcre;
  final double fuelCostPerAcre;
  final double equipmentCostPerAcre;
  final double waterPerAcre;
  final double nitrogenPerAcre;
  final double yieldVolatility;
  final double priceVolatility;
  final String rotationFamily;
  final int minimumRotationYears;
  final bool requiresIrrigation;
  final List<String> inputs;
  final bool providesSoilCover;
  final Provenance provenance;
  CropProfile({
    required this.id,
    required this.name,
    required this.yieldPerAcre,
    required this.pricePerUnit,
    required this.yieldUnit,
    required this.seedCostPerAcre,
    required this.fertilizerCostPerAcre,
    required this.chemicalCostPerAcre,
    required this.waterCostPerAcre,
    required this.laborCostPerAcre,
    required this.fuelCostPerAcre,
    required this.equipmentCostPerAcre,
    required this.waterPerAcre,
    required this.nitrogenPerAcre,
    required this.yieldVolatility,
    required this.priceVolatility,
    required this.rotationFamily,
    required this.minimumRotationYears,
    required this.requiresIrrigation,
    required List<String> inputs,
    required this.providesSoilCover,
    required this.provenance,
  }) : inputs = List.unmodifiable(inputs);
  factory CropProfile.fromJson(Map<String, dynamic> json) {
    try {
      return CropProfile(
        id: _string(json, 'id'),
        name: _string(json, 'name'),
        yieldPerAcre: _number(json, 'yieldPerAcre'),
        pricePerUnit: _number(json, 'pricePerUnit'),
        yieldUnit: _string(json, 'yieldUnit'),
        seedCostPerAcre: _number(json, 'seedCostPerAcre'),
        fertilizerCostPerAcre: _number(json, 'fertilizerCostPerAcre'),
        chemicalCostPerAcre: _number(json, 'chemicalCostPerAcre'),
        waterCostPerAcre: _number(json, 'waterCostPerAcre'),
        laborCostPerAcre: _number(json, 'laborCostPerAcre'),
        fuelCostPerAcre: _number(json, 'fuelCostPerAcre'),
        equipmentCostPerAcre: _number(json, 'equipmentCostPerAcre'),
        waterPerAcre: _number(json, 'waterPerAcre'),
        nitrogenPerAcre: _number(json, 'nitrogenPerAcre'),
        yieldVolatility: _number(json, 'yieldVolatility'),
        priceVolatility: _number(json, 'priceVolatility'),
        rotationFamily: _string(json, 'rotationFamily'),
        minimumRotationYears: _integer(json, 'minimumRotationYears'),
        requiresIrrigation: _boolean(json, 'requiresIrrigation'),
        inputs: _list(
          json,
          'inputs',
        ).map((v) => _string({'value': v}, 'value')).toList(),
        providesSoilCover: _boolean(json, 'providesSoilCover'),
        provenance: Provenance.fromJson(
          _object(json['provenance'], 'provenance'),
        ),
      );
    } on DomainFailure {
      rethrow;
    } catch (e) {
      throw ValidationFailure('Invalid CropProfile data.', {
        'cause': e.toString(),
      });
    }
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'yieldPerAcre': yieldPerAcre,
    'pricePerUnit': pricePerUnit,
    'yieldUnit': yieldUnit,
    'seedCostPerAcre': seedCostPerAcre,
    'fertilizerCostPerAcre': fertilizerCostPerAcre,
    'chemicalCostPerAcre': chemicalCostPerAcre,
    'waterCostPerAcre': waterCostPerAcre,
    'laborCostPerAcre': laborCostPerAcre,
    'fuelCostPerAcre': fuelCostPerAcre,
    'equipmentCostPerAcre': equipmentCostPerAcre,
    'waterPerAcre': waterPerAcre,
    'nitrogenPerAcre': nitrogenPerAcre,
    'yieldVolatility': yieldVolatility,
    'priceVolatility': priceVolatility,
    'rotationFamily': rotationFamily,
    'minimumRotationYears': minimumRotationYears,
    'requiresIrrigation': requiresIrrigation,
    'inputs': inputs,
    'providesSoilCover': providesSoilCover,
    'provenance': provenance.toJson(),
  };
  CropProfile copyWith({
    String? id,
    String? name,
    double? yieldPerAcre,
    double? pricePerUnit,
    String? yieldUnit,
    double? seedCostPerAcre,
    double? fertilizerCostPerAcre,
    double? chemicalCostPerAcre,
    double? waterCostPerAcre,
    double? laborCostPerAcre,
    double? fuelCostPerAcre,
    double? equipmentCostPerAcre,
    double? waterPerAcre,
    double? nitrogenPerAcre,
    double? yieldVolatility,
    double? priceVolatility,
    String? rotationFamily,
    int? minimumRotationYears,
    bool? requiresIrrigation,
    List<String>? inputs,
    bool? providesSoilCover,
    Provenance? provenance,
  }) => CropProfile(
    id: id ?? this.id,
    name: name ?? this.name,
    yieldPerAcre: yieldPerAcre ?? this.yieldPerAcre,
    pricePerUnit: pricePerUnit ?? this.pricePerUnit,
    yieldUnit: yieldUnit ?? this.yieldUnit,
    seedCostPerAcre: seedCostPerAcre ?? this.seedCostPerAcre,
    fertilizerCostPerAcre: fertilizerCostPerAcre ?? this.fertilizerCostPerAcre,
    chemicalCostPerAcre: chemicalCostPerAcre ?? this.chemicalCostPerAcre,
    waterCostPerAcre: waterCostPerAcre ?? this.waterCostPerAcre,
    laborCostPerAcre: laborCostPerAcre ?? this.laborCostPerAcre,
    fuelCostPerAcre: fuelCostPerAcre ?? this.fuelCostPerAcre,
    equipmentCostPerAcre: equipmentCostPerAcre ?? this.equipmentCostPerAcre,
    waterPerAcre: waterPerAcre ?? this.waterPerAcre,
    nitrogenPerAcre: nitrogenPerAcre ?? this.nitrogenPerAcre,
    yieldVolatility: yieldVolatility ?? this.yieldVolatility,
    priceVolatility: priceVolatility ?? this.priceVolatility,
    rotationFamily: rotationFamily ?? this.rotationFamily,
    minimumRotationYears: minimumRotationYears ?? this.minimumRotationYears,
    requiresIrrigation: requiresIrrigation ?? this.requiresIrrigation,
    inputs: inputs ?? this.inputs,
    providesSoilCover: providesSoilCover ?? this.providesSoilCover,
    provenance: provenance ?? this.provenance,
  );
  double get costPerAcre =>
      seedCostPerAcre +
      fertilizerCostPerAcre +
      chemicalCostPerAcre +
      waterCostPerAcre +
      laborCostPerAcre +
      fuelCostPerAcre +
      equipmentCostPerAcre;
  void validate() {
    _text(id, 'Crop id');
    _text(name, 'Crop name');
    _text(yieldUnit, 'Yield unit');
    _text(rotationFamily, 'Rotation family');
    for (final e in <String, double>{
      'yield': yieldPerAcre,
      'price': pricePerUnit,
      'seed': seedCostPerAcre,
      'fertilizer': fertilizerCostPerAcre,
      'chemical': chemicalCostPerAcre,
      'water cost': waterCostPerAcre,
      'labor': laborCostPerAcre,
      'fuel': fuelCostPerAcre,
      'equipment': equipmentCostPerAcre,
      'water requirement': waterPerAcre,
      'nitrogen': nitrogenPerAcre,
      'yield volatility': yieldVolatility,
      'price volatility': priceVolatility,
    }.entries) {
      _finite(e.value, e.key, min: 0);
    }
    if (minimumRotationYears < 0) {
      throw const ValidationFailure('Rotation interval cannot be negative.');
    }
  }
}

class Expense {
  final String id;
  final String name;
  final double annualAmount;
  final double inflationRate;
  final Provenance provenance;
  Expense({
    required this.id,
    required this.name,
    required this.annualAmount,
    required this.inflationRate,
    required this.provenance,
  });
  factory Expense.fromJson(Map<String, dynamic> json) {
    try {
      return Expense(
        id: _string(json, 'id'),
        name: _string(json, 'name'),
        annualAmount: _number(json, 'annualAmount'),
        inflationRate: _number(json, 'inflationRate'),
        provenance: Provenance.fromJson(
          _object(json['provenance'], 'provenance'),
        ),
      );
    } on DomainFailure {
      rethrow;
    } catch (e) {
      throw ValidationFailure('Invalid Expense data.', {'cause': e.toString()});
    }
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'annualAmount': annualAmount,
    'inflationRate': inflationRate,
    'provenance': provenance.toJson(),
  };
  Expense copyWith({
    String? id,
    String? name,
    double? annualAmount,
    double? inflationRate,
    Provenance? provenance,
  }) => Expense(
    id: id ?? this.id,
    name: name ?? this.name,
    annualAmount: annualAmount ?? this.annualAmount,
    inflationRate: inflationRate ?? this.inflationRate,
    provenance: provenance ?? this.provenance,
  );
  void validate() {
    _text(id, 'Expense id');
    _text(name, 'Expense name');
    _finite(annualAmount, 'Annual expense', min: 0);
    _finite(inflationRate, 'Expense inflation', min: -1);
  }
}

class Debt {
  final String id;
  final String name;
  final double balance;
  final double annualInterestRate;
  final double annualPayment;
  final Provenance provenance;
  Debt({
    required this.id,
    required this.name,
    required this.balance,
    required this.annualInterestRate,
    required this.annualPayment,
    required this.provenance,
  });
  factory Debt.fromJson(Map<String, dynamic> json) {
    try {
      return Debt(
        id: _string(json, 'id'),
        name: _string(json, 'name'),
        balance: _number(json, 'balance'),
        annualInterestRate: _number(json, 'annualInterestRate'),
        annualPayment: _number(json, 'annualPayment'),
        provenance: Provenance.fromJson(
          _object(json['provenance'], 'provenance'),
        ),
      );
    } on DomainFailure {
      rethrow;
    } catch (e) {
      throw ValidationFailure('Invalid Debt data.', {'cause': e.toString()});
    }
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'balance': balance,
    'annualInterestRate': annualInterestRate,
    'annualPayment': annualPayment,
    'provenance': provenance.toJson(),
  };
  Debt copyWith({
    String? id,
    String? name,
    double? balance,
    double? annualInterestRate,
    double? annualPayment,
    Provenance? provenance,
  }) => Debt(
    id: id ?? this.id,
    name: name ?? this.name,
    balance: balance ?? this.balance,
    annualInterestRate: annualInterestRate ?? this.annualInterestRate,
    annualPayment: annualPayment ?? this.annualPayment,
    provenance: provenance ?? this.provenance,
  );
  double get interest => balance * annualInterestRate;
  double get paymentDue => math.min(annualPayment, balance + interest);
  double get nextBalance => math.max(0, balance + interest - paymentDue);
  void validate() {
    _text(id, 'Debt id');
    _text(name, 'Debt name');
    _finite(balance, 'Debt balance', min: 0);
    _finite(annualInterestRate, 'Interest rate', min: 0);
    _finite(annualPayment, 'Debt payment', min: 0);
  }
}

class FarmConstraint {
  final String id;
  final String name;
  final ConstraintKind kind;
  final ConstraintMode mode;
  final double limit;
  final List<String> restrictedInputs;
  FarmConstraint({
    required this.id,
    required this.name,
    required this.kind,
    required this.mode,
    required this.limit,
    List<String> restrictedInputs = const [],
  }) : restrictedInputs = List.unmodifiable(restrictedInputs);
  factory FarmConstraint.fromJson(Map<String, dynamic> json) {
    try {
      return FarmConstraint(
        id: _string(json, 'id'),
        name: _string(json, 'name'),
        kind: _enum(ConstraintKind.values, json['kind'], 'kind'),
        mode: _enum(ConstraintMode.values, json['mode'], 'mode'),
        limit: _number(json, 'limit'),
        restrictedInputs: json.containsKey('restrictedInputs')
            ? _list(
                json,
                'restrictedInputs',
              ).map((v) => _string({'value': v}, 'value')).toList()
            : const [],
      );
    } on DomainFailure {
      rethrow;
    } catch (e) {
      throw ValidationFailure('Invalid FarmConstraint data.', {
        'cause': e.toString(),
      });
    }
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'mode': mode.name,
    'limit': limit,
    'restrictedInputs': restrictedInputs,
  };
  FarmConstraint copyWith({
    String? id,
    String? name,
    ConstraintKind? kind,
    ConstraintMode? mode,
    double? limit,
    List<String>? restrictedInputs,
  }) => FarmConstraint(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    mode: mode ?? this.mode,
    limit: limit ?? this.limit,
    restrictedInputs: restrictedInputs ?? this.restrictedInputs,
  );
  void validate() {
    _text(id, 'Constraint id');
    _text(name, 'Constraint name');
    _finite(limit, 'Constraint limit');
    if (kind != ConstraintKind.minOperatingIncome &&
        kind != ConstraintKind.minLiquidity &&
        limit < 0) {
      throw const ValidationFailure(
        'This constraint limit cannot be negative.',
      );
    }
    if ((kind == ConstraintKind.maxConcentration ||
            kind == ConstraintKind.minSoilCover) &&
        (limit < 0 || limit > 1)) {
      throw const ValidationFailure(
        'Proportions must be between zero and one.',
      );
    }
    if (kind == ConstraintKind.minDiversity && limit != limit.roundToDouble()) {
      throw const ValidationFailure('Crop diversity must be an integer.');
    }
  }
}

class OptimizationConfig {
  final Map<Objective, double> weights;
  final int exhaustiveLimit;
  final int candidateLimit;
  final int frontierLimit;
  final int seed;
  OptimizationConfig({
    required Map<Objective, double> weights,
    required this.exhaustiveLimit,
    required this.candidateLimit,
    required this.frontierLimit,
    required this.seed,
  }) : weights = Map.unmodifiable(weights);
  factory OptimizationConfig.fromJson(Map<String, dynamic> json) {
    try {
      return OptimizationConfig(
        weights: _object(json['weights'], 'weights').map(
          (k, v) => MapEntry(
            _enum(Objective.values, k, 'objective'),
            _number({'value': v}, 'value'),
          ),
        ),
        exhaustiveLimit: _integer(json, 'exhaustiveLimit'),
        candidateLimit: _integer(json, 'candidateLimit'),
        frontierLimit: _integer(json, 'frontierLimit'),
        seed: _integer(json, 'seed'),
      );
    } on DomainFailure {
      rethrow;
    } catch (e) {
      throw ValidationFailure('Invalid OptimizationConfig data.', {
        'cause': e.toString(),
      });
    }
  }
  Map<String, dynamic> toJson() => {
    'weights': weights.map((k, v) => MapEntry(k.name, v)),
    'exhaustiveLimit': exhaustiveLimit,
    'candidateLimit': candidateLimit,
    'frontierLimit': frontierLimit,
    'seed': seed,
  };
  OptimizationConfig copyWith({
    Map<Objective, double>? weights,
    int? exhaustiveLimit,
    int? candidateLimit,
    int? frontierLimit,
    int? seed,
  }) => OptimizationConfig(
    weights: weights ?? this.weights,
    exhaustiveLimit: exhaustiveLimit ?? this.exhaustiveLimit,
    candidateLimit: candidateLimit ?? this.candidateLimit,
    frontierLimit: frontierLimit ?? this.frontierLimit,
    seed: seed ?? this.seed,
  );
  void validate() {
    if (weights.isEmpty) {
      throw const ValidationFailure(
        'At least one optimization objective is required.',
      );
    }
    for (final e in weights.entries) {
      _finite(e.value, 'Objective weight', min: 0, max: 1);
    }
    final total = weights.values.fold(0.0, (a, b) => a + b);
    if ((total - 1).abs() > numericTolerance) {
      throw const ValidationFailure('Optimization weights must total 100%.');
    }
    if (exhaustiveLimit < 1 || candidateLimit < 1 || frontierLimit < 1) {
      throw const ValidationFailure('Search limits must be positive.');
    }
    if (exhaustiveLimit > 1000000 ||
        candidateLimit > 1000000 ||
        frontierLimit > 10000) {
      throw const OptimizationFailure(
        'Search limits exceed the supported on-device safety limits.',
      );
    }
  }
}

class SimulationConfig {
  final int iterations;
  final int seed;
  final double weatherCorrelation;
  final double marketCorrelation;
  final double fertilizerVolatility;
  final double fuelVolatility;
  final double waterVolatility;
  final double equipmentFailureProbability;
  final double equipmentFailureCost;
  SimulationConfig({
    required this.iterations,
    required this.seed,
    required this.weatherCorrelation,
    required this.marketCorrelation,
    required this.fertilizerVolatility,
    required this.fuelVolatility,
    required this.waterVolatility,
    required this.equipmentFailureProbability,
    required this.equipmentFailureCost,
  });
  factory SimulationConfig.fromJson(Map<String, dynamic> json) {
    try {
      return SimulationConfig(
        iterations: _integer(json, 'iterations'),
        seed: _integer(json, 'seed'),
        weatherCorrelation: _number(json, 'weatherCorrelation'),
        marketCorrelation: _number(json, 'marketCorrelation'),
        fertilizerVolatility: _number(json, 'fertilizerVolatility'),
        fuelVolatility: _number(json, 'fuelVolatility'),
        waterVolatility: _number(json, 'waterVolatility'),
        equipmentFailureProbability: _number(
          json,
          'equipmentFailureProbability',
        ),
        equipmentFailureCost: _number(json, 'equipmentFailureCost'),
      );
    } on DomainFailure {
      rethrow;
    } catch (e) {
      throw ValidationFailure('Invalid SimulationConfig data.', {
        'cause': e.toString(),
      });
    }
  }
  Map<String, dynamic> toJson() => {
    'iterations': iterations,
    'seed': seed,
    'weatherCorrelation': weatherCorrelation,
    'marketCorrelation': marketCorrelation,
    'fertilizerVolatility': fertilizerVolatility,
    'fuelVolatility': fuelVolatility,
    'waterVolatility': waterVolatility,
    'equipmentFailureProbability': equipmentFailureProbability,
    'equipmentFailureCost': equipmentFailureCost,
  };
  SimulationConfig copyWith({
    int? iterations,
    int? seed,
    double? weatherCorrelation,
    double? marketCorrelation,
    double? fertilizerVolatility,
    double? fuelVolatility,
    double? waterVolatility,
    double? equipmentFailureProbability,
    double? equipmentFailureCost,
  }) => SimulationConfig(
    iterations: iterations ?? this.iterations,
    seed: seed ?? this.seed,
    weatherCorrelation: weatherCorrelation ?? this.weatherCorrelation,
    marketCorrelation: marketCorrelation ?? this.marketCorrelation,
    fertilizerVolatility: fertilizerVolatility ?? this.fertilizerVolatility,
    fuelVolatility: fuelVolatility ?? this.fuelVolatility,
    waterVolatility: waterVolatility ?? this.waterVolatility,
    equipmentFailureProbability:
        equipmentFailureProbability ?? this.equipmentFailureProbability,
    equipmentFailureCost: equipmentFailureCost ?? this.equipmentFailureCost,
  );
  void validate() {
    if (iterations < 2 || iterations > 100000) {
      throw const SimulationFailure(
        'Simulation iterations must be between 2 and 100,000.',
      );
    }
    _finite(weatherCorrelation, 'Weather correlation', min: 0, max: 1);
    _finite(marketCorrelation, 'Market correlation', min: 0, max: 1);
    _finite(
      equipmentFailureProbability,
      'Equipment failure probability',
      min: 0,
      max: 1,
    );
    for (final e in <String, double>{
      'Fertilizer volatility': fertilizerVolatility,
      'Fuel volatility': fuelVolatility,
      'Water volatility': waterVolatility,
      'Equipment failure cost': equipmentFailureCost,
    }.entries) {
      _finite(e.value, e.key, min: 0);
    }
  }
}

class FarmSettings {
  final String currencyCode;
  final OptimizationConfig optimization;
  final SimulationConfig simulation;
  final double priceGrowthRate;
  final double expenseInflationRate;
  final double liquidityReserve;
  final double alertUtilizationThreshold;
  FarmSettings({
    required this.currencyCode,
    required this.optimization,
    required this.simulation,
    required this.priceGrowthRate,
    required this.expenseInflationRate,
    required this.liquidityReserve,
    required this.alertUtilizationThreshold,
  });
  factory FarmSettings.fromJson(Map<String, dynamic> json) {
    try {
      return FarmSettings(
        currencyCode: _string(json, 'currencyCode'),
        optimization: OptimizationConfig.fromJson(
          _object(json['optimization'], 'optimization'),
        ),
        simulation: SimulationConfig.fromJson(
          _object(json['simulation'], 'simulation'),
        ),
        priceGrowthRate: _number(json, 'priceGrowthRate'),
        expenseInflationRate: _number(json, 'expenseInflationRate'),
        liquidityReserve: _number(json, 'liquidityReserve'),
        alertUtilizationThreshold: _number(json, 'alertUtilizationThreshold'),
      );
    } on DomainFailure {
      rethrow;
    } catch (e) {
      throw ValidationFailure('Invalid FarmSettings data.', {
        'cause': e.toString(),
      });
    }
  }
  Map<String, dynamic> toJson() => {
    'currencyCode': currencyCode,
    'optimization': optimization.toJson(),
    'simulation': simulation.toJson(),
    'priceGrowthRate': priceGrowthRate,
    'expenseInflationRate': expenseInflationRate,
    'liquidityReserve': liquidityReserve,
    'alertUtilizationThreshold': alertUtilizationThreshold,
  };
  FarmSettings copyWith({
    String? currencyCode,
    OptimizationConfig? optimization,
    SimulationConfig? simulation,
    double? priceGrowthRate,
    double? expenseInflationRate,
    double? liquidityReserve,
    double? alertUtilizationThreshold,
  }) => FarmSettings(
    currencyCode: currencyCode ?? this.currencyCode,
    optimization: optimization ?? this.optimization,
    simulation: simulation ?? this.simulation,
    priceGrowthRate: priceGrowthRate ?? this.priceGrowthRate,
    expenseInflationRate: expenseInflationRate ?? this.expenseInflationRate,
    liquidityReserve: liquidityReserve ?? this.liquidityReserve,
    alertUtilizationThreshold:
        alertUtilizationThreshold ?? this.alertUtilizationThreshold,
  );
  void validate() {
    _text(currencyCode, 'Currency code');
    optimization.validate();
    simulation.validate();
    _finite(priceGrowthRate, 'Price growth', min: -1);
    _finite(expenseInflationRate, 'Expense inflation', min: -1);
    _finite(liquidityReserve, 'Liquidity reserve', min: 0);
    _finite(
      alertUtilizationThreshold,
      'Alert utilization threshold',
      min: 0,
      max: 1,
    );
  }
}

class FarmPlan {
  final Map<String, String> assignments;
  FarmPlan({required Map<String, String> assignments})
    : assignments = Map.unmodifiable(assignments);
  factory FarmPlan.fromJson(Map<String, dynamic> json) {
    try {
      return FarmPlan(
        assignments: _object(
          json['assignments'],
          'assignments',
        ).map((k, v) => MapEntry(k, _string({'value': v}, 'value'))),
      );
    } on DomainFailure {
      rethrow;
    } catch (e) {
      throw ValidationFailure('Invalid FarmPlan data.', {
        'cause': e.toString(),
      });
    }
  }
  Map<String, dynamic> toJson() => {'assignments': assignments};
  FarmPlan copyWith({Map<String, String>? assignments}) =>
      FarmPlan(assignments: assignments ?? this.assignments);
}

class StressScenario {
  final String id;
  final String name;
  final double priceMultiplier;
  final double yieldMultiplier;
  final double fertilizerMultiplier;
  final double fuelMultiplier;
  final double laborMultiplier;
  final double waterAvailabilityMultiplier;
  final double interestRateMultiplier;
  final double equipmentCostAddition;
  StressScenario({
    required this.id,
    required this.name,
    this.priceMultiplier = 1,
    this.yieldMultiplier = 1,
    this.fertilizerMultiplier = 1,
    this.fuelMultiplier = 1,
    this.laborMultiplier = 1,
    this.waterAvailabilityMultiplier = 1,
    this.interestRateMultiplier = 1,
    this.equipmentCostAddition = 0,
  });
  factory StressScenario.fromJson(Map<String, dynamic> json) {
    try {
      return StressScenario(
        id: _string(json, 'id'),
        name: _string(json, 'name'),
        priceMultiplier: json.containsKey('priceMultiplier')
            ? _number(json, 'priceMultiplier')
            : 1,
        yieldMultiplier: json.containsKey('yieldMultiplier')
            ? _number(json, 'yieldMultiplier')
            : 1,
        fertilizerMultiplier: json.containsKey('fertilizerMultiplier')
            ? _number(json, 'fertilizerMultiplier')
            : 1,
        fuelMultiplier: json.containsKey('fuelMultiplier')
            ? _number(json, 'fuelMultiplier')
            : 1,
        laborMultiplier: json.containsKey('laborMultiplier')
            ? _number(json, 'laborMultiplier')
            : 1,
        waterAvailabilityMultiplier:
            json.containsKey('waterAvailabilityMultiplier')
            ? _number(json, 'waterAvailabilityMultiplier')
            : 1,
        interestRateMultiplier: json.containsKey('interestRateMultiplier')
            ? _number(json, 'interestRateMultiplier')
            : 1,
        equipmentCostAddition: json.containsKey('equipmentCostAddition')
            ? _number(json, 'equipmentCostAddition')
            : 0,
      );
    } on DomainFailure {
      rethrow;
    } catch (e) {
      throw ValidationFailure('Invalid StressScenario data.', {
        'cause': e.toString(),
      });
    }
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'priceMultiplier': priceMultiplier,
    'yieldMultiplier': yieldMultiplier,
    'fertilizerMultiplier': fertilizerMultiplier,
    'fuelMultiplier': fuelMultiplier,
    'laborMultiplier': laborMultiplier,
    'waterAvailabilityMultiplier': waterAvailabilityMultiplier,
    'interestRateMultiplier': interestRateMultiplier,
    'equipmentCostAddition': equipmentCostAddition,
  };
  StressScenario copyWith({
    String? id,
    String? name,
    double? priceMultiplier,
    double? yieldMultiplier,
    double? fertilizerMultiplier,
    double? fuelMultiplier,
    double? laborMultiplier,
    double? waterAvailabilityMultiplier,
    double? interestRateMultiplier,
    double? equipmentCostAddition,
  }) => StressScenario(
    id: id ?? this.id,
    name: name ?? this.name,
    priceMultiplier: priceMultiplier ?? this.priceMultiplier,
    yieldMultiplier: yieldMultiplier ?? this.yieldMultiplier,
    fertilizerMultiplier: fertilizerMultiplier ?? this.fertilizerMultiplier,
    fuelMultiplier: fuelMultiplier ?? this.fuelMultiplier,
    laborMultiplier: laborMultiplier ?? this.laborMultiplier,
    waterAvailabilityMultiplier:
        waterAvailabilityMultiplier ?? this.waterAvailabilityMultiplier,
    interestRateMultiplier:
        interestRateMultiplier ?? this.interestRateMultiplier,
    equipmentCostAddition: equipmentCostAddition ?? this.equipmentCostAddition,
  );
  void validate() {
    _text(id, 'Scenario id');
    _text(name, 'Scenario name');
    for (final e in <String, double>{
      'Price multiplier': priceMultiplier,
      'Yield multiplier': yieldMultiplier,
      'Fertilizer multiplier': fertilizerMultiplier,
      'Fuel multiplier': fuelMultiplier,
      'Labor multiplier': laborMultiplier,
      'Water multiplier': waterAvailabilityMultiplier,
      'Interest multiplier': interestRateMultiplier,
      'Equipment addition': equipmentCostAddition,
    }.entries) {
      _finite(e.value, e.key, min: 0);
    }
  }
}

class Farm {
  final String id;
  final String name;
  final List<Field> fields;
  final List<CropProfile> crops;
  final List<Expense> expenses;
  final List<Debt> debts;
  final List<FarmConstraint> constraints;
  final FarmSettings settings;
  final Provenance provenance;
  final List<StressScenario> scenarios;
  final int schemaVersion;
  Farm({
    required this.id,
    required this.name,
    required List<Field> fields,
    required List<CropProfile> crops,
    required List<Expense> expenses,
    required List<Debt> debts,
    required List<FarmConstraint> constraints,
    required this.settings,
    required this.provenance,
    List<StressScenario> scenarios = const [],
    this.schemaVersion = currentSchemaVersion,
  }) : fields = List.unmodifiable(fields),
       crops = List.unmodifiable(crops),
       expenses = List.unmodifiable(expenses),
       debts = List.unmodifiable(debts),
       constraints = List.unmodifiable(constraints),
       scenarios = List.unmodifiable(scenarios);
  factory Farm.fromJson(Map<String, dynamic> json) {
    try {
      return Farm(
        id: _string(json, 'id'),
        name: _string(json, 'name'),
        fields: _list(
          json,
          'fields',
        ).map((v) => Field.fromJson(_object(v, 'fields'))).toList(),
        crops: _list(
          json,
          'crops',
        ).map((v) => CropProfile.fromJson(_object(v, 'crops'))).toList(),
        expenses: _list(
          json,
          'expenses',
        ).map((v) => Expense.fromJson(_object(v, 'expenses'))).toList(),
        debts: _list(
          json,
          'debts',
        ).map((v) => Debt.fromJson(_object(v, 'debts'))).toList(),
        constraints: _list(json, 'constraints')
            .map((v) => FarmConstraint.fromJson(_object(v, 'constraints')))
            .toList(),
        settings: FarmSettings.fromJson(_object(json['settings'], 'settings')),
        provenance: Provenance.fromJson(
          _object(json['provenance'], 'provenance'),
        ),
        scenarios: json.containsKey('scenarios')
            ? _list(json, 'scenarios')
                  .map((v) => StressScenario.fromJson(_object(v, 'scenarios')))
                  .toList()
            : const [],
        schemaVersion: json.containsKey('schemaVersion')
            ? _integer(json, 'schemaVersion')
            : currentSchemaVersion,
      );
    } on DomainFailure {
      rethrow;
    } catch (e) {
      throw ValidationFailure('Invalid Farm data.', {'cause': e.toString()});
    }
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'fields': fields.map((v) => v.toJson()).toList(),
    'crops': crops.map((v) => v.toJson()).toList(),
    'expenses': expenses.map((v) => v.toJson()).toList(),
    'debts': debts.map((v) => v.toJson()).toList(),
    'constraints': constraints.map((v) => v.toJson()).toList(),
    'settings': settings.toJson(),
    'provenance': provenance.toJson(),
    'scenarios': scenarios.map((v) => v.toJson()).toList(),
    'schemaVersion': schemaVersion,
  };
  Farm copyWith({
    String? id,
    String? name,
    List<Field>? fields,
    List<CropProfile>? crops,
    List<Expense>? expenses,
    List<Debt>? debts,
    List<FarmConstraint>? constraints,
    FarmSettings? settings,
    Provenance? provenance,
    List<StressScenario>? scenarios,
    int? schemaVersion,
  }) => Farm(
    id: id ?? this.id,
    name: name ?? this.name,
    fields: fields ?? this.fields,
    crops: crops ?? this.crops,
    expenses: expenses ?? this.expenses,
    debts: debts ?? this.debts,
    constraints: constraints ?? this.constraints,
    settings: settings ?? this.settings,
    provenance: provenance ?? this.provenance,
    scenarios: scenarios ?? this.scenarios,
    schemaVersion: schemaVersion ?? this.schemaVersion,
  );
  double get acreage => fields.fold(0.0, (sum, field) => sum + field.acres);
  FarmPlan get currentPlan => FarmPlan(
    assignments: {for (final field in fields) field.id: field.currentCropId},
  );
  CropProfile crop(String id) => crops.firstWhere(
    (c) => c.id == id,
    orElse: () => throw DataUnavailableFailure('Crop $id is unavailable.'),
  );
  Field field(String id) => fields.firstWhere(
    (f) => f.id == id,
    orElse: () => throw DataUnavailableFailure('Field $id is unavailable.'),
  );
  void validate({bool requireReady = false}) {
    _text(id, 'Farm id');
    _text(name, 'Farm name');
    if (schemaVersion != currentSchemaVersion) {
      throw ValidationFailure(
        'Unsupported farm schema version $schemaVersion. Export data and update the application.',
      );
    }
    settings.validate();
    _finite(acreage, 'Total farm acreage', min: 0);
    _unique(fields.map((v) => v.id), 'field');
    _unique(crops.map((v) => v.id), 'crop');
    _unique(expenses.map((v) => v.id), 'expense');
    _unique(debts.map((v) => v.id), 'debt');
    _unique(constraints.map((v) => v.id), 'constraint');
    _unique(scenarios.map((v) => v.id), 'scenario');
    for (final v in crops) {
      v.validate();
    }
    for (final v in expenses) {
      v.validate();
    }
    for (final v in debts) {
      v.validate();
    }
    for (final v in constraints) {
      v.validate();
    }
    for (final v in scenarios) {
      v.validate();
    }
    for (final f in fields) {
      f.validate();
      for (final id in f.compatibleCropIds) {
        crop(id);
      }
      if (f.currentCropId.isNotEmpty) {
        crop(f.currentCropId);
      }
      if (requireReady &&
          (f.currentCropId.isEmpty || f.compatibleCropIds.isEmpty)) {
        throw ValidationFailure(
          'Set current crop and compatible crops for ${f.name}.',
        );
      }
    }
    if (requireReady && (fields.isEmpty || crops.isEmpty)) {
      throw const DataUnavailableFailure(
        'Add at least one field and crop profile before calculating a farm plan.',
      );
    }
  }

  void validatePlan(FarmPlan plan) {
    if (plan.assignments.length != fields.length ||
        plan.assignments.keys.any((id) => !fields.any((f) => f.id == id))) {
      throw const ValidationFailure(
        'A plan must assign exactly one crop to every field.',
      );
    }
    for (final f in fields) {
      final id = plan.assignments[f.id];
      if (id == null) {
        throw ValidationFailure('Missing assignment for ${f.name}.');
      }
      final c = crop(id);
      if (!f.compatibleCropIds.contains(id) ||
          (c.requiresIrrigation && !f.irrigated)) {
        throw ValidationFailure(
          'Crop ${c.name} is incompatible with ${f.name}.',
        );
      }
    }
  }
}
