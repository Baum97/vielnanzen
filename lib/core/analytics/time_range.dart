/// Auswählbare Zeiträume für Verläufe und Auswertungen.
enum TimeRange {
  w1('1W', 'Letzte Woche'),
  m1('1M', 'Letzter Monat'),
  m3('3M', 'Letzte 3 Monate'),
  m6('6M', 'Letzte 6 Monate'),
  ytd('YTD', 'Seit Jahresbeginn'),
  y1('1J', 'Letztes Jahr'),
  y5('5J', 'Letzte 5 Jahre'),
  max('Max', 'Gesamter Zeitraum');

  const TimeRange(this.short, this.label);

  final String short;
  final String label;

  static TimeRange fromName(String? name) => TimeRange.values.firstWhere((r) => r.name == name, orElse: () => TimeRange.m1);

  /// Startzeitpunkt (inklusive) relativ zu [now]. `max` braucht das früheste Datum.
  DateTime start(DateTime now, {DateTime? earliest}) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      TimeRange.w1 => today.subtract(const Duration(days: 6)),
      TimeRange.m1 => _monthsBack(today, 1),
      TimeRange.m3 => _monthsBack(today, 3),
      TimeRange.m6 => _monthsBack(today, 6),
      TimeRange.ytd => DateTime(today.year, 1, 1),
      TimeRange.y1 => _monthsBack(today, 12),
      TimeRange.y5 => _monthsBack(today, 60),
      TimeRange.max => earliest == null ? _monthsBack(today, 60) : DateTime(earliest.year, earliest.month, earliest.day),
    };
  }

  /// Gleicher Tag n Monate zuvor (auf Monatsende gekappt), plus ein Tag.
  static DateTime _monthsBack(DateTime today, int n) {
    final first = DateTime(today.year, today.month - n, 1);
    final lastDay = DateTime(first.year, first.month + 1, 0).day;
    final d = today.day > lastDay ? lastDay : today.day;
    return DateTime(first.year, first.month, d + 1);
  }

  /// Ende (exklusiv): morgen 0 Uhr.
  DateTime end(DateTime now) => DateTime(now.year, now.month, now.day + 1);

  /// Zeitraum gleicher Länge direkt davor – für „ggü. Vorperiode“.
  ({DateTime from, DateTime to}) previous(DateTime now, {DateTime? earliest}) {
    final from = start(now, earliest: earliest);
    final to = end(now);
    if (this == TimeRange.ytd) {
      // YTD: gleicher Zeitraum im Vorjahr
      return (from: DateTime(from.year - 1, 1, 1), to: DateTime(to.year - 1, to.month, to.day));
    }
    final length = to.difference(from);
    return (from: from.subtract(length), to: from);
  }
}

/// Granularität für Diagramm-Balken.
enum Bucket { day, week, month, quarter, year }

extension BucketFor on TimeRange {
  /// Passende Balkengröße, damit Diagramme lesbar bleiben (ca. 7–30 Balken).
  Bucket bucketFor(int spanDays) {
    if (spanDays <= 14) return Bucket.day;
    if (spanDays <= 93) return Bucket.week;
    if (spanDays <= 3 * 366) return Bucket.month;
    if (spanDays <= 8 * 366) return Bucket.quarter;
    return Bucket.year;
  }
}

/// Anfang des Buckets, in den [d] fällt.
DateTime bucketStart(DateTime d, Bucket b) => switch (b) {
      Bucket.day => DateTime(d.year, d.month, d.day),
      Bucket.week => DateTime(d.year, d.month, d.day - (d.weekday - 1)),
      Bucket.month => DateTime(d.year, d.month, 1),
      Bucket.quarter => DateTime(d.year, ((d.month - 1) ~/ 3) * 3 + 1, 1),
      Bucket.year => DateTime(d.year, 1, 1),
    };

DateTime nextBucket(DateTime d, Bucket b) => switch (b) {
      Bucket.day => DateTime(d.year, d.month, d.day + 1),
      Bucket.week => DateTime(d.year, d.month, d.day + 7),
      Bucket.month => DateTime(d.year, d.month + 1, 1),
      Bucket.quarter => DateTime(d.year, d.month + 3, 1),
      Bucket.year => DateTime(d.year + 1, 1, 1),
    };
