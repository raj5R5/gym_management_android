Map<String, dynamic> object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid profile response.');
  }
  return value;
}

String text(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw const FormatException('Missing profile field.');
  }
  return value;
}

String? optionalText(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw const FormatException('Invalid profile field.');
  return value;
}

int integer(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int || value < 0 || value > 9007199254740991) {
    throw const FormatException('Invalid profile number.');
  }
  return value;
}

bool boolean(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) {
    throw const FormatException('Invalid profile flag.');
  }
  return value;
}

List<T> items<T>(Object? value, T Function(Map<String, dynamic>) parse) {
  if (value is! List) {
    throw const FormatException('Invalid profile collection.');
  }
  return List.unmodifiable(value.map((item) => parse(object(item))));
}

T? optionalObject<T>(Object? value, T Function(Map<String, dynamic>) parse) =>
    value == null ? null : parse(object(value));

class ProfileAddress {
  ProfileAddress.fromJson(Map<String, dynamic> json)
    : line1 = text(json, 'line1'),
      city = text(json, 'city'),
      countryCode = text(json, 'countryCode'),
      line2 = optionalText(json, 'line2'),
      region = optionalText(json, 'state'),
      postalCode = optionalText(json, 'postalCode');
  final String line1, city, countryCode;
  final String? line2, region, postalCode;
  Map<String, dynamic> toJson() => {
    'line1': line1,
    'city': city,
    'countryCode': countryCode,
    if (line2 != null) 'line2': line2,
    if (region != null) 'state': region,
    if (postalCode != null) 'postalCode': postalCode,
  };
  String get display => [
    line1,
    line2,
    city,
    region,
    postalCode,
    countryCode,
  ].whereType<String>().join(', ');
}

class Pagination {
  Pagination.fromJson(Map<String, dynamic> json)
    : page = integer(json, 'page'),
      limit = integer(json, 'limit'),
      total = integer(json, 'total') {
    if (page < 1 || page > 10000 || limit < 1 || limit > 100) {
      throw const FormatException('Invalid pagination.');
    }
  }
  final int page, limit, total;
  bool get hasNext => page < 10000 && page * limit < total;
  bool get hasPrevious => page > 1;
}
