import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/shared/formatting/inr.dart';

void main() {
  test('whole rupees omit decimals only in compact display', () {
    expect(formatCompactInrPaise(200000), '₹2,000');
    expect(formatCompactInrPaise(0), '₹0');
    expect(formatInrPaise(200000), '₹2,000.00');
  });
  test('fractional paise and Indian grouping remain exact', () {
    expect(formatCompactInrPaise(200001), '₹2,000.01');
    expect(formatCompactInrPaise(1), '₹0.01');
    expect(formatCompactInrPaise(123456789), '₹12,34,567.89');
    expect(formatCompactInrPaise(9007199254740991), '₹9,00,71,99,25,47,409.91');
  });
  test('negative amounts remain invalid', () {
    expect(() => formatCompactInrPaise(-1), throwsArgumentError);
  });
}
