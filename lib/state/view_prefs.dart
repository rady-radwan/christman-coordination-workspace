/// Sizes each person chooses for their own screen: panel widths, the item photo,
/// the description text, card colors and the schedule zoom. Saved on the account
/// (inside profile prefs, under "view") and on this device.
class ViewPrefs {
  const ViewPrefs({
    this.sidebarW = 248,
    this.listW = 420,
    this.factsW = 300,
    this.photoShare = 0.5,
    this.descSize = 17,
    this.cardTint = 0.5,
    this.dayW = 0,
    this.taskColW = 280,
  });

  /// Panel widths (pixels): sidebar, item list, the item's right-hand facts column.
  final double sidebarW, listW, factsW;

  /// Part of the item's middle area taken by the photo (beside the description).
  final double photoShare;

  /// Description text size on an item page.
  final double descSize;

  /// Strength of the priority color on item cards (1 = full, 0 = none).
  final double cardTint;

  /// Schedule zoom: pixels per day, or 0 = fit the whole schedule on screen.
  final double dayW;

  /// Width of the task-name column on the schedule.
  final double taskColW;

  static const sidebarMin = 190.0, sidebarMax = 380.0;
  static const listMin = 300.0, listMax = 760.0;
  static const factsMin = 220.0, factsMax = 520.0;
  static const photoMin = 0.25, photoMax = 0.8;
  static const descMin = 13.0, descMax = 30.0;
  static const dayMin = 3.0, dayMax = 60.0;
  static const taskColMin = 150.0, taskColMax = 520.0;

  static double _c(num v, double lo, double hi) => v.toDouble().clamp(lo, hi).toDouble();

  ViewPrefs copyWith({
    double? sidebarW,
    double? listW,
    double? factsW,
    double? photoShare,
    double? descSize,
    double? cardTint,
    double? dayW,
    double? taskColW,
  }) =>
      ViewPrefs(
        sidebarW: _c(sidebarW ?? this.sidebarW, sidebarMin, sidebarMax),
        listW: _c(listW ?? this.listW, listMin, listMax),
        factsW: _c(factsW ?? this.factsW, factsMin, factsMax),
        photoShare: _c(photoShare ?? this.photoShare, photoMin, photoMax),
        descSize: _c(descSize ?? this.descSize, descMin, descMax),
        cardTint: _c(cardTint ?? this.cardTint, 0, 1),
        dayW: (dayW ?? this.dayW) <= 0 ? 0 : _c(dayW ?? this.dayW, dayMin, dayMax),
        taskColW: _c(taskColW ?? this.taskColW, taskColMin, taskColMax),
      );

  /// Panel widths back to normal.
  ViewPrefs resetPanels() => copyWith(sidebarW: 248, listW: 420, factsW: 300, taskColW: 280);

  Map<String, dynamic> toJson() => {
        'sidebarW': sidebarW.roundToDouble(),
        'listW': listW.roundToDouble(),
        'factsW': factsW.roundToDouble(),
        'photoShare': double.parse(photoShare.toStringAsFixed(2)),
        'descSize': descSize.roundToDouble(),
        'cardTint': double.parse(cardTint.toStringAsFixed(2)),
        'dayW': double.parse(dayW.toStringAsFixed(1)),
        'taskColW': taskColW.roundToDouble(),
      };

  factory ViewPrefs.fromJson(Object? j) {
    if (j is! Map) return const ViewPrefs();
    double? d(String k) => (j[k] as num?)?.toDouble();
    return const ViewPrefs().copyWith(
      sidebarW: d('sidebarW'),
      listW: d('listW'),
      factsW: d('factsW'),
      photoShare: d('photoShare'),
      descSize: d('descSize'),
      cardTint: d('cardTint'),
      dayW: d('dayW'),
      taskColW: d('taskColW'),
    );
  }

  @override
  bool operator ==(Object o) =>
      o is ViewPrefs &&
      o.sidebarW == sidebarW &&
      o.listW == listW &&
      o.factsW == factsW &&
      o.photoShare == photoShare &&
      o.descSize == descSize &&
      o.cardTint == cardTint &&
      o.dayW == dayW &&
      o.taskColW == taskColW;

  @override
  int get hashCode => Object.hash(sidebarW, listW, factsW, photoShare, descSize, cardTint, dayW, taskColW);
}
