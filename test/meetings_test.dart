import 'package:christman_coordination/models.dart';
import 'package:christman_coordination/util/minutes_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

Meeting _meeting() => Meeting.fromJson({
      'id': 'm1',
      'project_id': 'p1',
      'number': 3,
      'title': 'Weekly MEP Coordination Meeting',
      'starts_at': '2026-11-05T16:00:00Z',
      'duration_min': 90,
      'location': 'Site trailer',
      'attendees': [
        {'name': 'Rady Radwan', 'company': 'The Christman Company', 'role': 'Coordinator', 'present': true},
        {'name': 'Mike Torres', 'company': 'Hart Mechanical', 'role': 'Mechanical', 'present': false},
      ],
      'summary': 'Level 2 hospital is close to sign-off.\nSteel confirmed no web penetrations at moment frames.',
      'items': [
        {'id': 'i1', 'number': 'NMC-CL-014', 'title': 'Supply duct hits W14 beam at C-4', 'status': 'in_review', 'priority': 'urgent', 'ball': 'Mechanical + Plumbing', 'note': 'Drop the duct 6 in.; Plumbing to shift the 4 in. line.'},
      ],
      'actions': [
        {'text': 'Upload revised mechanical model', 'owner': 'Mechanical', 'due': '2026-11-10', 'done': false},
        {'text': 'Confirm ceiling height with architect', 'owner': 'Christman VDC', 'due': null, 'done': true},
      ],
      'agenda': [
        {'text': 'Review open action items', 'owner': 'Christman VDC', 'minutes': 10},
        {'text': 'Level 2 hospital clashes', 'owner': 'Mechanical', 'minutes': 30},
      ],
      'prep': [
        {'text': 'Upload latest model', 'owner': 'All trades', 'due': '2026-11-11', 'done': false},
      ],
      'next_meeting': '2026-11-12T16:00:00Z',
      'updated_at': '2026-11-05T18:00:00Z',
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('meeting reads attendees, items and actions', () {
    final m = _meeting();
    expect(m.attendees.length, 2);
    expect(m.attendees.where((a) => a.present).length, 1);
    expect(m.items.single.ball, 'Mechanical + Plumbing');
    expect(m.openActions, 1);
    expect(m.hasMinutes, isTrue);
    expect(m.endsAt.difference(m.startsAt).inMinutes, 90);
    expect(m.agenda.length, 2);
    expect(m.agenda.last.minutes, 30);
    expect(m.prep.single.owner, 'All trades');
  });

  test('minutes PDF builds', () async {
    final bytes = await buildMinutesPdf(
      meeting: _meeting(),
      project: Project(id: 'p1', name: 'Newcastle Medical Center', code: 'NMC'),
      recordedBy: 'Rady Radwan',
    );
    expect(bytes.length, greaterThan(2000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('schedule task days and state', () {
    final t = ScheduleTask.fromJson({
      'id': 't1',
      'project_id': 'p1',
      'name': 'L2 Hospital coordination',
      'kind': 'coordination',
      'start_date': '2026-11-02',
      'end_date': '2026-11-13',
      'percent': 40,
    });
    expect(t.days, 12);
    expect(t.isCurrent(DateTime(2026, 11, 5)), isTrue);
    expect(t.isLate(DateTime(2026, 11, 20)), isTrue);
    final so = ScheduleTask.fromJson({
      'id': 't2', 'project_id': 'p1', 'name': 'L2 sign-off', 'kind': 'sign_off', 'start_date': '2026-11-14', 'end_date': '2026-11-14',
    });
    expect(so.isPoint, isTrue);
    expect(so.kind, TaskKind.signOff);
  });
}
