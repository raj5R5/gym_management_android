import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../shared/formatting/inr.dart';
import '../../shared/sharing/share_pdf.dart';
import '../../shared/formatting/payment_date.dart';
import '../admin_dashboard/providers/dashboard_providers.dart';
import '../auth/data/auth_failure.dart';
import '../auth/providers/auth_providers.dart';
import '../memberships/models/billing_models.dart';

String _text(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw const FormatException('Invalid receipt.');
  }
  return value;
}

int _paise(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int || value < 0) {
    throw const FormatException('Invalid receipt.');
  }
  return value;
}

/// A payment receipt (not a tax invoice: no GST lines, by owner choice).
class PaymentReceipt {
  PaymentReceipt.fromJson(Map<String, dynamic> json)
    : receiptNumber = _text(json, 'receiptNumber'),
      timezone = json['timezone'] as String?,
      gymName = _text(json['gym'] as Map<String, dynamic>, 'name'),
      gymPhone = (json['gym'] as Map)['phone'] as String?,
      gymEmail = (json['gym'] as Map)['email'] as String?,
      gymAddress = (json['gym'] as Map)['address'] as String?,
      memberName = _text(json['member'] as Map<String, dynamic>, 'name'),
      memberCode = _text(json['member'] as Map<String, dynamic>, 'memberCode'),
      memberPhone = (json['member'] as Map)['phone'] as String?,
      amountPaise = _paise(
        json['payment'] as Map<String, dynamic>,
        'amountPaise',
      ),
      method = PaymentMethod.values.firstWhere(
        (method) => method.wireValue == (json['payment'] as Map)['method'],
        orElse: () => PaymentMethod.other,
      ),
      reference = (json['payment'] as Map)['reference'] as String?,
      paidAt = DateTime.parse(
        _text(json['payment'] as Map<String, dynamic>, 'paidAt'),
      ),
      planName = _text(json['membership'] as Map<String, dynamic>, 'planName'),
      startDate = _text(
        json['membership'] as Map<String, dynamic>,
        'startDate',
      ),
      endDate = _text(json['membership'] as Map<String, dynamic>, 'endDate'),
      pricePaise = _paise(
        json['membership'] as Map<String, dynamic>,
        'pricePaise',
      ),
      discountPaise = (json['membership'] as Map)['discountPaise'] as int? ?? 0,
      paidTotalPaise = _paise(
        json['membership'] as Map<String, dynamic>,
        'paidTotalPaise',
      ),
      balancePaise = _paise(
        json['membership'] as Map<String, dynamic>,
        'balancePaise',
      );
  final String receiptNumber, gymName, memberName, memberCode, planName;
  final String startDate, endDate;
  final String? timezone,
      gymPhone,
      gymEmail,
      gymAddress,
      memberPhone,
      reference;
  final int amountPaise, pricePaise, paidTotalPaise, balancePaise;

  /// Discount given on the membership; plan price = price + discount.
  final int discountPaise;
  final PaymentMethod method;
  final DateTime paidAt;

  /// "18 Oct 2026 – 17 Nov 2026" (with years, as receipts need): the stored
  /// end date is exclusive, so the last day is the day before it.
  String periodLabel(MaterialLocalizations localizations) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    String day(DateTime date) =>
        '${date.day} ${months[date.month - 1]} ${date.year}';
    final start = DateTime.parse(startDate);
    final lastDay = DateTime.parse(endDate).subtract(const Duration(days: 1));
    return '${day(start)} – ${day(lastDay)}';
  }
}

class ReceiptFailure implements Exception {
  const ReceiptFailure(this.message);
  final String message;
}

class ReceiptRepository {
  ReceiptRepository(this._client);
  final Dio _client;

  /// [asMember] reads the signed-in member's own receipt instead of staff's.
  Future<PaymentReceipt> get(
    String gymId,
    String paymentId, {
    bool asMember = false,
  }) async {
    final id = RegExp(r'^[a-fA-F0-9]{24}$');
    if (!id.hasMatch(gymId) || !id.hasMatch(paymentId)) {
      throw const ReceiptFailure('Invalid payment.');
    }
    try {
      final body = (await _client.get<dynamic>(
        '${asMember ? 'me/' : ''}gyms/$gymId/payments/$paymentId/receipt',
      )).data;
      if (body is! Map<String, dynamic> || body['success'] != true) {
        throw const FormatException('Invalid receipt envelope.');
      }
      return PaymentReceipt.fromJson(body['data'] as Map<String, dynamic>);
    } on DioException catch (error) {
      final data = error.response?.data;
      final code = data is Map && data['error'] is Map
          ? (data['error'] as Map)['code']
          : null;
      throw ReceiptFailure(switch (code) {
        'RECEIPT_UNAVAILABLE' =>
          'Receipts are only available for successful payments.',
        'PAYMENT_NOT_FOUND' => 'This payment is no longer available.',
        _ => AuthFailure.fromDio(error).message,
      });
    } on ReceiptFailure {
      rethrow;
    } catch (_) {
      throw const ReceiptFailure('The server returned an unexpected receipt.');
    }
  }
}

final receiptRepositoryProvider = Provider<ReceiptRepository>(
  (ref) => ReceiptRepository(ref.watch(authenticatedApiClientProvider)),
);

/// Builds a one-page A5 receipt. Geist is embedded for the ₹ sign.
Future<Uint8List> buildReceiptPdf(
  PaymentReceipt receipt,
  MaterialLocalizations localizations,
) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Geist_400Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Geist_700Bold.ttf'),
  );
  final muted = PdfColor.fromInt(0xFF6B6E75);
  pw.Widget row(String label, String value, {bool strong = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: pw.TextStyle(color: muted)),
            pw.Text(value, style: strong ? pw.TextStyle(font: bold) : null),
          ],
        ),
      );
  final document = pw.Document(
    title: 'Receipt ${receipt.receiptNumber}',
    author: receipt.gymName,
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );
  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(28),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            receipt.gymName,
            style: pw.TextStyle(font: bold, fontSize: 18),
          ),
          if (receipt.gymAddress != null)
            pw.Text(receipt.gymAddress!, style: pw.TextStyle(color: muted)),
          if (receipt.gymPhone != null || receipt.gymEmail != null)
            pw.Text(
              [
                receipt.gymPhone,
                receipt.gymEmail,
              ].whereType<String>().join(' · '),
              style: pw.TextStyle(color: muted),
            ),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Payment receipt',
                style: pw.TextStyle(font: bold, fontSize: 14),
              ),
              pw.Text(receipt.receiptNumber, style: pw.TextStyle(font: bold)),
            ],
          ),
          pw.Divider(color: muted),
          row('Member', '${receipt.memberName} (${receipt.memberCode})'),
          if (receipt.memberPhone != null) row('Phone', receipt.memberPhone!),
          row(
            'Paid on',
            formatPaymentDateTime(
              localizations,
              receipt.paidAt,
              timezone: receipt.timezone,
            ),
          ),
          row('Method', receipt.method.label),
          if (receipt.reference != null) row('Reference', receipt.reference!),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: muted, width: .5),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Amount received', style: pw.TextStyle(font: bold)),
                pw.Text(
                  formatInrPaise(receipt.amountPaise),
                  style: pw.TextStyle(font: bold, fontSize: 16),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          pw.Text('Membership', style: pw.TextStyle(font: bold)),
          pw.SizedBox(height: 4),
          row('Plan', receipt.planName),
          row('Period', receipt.periodLabel(localizations)),
          row(
            'Plan price',
            formatInrPaise(receipt.pricePaise + receipt.discountPaise),
          ),
          if (receipt.discountPaise > 0) ...[
            row('Discount', '− ${formatInrPaise(receipt.discountPaise)}'),
            row('Amount payable', formatInrPaise(receipt.pricePaise)),
          ],
          row('Paid so far', formatInrPaise(receipt.paidTotalPaise)),
          row(
            'Balance due',
            formatInrPaise(receipt.balancePaise),
            strong: true,
          ),
          pw.Spacer(),
          pw.Text(
            'This is a payment receipt, not a tax invoice. Computer generated; no signature required.',
            style: pw.TextStyle(color: muted, fontSize: 8),
          ),
        ],
      ),
    ),
  );
  return document.save();
}

/// Fetches the receipt, renders the PDF and opens the share sheet (WhatsApp, etc.).
///
/// [memberGymId] is set in the member app: the member's own receipt, with a
/// note for themselves instead of a message from the gym.
Future<void> shareReceipt(
  BuildContext context,
  WidgetRef ref,
  String paymentId, {
  String? memberGymId,
}) async {
  final gymId = memberGymId ?? ref.read(adminGymProvider)?.gymId;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final localizations = MaterialLocalizations.of(context);
  if (gymId == null) return;
  messenger?.showSnackBar(
    const SnackBar(
      content: Text('Preparing receipt…'),
      duration: Duration(seconds: 2),
    ),
  );
  try {
    final receipt = await ref
        .read(receiptRepositoryProvider)
        .get(gymId, paymentId, asMember: memberGymId != null);
    final bytes = await buildReceiptPdf(receipt, localizations);
    await sharePdf(
      bytes,
      title: 'Receipt ${receipt.receiptNumber}',
      text: memberGymId != null
          ? 'Receipt ${receipt.receiptNumber} · ${formatCompactInrPaise(receipt.amountPaise)}'
          : 'Hi ${receipt.memberName.split(' ').first}, here is your receipt '
                '${receipt.receiptNumber} for ${formatCompactInrPaise(receipt.amountPaise)}. '
                'Thank you!',
    );
  } on ReceiptFailure catch (failure) {
    messenger?.showSnackBar(SnackBar(content: Text(failure.message)));
  } catch (_) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('The receipt could not be shared.')),
    );
  }
}

/// After a successful payment, offer the receipt in one tap.
void offerReceipt(
  BuildContext context,
  WidgetRef ref,
  RecordedPayment? payment,
) {
  if (payment == null || payment.status != 'succeeded' || !context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('${formatCompactInrPaise(payment.amountPaise)} recorded'),
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
        label: 'Share receipt',
        onPressed: () => shareReceipt(context, ref, payment.id),
      ),
    ),
  );
}
