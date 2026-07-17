const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Short, human-readable date, e.g. "Jul 8".
String formatShortDate(DateTime date) {
  return '${_months[date.month - 1]} ${date.day}';
}

/// Full, human-readable date with year, e.g. "Jul 8, 2026".
String formatFullDate(DateTime date) {
  return '${_months[date.month - 1]} ${date.day}, ${date.year}';
}
