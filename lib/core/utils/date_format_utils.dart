const _monthNames = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Agu',
  'Sep',
  'Okt',
  'Nov',
  'Des',
];

DateTime? toWib(DateTime? value) {
  if (value == null) return null;
  return value.toUtc().add(const Duration(hours: 7));
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String formatWibTime(DateTime? value) {
  final wib = toWib(value);
  if (wib == null) return '--.--';
  return '${_twoDigits(wib.hour)}.${_twoDigits(wib.minute)}';
}

String formatWibDate(DateTime? value) {
  final wib = toWib(value);
  if (wib == null) return '--';
  return '${wib.day} ${_monthNames[wib.month - 1]} ${wib.year}';
}

String formatWibDateTime(DateTime? value) {
  final wib = toWib(value);
  if (wib == null) return 'Belum ada data';
  return '${wib.day} ${_monthNames[wib.month - 1]} ${wib.year} · '
      '${_twoDigits(wib.hour)}.${_twoDigits(wib.minute)} WIB';
}

String relativeTime(DateTime? value, {DateTime? now}) {
  if (value == null) return 'Belum ada data';

  final current = now ?? DateTime.now();
  final difference = current.difference(value);
  if (difference.isNegative || difference.inSeconds < 10) {
    return 'Baru saja';
  }
  if (difference.inMinutes < 1) {
    return '${difference.inSeconds} dtk lalu';
  }
  if (difference.inHours < 1) {
    return '${difference.inMinutes} mnt lalu';
  }
  if (difference.inDays < 1) {
    return '${difference.inHours} jam lalu';
  }
  if (difference.inDays < 7) {
    return '${difference.inDays} hari lalu';
  }
  return formatWibDateTime(value);
}
