import 'package:christman_coordination/state/view_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('view sizes are kept in range and survive saving', () {
    final v = const ViewPrefs().copyWith(listW: 5000, photoShare: 0.1, descSize: 22, dayW: 12.5, cardTint: 0.3);
    expect(v.listW, ViewPrefs.listMax);
    expect(v.photoShare, ViewPrefs.photoMin);
    final back = ViewPrefs.fromJson(v.toJson());
    expect(back, v);
    expect(const ViewPrefs().copyWith(dayW: 0).dayW, 0);
    expect(ViewPrefs.fromJson(null), const ViewPrefs());
  });
}
