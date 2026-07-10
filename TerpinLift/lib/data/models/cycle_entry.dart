enum CycleEntryType { flow, symptom }

extension CycleEntryTypeKey on CycleEntryType {
  String get key {
    switch (this) {
      case CycleEntryType.flow:
        return 'flow';
      case CycleEntryType.symptom:
        return 'symptom';
    }
  }

  static CycleEntryType fromKey(String key) =>
      CycleEntryType.values.firstWhere((t) => t.key == key);
}

class CycleEntry {
  final int? id;
  final String date;
  final CycleEntryType entryType;

  /// 0-4 flow score, only meaningful when [entryType] is [CycleEntryType.flow].
  /// 0 means "logged, no bleeding" (distinct from "never logged").
  final int? flowValue;
  final String? symptomTag;
  final String? notes;

  const CycleEntry({
    this.id,
    required this.date,
    required this.entryType,
    this.flowValue,
    this.symptomTag,
    this.notes,
  });

  factory CycleEntry.fromMap(Map<String, dynamic> m) => CycleEntry(
        id: m['id'] as int?,
        date: m['date'] as String,
        entryType: CycleEntryTypeKey.fromKey(m['entry_type'] as String),
        flowValue: m['flow_value'] as int?,
        symptomTag: m['symptom_tag'] as String?,
        notes: m['notes'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'date': date,
        'entry_type': entryType.key,
        'flow_value': flowValue,
        'symptom_tag': symptomTag,
        'notes': notes,
      };
}
