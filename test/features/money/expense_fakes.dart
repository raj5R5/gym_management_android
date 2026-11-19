import 'package:gym_management_app/features/expenses/expenses.dart';

/// In-memory expenses for the current month.
class FakeExpenseRepository implements ExpenseRepository {
  final items = <Map<String, dynamic>>[];
  final removed = <String>[];

  @override
  Future<ExpensePage> list(String gymId, ExpensePeriod period) async {
    final live = items.where((item) => !removed.contains(item['id'])).toList();
    final totals = <String, ({int amount, int count})>{};
    for (final item in live) {
      final previous = totals[item['category']] ?? (amount: 0, count: 0);
      totals[item['category'] as String] = (
        amount: previous.amount + (item['amountPaise'] as int),
        count: previous.count + 1,
      );
    }
    return ExpensePage.fromJson({
      'from': '2026-11-01',
      'to': '2026-11-14',
      'totalPaise': live.fold<int>(
        0,
        (sum, item) => sum + (item['amountPaise'] as int),
      ),
      'byCategory': [
        for (final entry in totals.entries)
          {
            'category': entry.key,
            'amountPaise': entry.value.amount,
            'count': entry.value.count,
          },
      ],
      'data': live,
      'pagination': {'page': 1, 'limit': 50, 'total': live.length},
    });
  }

  @override
  Future<void> create(
    String gymId, {
    required ExpenseCategory category,
    required int amountPaise,
    required String spentOn,
    required String paymentMethod,
    String? note,
  }) async => items.add({
    'id': 'e${items.length + 1}',
    'category': category.name,
    'amountPaise': amountPaise,
    'spentOn': spentOn,
    'paymentMethod': paymentMethod,
    'note': note,
  });

  @override
  Future<void> remove(String gymId, String expenseId) async =>
      removed.add(expenseId);
}
