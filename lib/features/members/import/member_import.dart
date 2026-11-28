import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../admin_dashboard/models/dashboard_models.dart' show CalendarDate;
import '../../memberships/models/billing_models.dart';
import '../models/member_draft.dart';
import '../models/onboarding_models.dart';

/// The columns a member sheet can have, with the header names people use.
enum ImportColumn {
  memberCode('Member code', ['member code', 'code', 'member id', 'id']),
  firstName('First name', ['first name', 'firstname', 'first']),
  lastName('Last name', ['last name', 'lastname', 'surname', 'last']),
  fullName('Name', ['name', 'full name', 'member name']),
  phone('Phone', ['phone', 'mobile', 'phone number', 'mobile number']),
  plan('Plan', ['plan', 'plan name', 'membership', 'package']),
  startDate('Plan started', [
    'plan started',
    'start date',
    'started',
    'start',
    'joined',
    'joining date',
  ]),
  paid('Paid', ['paid', 'amount paid', 'paid (₹)', 'paid (rs)', 'paid amount']),
  method('Method', ['method', 'payment method', 'mode', 'payment mode']);

  const ImportColumn(this.label, this.aliases);
  final String label;
  final List<String> aliases;

  static ImportColumn? forHeader(String header) {
    final key = header.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    for (final column in values) {
      if (column.aliases.contains(key)) return column;
    }
    return null;
  }
}

/// The template a gym fills in: one header row and one example member.
const memberImportTemplate =
    'First name,Last name,Phone,Plan,Plan started,Paid,Method\n'
    'Ravi,Kumar,9876543210,Monthly,2026-11-01,1500,cash\n';

class MemberSheetFailure implements Exception {
  const MemberSheetFailure(this.message);
  final String message;
  @override
  String toString() => 'MemberSheetFailure: $message';
}

/// Reads a CSV (comma, tab or semicolon) or an Excel .xlsx sheet into rows of
/// text. Empty rows are dropped.
List<List<String>> readMemberSheet(Uint8List bytes, String fileName) {
  final rows = fileName.toLowerCase().endsWith('.xlsx')
      ? _readXlsx(bytes)
      : _readCsv(utf8.decode(bytes, allowMalformed: true));
  return [
    for (final row in rows)
      if (row.any((cell) => cell.trim().isNotEmpty))
        [for (final cell in row) cell.trim()],
  ];
}

List<List<String>> _readCsv(String text) {
  final source = text.startsWith('﻿') ? text.substring(1) : text;
  final firstLine = source.split('\n').first;
  final delimiter = ['\t', ';', ','].reduce(
    (a, b) => firstLine.split(a).length >= firstLine.split(b).length ? a : b,
  );
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (quoted) {
      if (char == '"') {
        if (i + 1 < source.length && source[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(char);
      }
    } else if (char == '"') {
      quoted = true;
    } else if (char == delimiter) {
      row.add(cell.toString());
      cell.clear();
    } else if (char == '\n' || char == '\r') {
      if (char == '\r' && i + 1 < source.length && source[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = <String>[];
    } else {
      cell.write(char);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}

List<List<String>> _readXlsx(Uint8List bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } on Object {
    throw const MemberSheetFailure('This Excel file could not be opened.');
  }
  String? file(String name) {
    final entry = archive.findFile(name);
    return entry == null ? null : utf8.decode(entry.content);
  }

  final shared = <String>[];
  if (file('xl/sharedStrings.xml') case final xml?) {
    for (final item in XmlDocument.parse(xml).findAllElements('si')) {
      shared.add(item.findAllElements('t').map((t) => t.innerText).join());
    }
  }
  final sheet = file('xl/worksheets/sheet1.xml');
  if (sheet == null) {
    throw const MemberSheetFailure('The Excel file has no first sheet.');
  }
  final rows = <List<String>>[];
  for (final row in XmlDocument.parse(sheet).findAllElements('row')) {
    final cells = <String>[];
    for (final cell in row.findElements('c')) {
      final ref = cell.getAttribute('r') ?? '';
      final column = _columnIndex(ref);
      while (cells.length < column) {
        cells.add('');
      }
      final type = cell.getAttribute('t');
      final value = cell.getElement('v')?.innerText ?? '';
      cells.add(switch (type) {
        's' => shared.elementAtOrNull(int.tryParse(value) ?? -1) ?? '',
        'inlineStr' => cell.findAllElements('t').map((t) => t.innerText).join(),
        _ => value,
      });
    }
    rows.add(cells);
  }
  return rows;
}

/// "C7" → 2.
int _columnIndex(String ref) {
  var index = 0;
  for (final unit in ref.codeUnits) {
    if (unit < 65 || unit > 90) break;
    index = index * 26 + (unit - 64);
  }
  return index == 0 ? 0 : index - 1;
}

/// One member from the sheet, checked against the gym's plans.
class ImportRow {
  ImportRow({
    required this.line,
    required this.memberCode,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.plan,
    required this.startDate,
    required this.paidPaise,
    required this.method,
    required this.problems,
  });

  /// The sheet row number, counting the header as 1.
  final int line;
  final String memberCode, firstName, lastName, phone;
  final MembershipPlan? plan;
  final CalendarDate? startDate;
  final int paidPaise;
  final PaymentMethod method;
  final List<String> problems;

  bool get ok => problems.isEmpty;
  String get name => '$firstName $lastName'.trim();

  /// The same request Add member sends for an existing member.
  OnboardingRequest toRequest() {
    if (!ok) throw const FormatException('Fix this row before importing.');
    final day = startDate!.value;
    final midday = DateTime(day.year, day.month, day.day, 12);
    final now = DateTime.now();
    return OnboardingRequest(
      member: MemberDraft(
        memberCode: memberCode,
        firstName: firstName,
        lastName: lastName,
        phone: phone,
      ),
      membership: OnboardingMembership(
        planId: plan!.id,
        startDate: startDate,
        payment: paidPaise == 0
            ? null
            : OnboardingPayment(
                method: method,
                amountPaise: paidPaise,
                paidAt: midday.isAfter(now) ? now : midday,
                openingBalance: true,
              ),
      ),
    );
  }
}

/// Turns sheet rows into checked members. The first row must be the header.
List<ImportRow> checkImportRows(
  List<List<String>> rows,
  List<MembershipPlan> plans, {
  DateTime? today,
}) {
  if (rows.isEmpty) throw const MemberSheetFailure('The sheet is empty.');
  final header = <ImportColumn, int>{};
  for (final (index, title) in rows.first.indexed) {
    final column = ImportColumn.forHeader(title);
    if (column != null) header.putIfAbsent(column, () => index);
  }
  final hasName =
      header.containsKey(ImportColumn.fullName) ||
      header.containsKey(ImportColumn.firstName);
  final missing = [
    if (!hasName) 'First name',
    if (!header.containsKey(ImportColumn.phone)) 'Phone',
    if (!header.containsKey(ImportColumn.plan)) 'Plan',
    if (!header.containsKey(ImportColumn.startDate)) 'Plan started',
  ];
  if (missing.isNotEmpty) {
    throw MemberSheetFailure(
      'The first row needs these column titles: ${missing.join(', ')}.',
    );
  }
  final now = today ?? DateTime.now();
  final todayUtc = DateTime.utc(now.year, now.month, now.day);
  final earliest = DateTime.utc(now.year - 3, now.month, now.day);
  final byName = {
    for (final plan in plans)
      if (plan.status == 'active') plan.name.trim().toLowerCase(): plan,
  };
  final phones = <String, int>{};
  final result = <ImportRow>[];
  for (final (index, cells) in rows.skip(1).indexed) {
    String cell(ImportColumn column) {
      final at = header[column];
      return at == null || at >= cells.length ? '' : cells[at].trim();
    }

    final problems = <String>[];
    var first = cell(ImportColumn.firstName);
    var last = cell(ImportColumn.lastName);
    if (first.isEmpty && cell(ImportColumn.fullName).isNotEmpty) {
      final parts = cell(ImportColumn.fullName).split(RegExp(r'\s+'));
      first = parts.first;
      last = parts.skip(1).join(' ');
    }
    if (last.isEmpty) last = '.';
    final code = cell(ImportColumn.memberCode);
    final phone = cell(ImportColumn.phone).replaceAll(RegExp(r'[\s-]'), '');
    if (validateMemberCode(code) case final error?) {
      problems.add('Member code: $error');
    }
    if (validateName(first) case final error?) problems.add('Name: $error');
    if (validatePhone(phone) case final error?) problems.add('Phone: $error');
    final line = index + 2;
    // Codes may repeat; each member needs their own phone number.
    if (phone.isNotEmpty) {
      if (phones[memberPhoneKey(phone)] case final other?) {
        problems.add('Same phone as row $other');
      } else {
        phones[memberPhoneKey(phone)] = line;
      }
    }
    final planName = cell(ImportColumn.plan);
    final plan = byName[planName.toLowerCase()];
    if (plan == null) {
      problems.add(
        planName.isEmpty
            ? 'Plan is missing'
            : 'No active plan named "$planName"',
      );
    }
    final start = _parseDay(cell(ImportColumn.startDate));
    if (start == null) {
      problems.add('Plan started: use a date like 2026-11-01 or 01/11/2026');
    } else if (start.value.isAfter(todayUtc)) {
      problems.add('Plan started is in the future');
    } else if (start.value.isBefore(earliest)) {
      problems.add('Plan started is more than 3 years ago');
    }
    var paid = 0;
    final paidText = cell(ImportColumn.paid).replaceAll(RegExp(r'[₹,\s]'), '');
    if (paidText.isNotEmpty) {
      final rupees = num.tryParse(paidText);
      if (rupees == null || rupees < 0) {
        problems.add('Paid must be an amount like 1500');
      } else {
        paid = (rupees * 100).round();
        if (plan != null && paid > plan.pricePaise) {
          problems.add('Paid is more than the plan price');
        }
      }
    }
    final methodText = cell(ImportColumn.method).toLowerCase();
    final method = switch (methodText) {
      '' || 'cash' => PaymentMethod.cash,
      'upi' || 'gpay' || 'phonepe' || 'paytm' => PaymentMethod.upi,
      'card' => PaymentMethod.card,
      'bank' ||
      'bank transfer' ||
      'bank_transfer' ||
      'neft' ||
      'imps' => PaymentMethod.bankTransfer,
      _ => PaymentMethod.other,
    };
    result.add(
      ImportRow(
        line: line,
        memberCode: code,
        firstName: first,
        lastName: last,
        phone: phone,
        plan: plan,
        startDate: start,
        paidPaise: paid,
        method: method,
        problems: problems,
      ),
    );
  }
  if (result.isEmpty) {
    throw const MemberSheetFailure('The sheet has a header but no members.');
  }
  return result;
}

/// Accepts 2026-11-01, 01/11/2026, 01-11-2026, 1.11.2026 and Excel day numbers.
CalendarDate? _parseDay(String text) {
  final value = text.trim();
  if (value.isEmpty) return null;
  int? y, m, d;
  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(value);
  final dmy = RegExp(
    r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$',
  ).firstMatch(value);
  if (iso != null) {
    (y, m, d) = (int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
  } else if (dmy != null) {
    (y, m, d) = (int.parse(dmy[3]!), int.parse(dmy[2]!), int.parse(dmy[1]!));
  } else if (num.tryParse(value) case final serial?
      when serial > 20000 && serial < 80000) {
    // Excel counts days from 30 Dec 1899.
    final day = DateTime.utc(1899, 12, 30).add(Duration(days: serial.floor()));
    (y, m, d) = (day.year, day.month, day.day);
  }
  if (y == null || m == null || d == null) return null;
  final day = DateTime.utc(y, m, d);
  if (day.month != m || day.day != d) return null;
  try {
    return CalendarDate.parse(
      '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}',
    );
  } on FormatException {
    return null;
  }
}
