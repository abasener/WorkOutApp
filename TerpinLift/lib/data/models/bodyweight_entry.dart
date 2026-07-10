class BodyweightEntry {
  final int? id;
  final String date;
  final double weight;

  const BodyweightEntry({this.id, required this.date, required this.weight});

  factory BodyweightEntry.fromMap(Map<String, dynamic> m) => BodyweightEntry(
        id: m['id'] as int?,
        date: m['date'] as String,
        weight: (m['weight'] as num).toDouble(),
      );

  Map<String, dynamic> toMap() => {'date': date, 'weight': weight};
}
