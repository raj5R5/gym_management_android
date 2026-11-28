import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/members/import/member_import.dart';
import 'package:gym_management_app/features/memberships/models/billing_models.dart';

import '../memberships/billing_fakes.dart';

void main() {
  final monthly = MembershipPlan.fromJson(planJson()); // "Monthly", ₹1,500
  final today = DateTime(2026, 11, 27);

  Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

  group('reading a sheet', () {
    test('CSV with quotes, a BOM and Windows line ends', () {
      final rows = readMemberSheet(
        bytes(
          '﻿Member code,Name,Phone\r\n'
          'M1,"Kumar, Ravi",98765 43210\r\n'
          '\r\n'
          'M2,"Say ""Hi""",9876543211\r\n',
        ),
        'members.csv',
      );
      expect(rows, [
        ['Member code', 'Name', 'Phone'],
        ['M1', 'Kumar, Ravi', '98765 43210'],
        ['M2', 'Say "Hi"', '9876543211'],
      ]);
    });

    test('tab-separated rows pasted from Excel', () {
      final rows = readMemberSheet(
        bytes('Code\tPhone\nM1\t9876543210\n'),
        'x.txt',
      );
      expect(rows.last, ['M1', '9876543210']);
    });

    test('an Excel .xlsx file with shared and inline text', () {
      final archive = Archive()
        ..add(
          ArchiveFile.string(
            'xl/sharedStrings.xml',
            '<sst><si><t>Member code</t></si><si><t>M1</t></si></sst>',
          ),
        )
        ..add(
          ArchiveFile.string(
            'xl/worksheets/sheet1.xml',
            '<worksheet><sheetData>'
                '<row r="1"><c r="A1" t="s"><v>0</v></c>'
                '<c r="C1" t="inlineStr"><is><t>Plan started</t></is></c></row>'
                '<row r="2"><c r="A2" t="s"><v>1</v></c>'
                '<c r="C2"><v>46327</v></c></row>'
                '</sheetData></worksheet>',
          ),
        );
      final file = Uint8List.fromList(ZipEncoder().encode(archive));
      final rows = readMemberSheet(file, 'members.xlsx');
      expect(rows, [
        ['Member code', '', 'Plan started'],
        ['M1', '', '46327'],
      ]);
    });
  });

  group('checking rows', () {
    List<ImportRow> check(String csv) => checkImportRows(
      readMemberSheet(bytes(csv), 'a.csv'),
      [monthly],
      today: today,
    );

    test('a good member becomes an existing-member request', () {
      final rows = check(
        'Member code,First name,Last name,Phone,Plan,Plan started,Paid,Method\n'
        'M1,Ravi,Kumar,9876543210,monthly,01/11/2026,500,UPI\n',
      );
      final row = rows.single;
      expect(row.problems, isEmpty);
      expect(row.plan!.id, monthly.id);
      expect(row.startDate.toString(), '2026-11-01');
      final body = row.toRequest().toJson();
      final membership = body['membership'] as Map<String, dynamic>;
      expect(membership['startDate'], '2026-11-01');
      final payment = membership['payment'] as Map<String, dynamic>;
      expect(payment['amountPaise'], 50000);
      expect(payment['method'], 'upi');
      expect(payment['openingBalance'], isTrue);
      expect(payment.containsKey('reference'), isFalse);
    });

    test('a sheet without a code column sends no code', () {
      final row = check(
        'Name,Phone,Plan,Start date\nRavi Kumar,9876543210,Monthly,2026-11-20\n',
      ).single;
      expect(row.problems, isEmpty);
      expect(
        (row.toRequest().toJson()['member'] as Map).containsKey('memberCode'),
        isFalse,
      );
    });

    test('nothing paid sends no payment', () {
      final row = check(
        'Code,Name,Phone,Plan,Start date\nM1,Ravi Kumar,9876543210,Monthly,2026-11-20\n',
      ).single;
      expect(row.firstName, 'Ravi');
      expect(row.lastName, 'Kumar');
      final membership = row.toRequest().toJson()['membership'] as Map;
      expect(membership.containsKey('payment'), isFalse);
    });

    test('each problem is named on its row', () {
      final rows = check(
        'Code,Name,Phone,Plan,Start date,Paid\n'
        'M1,Ravi,123,Gold,2027-01-01,99999\n'
        'M2,Asha,9876543211,Monthly,31/02/2026,\n'
        'M2,Neha,+91 98765 43211,Monthly,2026-11-01,\n',
      );
      expect(rows[0].problems, [
        contains('Phone'),
        'No active plan named "Gold"',
        'Plan started is in the future',
      ]);
      expect(rows[1].problems.single, contains('use a date like'));
      // A repeated code is fine; the same phone written differently is not.
      expect(rows[2].problems, ['Same phone as row 3']);
      expect(() => rows[0].toRequest(), throwsFormatException);
    });

    test('paying more than the plan costs is caught', () {
      final row = check(
        'Code,Name,Phone,Plan,Start date,Paid\nM1,Ravi,9876543210,Monthly,2026-11-01,2000\n',
      ).single;
      expect(row.problems, ['Paid is more than the plan price']);
    });

    test('a sheet without the needed columns says which are missing', () {
      expect(
        () => check('Name,Phone\nRavi,9876543210\n'),
        throwsA(
          isA<MemberSheetFailure>().having(
            (error) => error.message,
            'message',
            contains('these column titles: Plan, Plan started'),
          ),
        ),
      );
    });

    test('Excel day numbers are read as dates', () {
      final row = checkImportRows(
        [
          ['Code', 'Name', 'Phone', 'Plan', 'Plan started'],
          ['M1', 'Ravi', '9876543210', 'Monthly', '46327'],
        ],
        [monthly],
        today: today,
      ).single;
      expect(row.startDate.toString(), '2026-11-01');
    });

    test('the template itself checks out', () {
      final rows = checkImportRows(
        readMemberSheet(bytes(memberImportTemplate), 'template.csv'),
        [monthly],
        today: today,
      );
      expect(rows.single.problems, isEmpty);
    });
  });
}
