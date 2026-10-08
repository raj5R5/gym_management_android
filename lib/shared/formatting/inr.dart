/// Exact INR formatting: no conversion to floating-point rupees.
String formatInrPaise(int paise) {
  if (paise < 0) {
    throw ArgumentError.value(paise, 'paise', 'Must be nonnegative');
  }
  final digits = (paise ~/ 100).toString();
  final groups = <String>[];
  var end = digits.length;
  if (end > 3) {
    groups.insert(0, digits.substring(end - 3, end));
    end -= 3;
    while (end > 2) {
      groups.insert(0, digits.substring(end - 2, end));
      end -= 2;
    }
  }
  groups.insert(0, digits.substring(0, end));
  return '₹${groups.join(',')}.${(paise % 100).toString().padLeft(2, '0')}';
}
