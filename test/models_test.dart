import 'package:christman_coordination/models.dart';
import 'package:christman_coordination/util/dates.dart';
import 'package:flutter_test/flutter_test.dart';

Item _item({String status = 'open', String? due}) => Item.fromJson({
      'id': 'i1',
      'project_id': 'p1',
      'type_id': 't1',
      'number': 'NMC-CL-014',
      'title': 'Supply duct hits W14 beam at C-4',
      'status': status,
      'priority': 'urgent',
      'trade_ids': ['a', 'b'],
      'bic_trade_ids': ['a'],
      'bic_since': '2026-10-28T12:00:00Z',
      'due_date': due,
      'created_by': 'u1',
      'created_at': '2026-10-27T14:42:00Z',
      'updated_at': '2026-10-28T12:00:00Z',
      'level': 'Level 3',
      'zone': 'Zone B',
      'grid': 'C-4 / D-5',
      'clash_id': '2147',
    });

void main() {
  test('status names round-trip with the database', () {
    for (final s in ItemStatus.values) {
      expect(ItemStatus.fromDb(s.db), s);
    }
    expect(ItemStatus.fromDb('void'), ItemStatus.voided);
    expect(ItemStatus.fromDb('nonsense'), ItemStatus.open);
  });

  test('overdue counts whole days past the due date', () {
    final now = DateTime.now();
    final threeDaysAgo = dayOnly(now).subtract(const Duration(days: 3));
    final item = _item(due: dateToDb(threeDaysAgo));
    expect(item.overdueDays(now), 3);
    expect(item.isOverdue, isTrue);
    expect(overdueText(3), 'OVERDUE · 3 days');
    expect(overdueText(1), 'OVERDUE · 1 day');
  });

  test('closed and on-hold items are never overdue', () {
    final old = dateToDb(DateTime(2020, 1, 1));
    expect(_item(status: 'closed', due: old).isOverdue, isFalse);
    expect(_item(status: 'on_hold', due: old).isOverdue, isFalse);
    expect(_item(status: 'void', due: old).isOverdue, isFalse);
  });

  test('due today is not overdue', () {
    expect(_item(due: dateToDb(DateTime.now())).isOverdue, isFalse);
  });

  test('location and search text', () {
    final item = _item();
    expect(item.locationText, 'Level 3 · Zone B · C-4 / D-5');
    expect(item.searchText.contains('2147'), isTrue);
    expect(item.searchText.contains('nmc-cl-014'), isTrue);
    expect(item.searchText.contains('c-4'), isTrue);
  });

  test('initials and first-sign-in check', () {
    final p = Profile(id: 'x', name: 'Rady Radwan', email: 'rady@christman.test');
    expect(p.initials, 'RR');
    final fresh = Profile(id: 'y', name: 'mike', email: 'mike@hart.test');
    expect(fresh.needsDetails, isTrue);
  });

  test('history lines read plainly', () {
    final e = ItemEvent(id: 1, itemId: 'i', kind: 'ball', fromValue: 'Structural Steel', toValue: 'Mechanical', createdAt: DateTime.now());
    expect(e.describe(), 'Ball moved: Structural Steel → Mechanical');
    final st = ItemEvent(id: 2, itemId: 'i', kind: 'status', fromValue: 'in_review', toValue: 'response_submitted', createdAt: DateTime.now());
    expect(st.describe(), 'Status: Assigned / In Review → Response Submitted');
  });
}
