/// Tolerant JSON readers.
///
/// Farm data arrives from bundled demo assets, Firestore documents and user
/// entry, so a number may legitimately show up as `int`, `double` or `String`.
/// These helpers normalise that without scattering casts through the models.
library;

double asDouble(Object? value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

int asInt(Object? value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

String asString(Object? value, {String fallback = ''}) {
  if (value is String) return value;
  if (value == null) return fallback;
  return value.toString();
}

bool asBool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final String lowered = value.toLowerCase();
    if (lowered == 'true') return true;
    if (lowered == 'false') return false;
  }
  return fallback;
}

/// Reads a JSON array into a `Set<String>`, ignoring nulls.
Set<String> asStringSet(Object? value) {
  if (value is Iterable) {
    return value
        .where((Object? e) => e != null)
        .map((Object? e) => e.toString())
        .toSet();
  }
  return const <String>{};
}

/// Reads a JSON array of objects into a typed list.
List<T> asObjectList<T>(
  Object? value,
  T Function(Map<String, dynamic>) fromJson,
) {
  if (value is Iterable) {
    return value
        .whereType<Map<String, dynamic>>()
        .map(fromJson)
        .toList(growable: false);
  }
  return <T>[];
}

/// Reads a `{"2024": "corn"}` style map into `{2024: 'corn'}`.
Map<int, String> asIntKeyedStringMap(Object? value) {
  if (value is Map) {
    final Map<int, String> result = <int, String>{};
    value.forEach((Object? key, Object? val) {
      final int? year = key is int ? key : int.tryParse(key.toString());
      if (year != null && val != null) result[year] = val.toString();
    });
    return result;
  }
  return <int, String>{};
}

/// Reads a nested JSON object, returning an empty map when absent.
Map<String, dynamic> asJsonMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return <String, dynamic>{};
}
