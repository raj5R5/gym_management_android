import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../admin_dashboard/providers/dashboard_providers.dart';
import '../auth/data/auth_failure.dart';
import '../auth/providers/auth_providers.dart';
import '../members/models/member_models.dart';

enum ExpenseCategory {
  rent('Rent', Icons.home_work_outlined),
  salaries('Salaries', Icons.badge_outlined),
  electricity('Electricity', Icons.bolt_outlined),
  equipment('Equipment', Icons.fitness_center_outlined),
  maintenance('Maintenance', Icons.build_outlined),
  marketing('Marketing', Icons.campaign_outlined),
  supplies('Supplies', Icons.inventory_2_outlined),
  other('Other', Icons.more_horiz);

  const ExpenseCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

class Expense {
  Expense.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      category = ExpenseCategory.values.byName(json['category'] as String),
      amountPaise = json['amountPaise'] as int,
      spentOn = json['spentOn'] as String,
      paymentMethod = json['paymentMethod'] as String,
      note = json['note'] as String?;
  final String id, spentOn, paymentMethod;
  final ExpenseCategory category;
  final int amountPaise;
  final String? note;
}

class CategoryTotal {
  CategoryTotal.fromJson(Map<String, dynamic> json)
    : category = ExpenseCategory.values.byName(json['category'] as String),
      amountPaise = json['amountPaise'] as int,
      count = json['count'] as int;
  final ExpenseCategory category;
  final int amountPaise, count;
}

class ExpensePage {
  ExpensePage.fromJson(Map<String, dynamic> json)
    : from = json['from'] as String,
      to = json['to'] as String,
      totalPaise = json['totalPaise'] as int,
      byCategory = List.unmodifiable(
        (json['byCategory'] as List).map(
          (row) => CategoryTotal.fromJson(row as Map<String, dynamic>),
        ),
      ),
      expenses = List.unmodifiable(
        (json['data'] as List).map(
          (row) => Expense.fromJson(row as Map<String, dynamic>),
        ),
      ),
      pagination = Pagination.fromJson(
        json['pagination'] as Map<String, dynamic>,
      );
  final String from, to;
  final int totalPaise;
  final List<CategoryTotal> byCategory;
  final List<Expense> expenses;
  final Pagination pagination;
}

class ExpenseFailure implements Exception {
  const ExpenseFailure(this.message);
  final String message;
  factory ExpenseFailure.fromDio(DioException error) {
    final data = error.response?.data;
    final code = data is Map && data['error'] is Map
        ? (data['error'] as Map)['code']
        : null;
    return ExpenseFailure(switch (code) {
      'VALIDATION_ERROR' =>
        'Check the amount and date. Future dates aren’t allowed.',
      'EXPENSE_NOT_FOUND' => 'This expense was already removed.',
      _ => AuthFailure.fromDio(error).message,
    });
  }
}

/// Inclusive gym-local dates; null means the server's current month.
typedef ExpensePeriod = ({String? from, String? to, int page});

class ExpenseRepository {
  ExpenseRepository(this._client);
  final Dio _client;

  Future<Map<String, dynamic>> _data(
    Future<Response<dynamic>> Function() call,
  ) async {
    try {
      final body = (await call()).data;
      if (body is! Map<String, dynamic> || body['success'] != true) {
        throw const ExpenseFailure(
          'The server returned an unexpected response.',
        );
      }
      return body['data'] as Map<String, dynamic>;
    } on DioException catch (error) {
      throw ExpenseFailure.fromDio(error);
    }
  }

  Future<ExpensePage> list(String gymId, ExpensePeriod period) async {
    try {
      return ExpensePage.fromJson(
        await _data(
          () => _client.get<dynamic>(
            'gyms/$gymId/expenses',
            queryParameters: {
              'from': ?period.from,
              'to': ?period.to,
              'page': '${period.page}',
              'limit': '50',
            },
          ),
        ),
      );
    } on TypeError {
      throw const ExpenseFailure('The server returned unexpected expenses.');
    }
  }

  Future<void> create(
    String gymId, {
    required ExpenseCategory category,
    required int amountPaise,
    required String spentOn,
    required String paymentMethod,
    String? note,
  }) => _data(
    () => _client.post<dynamic>(
      'gyms/$gymId/expenses',
      data: {
        'category': category.name,
        'amountPaise': amountPaise,
        'spentOn': spentOn,
        'paymentMethod': paymentMethod,
        'note': ?note,
      },
    ),
  );

  Future<void> remove(String gymId, String expenseId) =>
      _data(() => _client.delete<dynamic>('gyms/$gymId/expenses/$expenseId'));
}

final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => ExpenseRepository(ref.watch(authenticatedApiClientProvider)),
);

final expensesProvider = FutureProvider.autoDispose
    .family<ExpensePage?, ExpensePeriod>((ref, period) {
      final gym = ref.watch(adminGymProvider);
      if (gym == null) return null;
      return ref.watch(expenseRepositoryProvider).list(gym.gymId, period);
    }, retry: (_, _) => null);
