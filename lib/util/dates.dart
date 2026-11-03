const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String shortDate(DateTime d) {
  final now = DateTime.now();
  final s = '${_months[d.month - 1]} ${d.day}';
  return d.year == now.year ? s : '$s, ${d.year}';
}

/// "Fri, Oct 30" (adds the year when it is not this year).
String weekdayDate(DateTime d) => '${_weekdays[d.weekday - 1]}, ${shortDate(d)}';

/// "Today", "Yesterday" or "Oct 9".
String dayText(DateTime d, [DateTime? now]) {
  final today = dayOnly(now ?? DateTime.now());
  final diff = today.difference(dayOnly(d)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return shortDate(d);
}

String timeText(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// "Today, 9:42 AM" / "Oct 27, 9:42 AM"
String dayTimeText(DateTime d) => '${dayText(d)}, ${timeText(d)}';

/// When an item was raised: "Tue, Oct 27, 2026 · 9:42 AM" (day, hour and minute).
String raisedText(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}, ${d.year} · ${timeText(d)}';

/// "Due today", "Due tomorrow", "Due Fri, Nov 6".
String dueText(DateTime due, [DateTime? now]) {
  final days = dayOnly(due).difference(dayOnly(now ?? DateTime.now())).inDays;
  if (days == 0) return 'Due today';
  if (days == 1) return 'Due tomorrow';
  return 'Due ${weekdayDate(due)}';
}

/// "OVERDUE · 3 days"
String overdueText(int days) => 'OVERDUE · $days ${days == 1 ? 'day' : 'days'}';

/// "2 days", "5 hrs", "20 min"
String spanText(Duration d) {
  if (d.isNegative) d = -d;
  if (d.inDays > 0) return '${d.inDays} ${d.inDays == 1 ? 'day' : 'days'}';
  if (d.inHours > 0) return '${d.inHours} ${d.inHours == 1 ? 'hr' : 'hrs'}';
  return '${d.inMinutes < 1 ? 1 : d.inMinutes} min';
}

/// "5 min ago", "3 hrs ago", "Yesterday", "Oct 9"
String agoText(DateTime d, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final diff = n.difference(d);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24 && dayOnly(n) == dayOnly(d)) return '${diff.inHours} ${diff.inHours == 1 ? 'hr' : 'hrs'} ago';
  return dayText(d, n);
}

/// The four groups used by the "By Date" view.
enum DateGroup { thisWeek, pastWeek, thisMonth, older }

class DateGroups {
  DateGroups(DateTime now) {
    today = dayOnly(now);
    thisWeekStart = today.subtract(Duration(days: today.weekday - 1)); // Monday
    pastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
    monthStart = DateTime(today.year, today.month, 1);
  }

  late final DateTime today, thisWeekStart, pastWeekStart, monthStart;

  DateGroup groupOf(DateTime d) {
    if (!d.isBefore(thisWeekStart)) return DateGroup.thisWeek;
    if (!d.isBefore(pastWeekStart)) return DateGroup.pastWeek;
    if (!d.isBefore(monthStart)) return DateGroup.thisMonth;
    return DateGroup.older;
  }

  static String label(DateGroup g) => switch (g) {
        DateGroup.thisWeek => 'This week',
        DateGroup.pastWeek => 'Past week',
        DateGroup.thisMonth => 'Earlier this month',
        DateGroup.older => 'Older',
      };
}
