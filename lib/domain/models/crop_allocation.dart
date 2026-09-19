import '../../core/utilities/json_utils.dart';

/// An assignment of exactly one crop to each field — a candidate farm plan.
///
/// Iteration order is always sorted by field id so that every engine, hash and
/// serialised run is reproducible regardless of insertion order.
class CropAllocation {
  CropAllocation(Map<String, String> cropByFieldId)
    : _cropByFieldId = Map<String, String>.unmodifiable(cropByFieldId),
      _sortedFieldIds = List<String>.unmodifiable(
        cropByFieldId.keys.toList()..sort(),
      );

  final Map<String, String> _cropByFieldId;
  final List<String> _sortedFieldIds;

  /// Field ids in stable sorted order.
  List<String> get fieldIds => _sortedFieldIds;

  int get fieldCount => _sortedFieldIds.length;

  Map<String, String> get asMap => _cropByFieldId;

  String? cropFor(String fieldId) => _cropByFieldId[fieldId];

  /// Distinct crops used, sorted.
  List<String> get cropIds {
    final Set<String> crops = _cropByFieldId.values.toSet();
    return crops.toList()..sort();
  }

  /// Stable textual key, useful for deduplication and run identifiers.
  String get signature =>
      _sortedFieldIds.map((String id) => '$id=${_cropByFieldId[id]}').join('|');

  CropAllocation withCrop(String fieldId, String cropId) =>
      CropAllocation(<String, String>{..._cropByFieldId, fieldId: cropId});

  factory CropAllocation.fromJson(Map<String, dynamic> json) {
    final Map<String, String> result = <String, String>{};
    asJsonMap(json).forEach((String key, Object? value) {
      if (value != null) result[key] = value.toString();
    });
    return CropAllocation(result);
  }

  Map<String, dynamic> toJson() => Map<String, dynamic>.from(_cropByFieldId);

  @override
  bool operator ==(Object other) =>
      other is CropAllocation && other.signature == signature;

  @override
  int get hashCode => signature.hashCode;

  @override
  String toString() => 'CropAllocation($signature)';
}
