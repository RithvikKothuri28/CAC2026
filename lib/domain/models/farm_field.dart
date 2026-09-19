import '../../core/utilities/json_utils.dart';

/// One physical field in the farm's digital twin.
class FarmField {
  const FarmField({
    required this.id,
    required this.name,
    required this.acres,
    required this.soilType,
    required this.irrigated,
    this.currentCropId,
    this.yieldMultiplier = 1.0,
    this.cropHistory = const <int, String>{},
    this.notes = '',
  });

  final String id;
  final String name;
  final double acres;

  /// Soil classification, matched against `CropProfile.compatibleSoilTypes`.
  final String soilType;

  final bool irrigated;

  /// Crop planted under the farm's existing plan, used as the comparison
  /// baseline. Null means the field is currently unassigned.
  final String? currentCropId;

  /// Productivity of this field relative to the crop's baseline yield.
  /// Dryland fields typically sit well below 1.0.
  final double yieldMultiplier;

  /// Past plantings, keyed by season year. Drives rotation checking.
  final Map<int, String> cropHistory;

  final String notes;

  /// Crop grown in [year], or null if unrecorded.
  String? cropInYear(int year) => cropHistory[year];

  /// Seasons since [cropId] last occupied this field, counting back from
  /// [planYear]. Returns null when the crop does not appear in the history,
  /// which callers should read as "no rotation conflict on record".
  int? seasonsSince(String cropId, int planYear) {
    int? mostRecent;
    for (final MapEntry<int, String> entry in cropHistory.entries) {
      if (entry.value == cropId && entry.key < planYear) {
        if (mostRecent == null || entry.key > mostRecent) {
          mostRecent = entry.key;
        }
      }
    }
    return mostRecent == null ? null : planYear - mostRecent;
  }

  factory FarmField.fromJson(Map<String, dynamic> json) => FarmField(
    id: asString(json['id']),
    name: asString(json['name']),
    acres: asDouble(json['acres']),
    soilType: asString(json['soilType']),
    irrigated: asBool(json['irrigated']),
    currentCropId: json['currentCropId'] == null
        ? null
        : asString(json['currentCropId']),
    yieldMultiplier: asDouble(json['yieldMultiplier'], fallback: 1.0),
    cropHistory: asIntKeyedStringMap(json['cropHistory']),
    notes: asString(json['notes']),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'acres': acres,
    'soilType': soilType,
    'irrigated': irrigated,
    'currentCropId': currentCropId,
    'yieldMultiplier': yieldMultiplier,
    'cropHistory': cropHistory.map(
      (int year, String crop) =>
          MapEntry<String, String>(year.toString(), crop),
    ),
    'notes': notes,
  };

  FarmField copyWith({
    double? acres,
    bool? irrigated,
    String? currentCropId,
    double? yieldMultiplier,
    Map<int, String>? cropHistory,
  }) => FarmField(
    id: id,
    name: name,
    acres: acres ?? this.acres,
    soilType: soilType,
    irrigated: irrigated ?? this.irrigated,
    currentCropId: currentCropId ?? this.currentCropId,
    yieldMultiplier: yieldMultiplier ?? this.yieldMultiplier,
    cropHistory: cropHistory ?? this.cropHistory,
    notes: notes,
  );

  @override
  String toString() => 'FarmField($id, ${acres.toStringAsFixed(0)}ac)';
}
