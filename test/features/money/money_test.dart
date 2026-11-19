import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/expenses/expenses.dart';
import 'package:gym_management_app/features/gym_settings/gym_settings.dart';
import 'package:gym_management_app/features/receipts/receipt.dart';
import '../auth/auth_fakes.dart';

const gym = '6af80a503ad696b0ec816cd7';
const payment = '6af80a763ad696b0ec816ce9';

Map<String, dynamic> receiptJson() => {
  'receiptNumber': 'R-00007',
  'issuedAt': '2026-11-14T10:00:00.000Z',
  'timezone': 'Asia/Kolkata',
  'gym': {
    'name': 'Iron Test Gym',
    'phone': '9876500000',
    'email': null,
    'address': '12 MG Road, Pune',
  },
  'member': {
    'id': 'm1',
    'memberCode': 'IT007',
    'name': 'Karan Mehta',
    'phone': '9876543207',
  },
  'payment': {
    'id': payment,
    'amountPaise': 350000,
    'method': 'upi',
    'reference': 'UTR998877',
    'paidAt': '2026-11-13T07:15:00.000Z',
  },
  'membership': {
    'planName': 'Half Yearly',
    'startDate': '2026-11-04',
    'endDate': '2027-05-03',
    'pricePaise': 700000,
    'paidTotalPaise': 350000,
    'balancePaise': 350000,
    'cancelled': false,
  },
};

Dio client(
  ResponseBody Function(RequestOptions) respond,
  List<RequestOptions> log,
) =>
    Dio(BaseOptions(baseUrl: 'https://api.example.invalid/api/v1/'))
      ..httpClientAdapter = CallbackAdapter((request) {
        log.add(request);
        return respond(request);
      });

void main() {
  group('UPI pay link', () {
    test('formats the amount in rupees and encodes text', () {
      expect(
        upiPayUri(
          upiId: 'irongym@okaxis',
          payeeName: 'Iron Gym & Spa',
          amountPaise: 350005,
          note: 'Half Yearly IT007',
        ),
        'upi://pay?pa=irongym%40okaxis&pn=Iron%20Gym%20%26%20Spa&am=3500.05&cu=INR&tn=Half%20Yearly%20IT007',
      );
    });
    test('UPI ID format', () {
      for (final ok in [
        'irongym@okaxis',
        'iron.gym-1@ybl',
        '9876543210@paytm',
      ]) {
        expect(upiIdPattern.hasMatch(ok), isTrue, reason: ok);
      }
      for (final bad in [
        'irongym',
        '@okaxis',
        'iron gym@ybl',
        'IRONGYM@OKAXIS',
      ]) {
        expect(upiIdPattern.hasMatch(bad), isFalse, reason: bad);
      }
    });
  });

  group('receipts', () {
    test('parse and describe the period with an inclusive last day', () {
      final receipt = PaymentReceipt.fromJson(receiptJson());
      expect(receipt.receiptNumber, 'R-00007');
      expect(receipt.method.label, 'UPI');
      expect(receipt.balancePaise, 350000);
      expect(
        receipt.periodLabel(const DefaultMaterialLocalizations()),
        '4 Nov 2026 – 2 May 2027',
      );
    });

    testWidgets('build a one-page PDF with the embedded font', (tester) async {
      final bytes = await tester.runAsync(
        () => buildReceiptPdf(
          PaymentReceipt.fromJson(receiptJson()),
          const DefaultMaterialLocalizations(),
        ),
      );
      expect(bytes, isNotNull);
      expect(latin1.decode(bytes!.sublist(0, 5)), '%PDF-');
      expect(bytes.length, greaterThan(2000));
      expect(
        latin1.decode(bytes).contains('/FontFile2'),
        isTrue,
        reason: 'Geist is embedded so ₹ renders',
      );
    });

    test('unavailable receipts show a safe message', () async {
      final log = <RequestOptions>[];
      final repository = ReceiptRepository(
        client(
          (_) => jsonResponse({
            'success': false,
            'error': {'code': 'RECEIPT_UNAVAILABLE', 'message': 'x'},
          }, status: 409),
          log,
        ),
      );
      await expectLater(
        repository.get(gym, payment),
        throwsA(
          isA<ReceiptFailure>().having(
            (e) => e.message,
            'message',
            'Receipts are only available for successful payments.',
          ),
        ),
      );
      expect(log.single.path, 'gyms/$gym/payments/$payment/receipt');
      await expectLater(
        repository.get(gym, 'bad'),
        throwsA(isA<ReceiptFailure>()),
      );
      expect(log, hasLength(1));
    });
  });

  group('expenses', () {
    test('list sends the period and parses totals', () async {
      final log = <RequestOptions>[];
      final repository = ExpenseRepository(
        client(
          (_) => jsonResponse({
            'success': true,
            'data': {
              'from': '2026-10-01',
              'to': '2026-10-31',
              'totalPaise': 3000000,
              'byCategory': [
                {'category': 'rent', 'amountPaise': 2500000, 'count': 1},
                {'category': 'electricity', 'amountPaise': 500000, 'count': 2},
              ],
              'data': [
                {
                  'id': 'e1',
                  'category': 'rent',
                  'amountPaise': 2500000,
                  'spentOn': '2026-10-05',
                  'paymentMethod': 'bank_transfer',
                  'note': 'October rent',
                },
              ],
              'pagination': {'page': 1, 'limit': 50, 'total': 3},
            },
          }),
          log,
        ),
      );
      final page = await repository.list(gym, (
        from: '2026-10-01',
        to: '2026-10-31',
        page: 1,
      ));
      expect(log.single.queryParameters, {
        'from': '2026-10-01',
        'to': '2026-10-31',
        'page': '1',
        'limit': '50',
      });
      expect(page.totalPaise, 3000000);
      expect(page.byCategory.first.category, ExpenseCategory.rent);
      expect(page.expenses.single.note, 'October rent');
    });

    test(
      'create omits an empty note; validation errors read clearly',
      () async {
        final log = <RequestOptions>[];
        final repository = ExpenseRepository(
          client(
            (request) => request.method == 'POST' && log.length == 1
                ? jsonResponse({'success': true, 'data': {}}, status: 201)
                : jsonResponse({
                    'success': false,
                    'error': {'code': 'VALIDATION_ERROR', 'message': 'x'},
                  }, status: 400),
            log,
          ),
        );
        await repository.create(
          gym,
          category: ExpenseCategory.electricity,
          amountPaise: 400000,
          spentOn: '2026-11-14',
          paymentMethod: 'cash',
        );
        expect(log.single.data, {
          'category': 'electricity',
          'amountPaise': 400000,
          'spentOn': '2026-11-14',
          'paymentMethod': 'cash',
        });
        await expectLater(
          repository.create(
            gym,
            category: ExpenseCategory.rent,
            amountPaise: 1,
            spentOn: '2099-01-01',
            paymentMethod: 'cash',
          ),
          throwsA(
            isA<ExpenseFailure>().having(
              (e) => e.message,
              'message',
              contains('Future dates aren’t allowed'),
            ),
          ),
        );
      },
    );
  });
}
