import '../data/client.dart';

const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];
const _weekdaysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
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

String _clock(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

int _daysAgo(DateTime at, DateTime now) => DateTime(
  now.year,
  now.month,
  now.day,
).difference(DateTime(at.year, at.month, at.day)).inDays;

String _date(NekodotClient c, DateTime at, DateTime now) {
  final day = c.tr(
    '${at.month}月${at.day}日',
    '${_months[at.month - 1]} ${at.day}',
  );
  return at.year == now.year
      ? day
      : c.tr('${at.year}年$day', '$day, ${at.year}');
}

/// Between messages after a pause: "今天 12:54", "昨天 21:55", "11月4日 09:30".
String dividerTime(NekodotClient c, DateTime at, [DateTime? now]) {
  now ??= DateTime.now();
  final days = _daysAgo(at, now);
  final day = switch (days) {
    0 => c.tr('今天', 'Today'),
    1 => c.tr('昨天', 'Yesterday'),
    _ => _date(c, at, now),
  };
  return '$day ${_clock(at)}';
}

/// Beside a conversation in a list: the time today, then 昨天, a weekday within
/// the week, then the date.
String rowTime(NekodotClient c, DateTime at, [DateTime? now]) {
  now ??= DateTime.now();
  final days = _daysAgo(at, now);
  if (days <= 0) return _clock(at);
  if (days == 1) return c.tr('昨天', 'Yesterday');
  if (days < 7) {
    return c.tr('星期${_weekdays[at.weekday - 1]}', _weekdaysEn[at.weekday - 1]);
  }
  return _date(c, at, now);
}
