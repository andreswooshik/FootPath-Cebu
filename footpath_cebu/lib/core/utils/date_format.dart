const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Short, human-readable date, e.g. "Jul 8".
String formatShortDate(DateTime date) {
  return '${_months[date.month - 1]} ${date.day}';
}
