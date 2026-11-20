/// Plain date formatting without an extra dependency.
library;

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `2026-11-20` → `20 Nov 2026`.
String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// `2026-11-20 14:05` → `20 Nov 2026, 14:05`.
String formatDateTime(DateTime d) =>
    '${formatDate(d)}, ${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}';
