/// Minimaler, robuster CSV-Parser (RFC 4180 + übliche Bank-Abweichungen):
/// Anführungszeichen, verdoppelte Anführungszeichen, Zeilenumbrüche in Feldern.
List<List<String>> parseCsv(String input, {String? delimiter}) {
  final d = delimiter ?? detectDelimiter(input);
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < input.length; i++) {
    final c = input[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < input.length && input[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(c);
      }
      continue;
    }
    if (c == '"' && field.toString().trim().isEmpty) {
      field.clear();
      inQuotes = true;
    } else if (c == d) {
      row.add(field.toString().trim());
      field.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < input.length && input[i + 1] == '\n') i++;
      row.add(field.toString().trim());
      field.clear();
      if (row.any((f) => f.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      field.write(c);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString().trim());
    if (row.any((f) => f.isNotEmpty)) rows.add(row);
  }
  return rows;
}

/// Wählt das Trennzeichen, das in den ersten Zeilen am häufigsten außerhalb von Anführungszeichen vorkommt.
String detectDelimiter(String input) {
  final sample = input.length > 4000 ? input.substring(0, 4000) : input;
  final counts = {';': 0, ',': 0, '\t': 0, '|': 0};
  var inQuotes = false;
  for (final ch in sample.split('')) {
    if (ch == '"') inQuotes = !inQuotes;
    if (!inQuotes && counts.containsKey(ch)) counts[ch] = counts[ch]! + 1;
  }
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}
