import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../services/calculator_engine.dart';
import '../services/plate_math.dart';
import '../services/units.dart';
import '../theme/app_theme.dart';

/// A scratchpad popup, opened from the "Calc" pill in `LogLiftForm` — never
/// writes anything back into the form itself, purely a mental-math aid.
/// Two tabs: a barbell plate calculator, and a plain 4-function calculator
/// for everything else (plate math on a leg press sled, splitting a
/// dumbbell pair, whatever).
///
/// [initialPlates]/[onPlatesChanged] let the caller carry the Barbell tab's
/// per-side plates across separate opens of this sheet **within the same
/// still-open log entry** — e.g. set 1 of a Deadlift session loads 2x45s,
/// set 2 reopens the calculator already showing them, since the next set of
/// the same lift is usually close to the last. This sheet itself has no
/// memory of its own; the caller (`LogLiftForm`) is what actually persists
/// it, per-exercise, for exactly as long as that one form stays open — nothing
/// is written to storage, and a fresh log or an edit of an already-saved
/// session always starts from just the bar.
class PlateCalculatorSheet extends StatefulWidget {
  final List<double> initialPlates;
  final ValueChanged<List<double>>? onPlatesChanged;

  const PlateCalculatorSheet({
    super.key,
    this.initialPlates = const [],
    this.onPlatesChanged,
  });

  @override
  State<PlateCalculatorSheet> createState() => _PlateCalculatorSheetState();
}

class _PlateCalculatorSheetState extends State<PlateCalculatorSheet> {
  bool _showBarbell = true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.card),
          ),
        ),
        padding: EdgeInsets.fromLTRB(
          AppSpacing.edge,
          AppSpacing.standard,
          AppSpacing.edge,
          AppSpacing.standard + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Calculator', style: AppText.subHeader),
                _ModeToggle(
                  showBarbell: _showBarbell,
                  onChanged: (v) => setState(() => _showBarbell = v),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.large),
            Flexible(
              child: SingleChildScrollView(
                child: _showBarbell
                    ? _BarbellTab(
                        initialPlates: widget.initialPlates,
                        onPlatesChanged: widget.onPlatesChanged,
                      )
                    : const _SimpleCalculatorTab(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final bool showBarbell;
  final ValueChanged<bool> onChanged;
  const _ModeToggle({required this.showBarbell, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pill('Barbell', showBarbell, () => onChanged(true)),
          _pill('Calc', !showBarbell, () => onChanged(false)),
        ],
      ),
    );
  }

  Widget _pill(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          label,
          style: AppText.smallText.copyWith(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _BarbellTab extends StatefulWidget {
  final List<double> initialPlates;
  final ValueChanged<List<double>>? onPlatesChanged;

  const _BarbellTab({this.initialPlates = const [], this.onPlatesChanged});

  @override
  State<_BarbellTab> createState() => _BarbellTabState();
}

class _BarbellTabState extends State<_BarbellTab> {
  late double _barWeight = Units.current == WeightUnit.kg ? 20 : 45;
  final _customBarController = TextEditingController();
  bool _customBar = false;
  final _plateController = TextEditingController();
  late final List<double> _plates = List.of(widget.initialPlates);
  bool _justCopied = false;

  List<double> get _barPresets =>
      Units.current == WeightUnit.kg ? [20, 15] : [45, 35];

  @override
  void dispose() {
    _customBarController.dispose();
    _plateController.dispose();
    super.dispose();
  }

  void _addPlate() {
    final value = double.tryParse(_plateController.text);
    if (value == null || value <= 0) return;
    setState(() {
      _plates.add(value);
      _plates.sort((a, b) => b.compareTo(a));
      _plateController.clear();
    });
    widget.onPlatesChanged?.call(_plates);
  }

  /// Trims a trailing ".0" (`225.0` -> `"225"`) but keeps a real decimal
  /// (`22.5` -> `"22.5"`) — pasted into a gym-log app/text as whatever's
  /// actually needed, not a fixed decimal count.
  String _copyFormat(double v) {
    final rounded = double.parse(v.toStringAsFixed(1));
    return rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1);
  }

  Future<void> _copyTotal(double total) async {
    await Clipboard.setData(ClipboardData(text: _copyFormat(total)));
    if (!mounted) return;
    setState(() => _justCopied = true);
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => _justCopied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = PlateMath.totalWeight(_barWeight, _plates);
    final perSide = _plates.fold<double>(0, (a, b) => a + b);
    final suffix = Units.suffix;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Bar', style: AppText.label),
        const SizedBox(height: AppSpacing.small),
        Wrap(
          spacing: AppSpacing.small,
          runSpacing: AppSpacing.small,
          children: [
            for (final preset in _barPresets)
              _choiceChip(
                '${preset.toStringAsFixed(0)} $suffix',
                !_customBar && _barWeight == preset,
                () => setState(() {
                  _customBar = false;
                  _barWeight = preset;
                }),
              ),
            _choiceChip(
              'Custom',
              _customBar,
              () => setState(() => _customBar = true),
            ),
          ],
        ),
        if (_customBar) ...[
          const SizedBox(height: AppSpacing.standard),
          TextField(
            controller: _customBarController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppText.bodyText,
            decoration: InputDecoration(labelText: 'Bar/sled weight ($suffix)'),
            onChanged: (v) {
              final entered = double.tryParse(v);
              if (entered != null) setState(() => _barWeight = entered);
            },
          ),
        ],
        const SizedBox(height: AppSpacing.large),
        Text('Plates, one side (mirrored automatically)', style: AppText.label),
        const SizedBox(height: AppSpacing.small),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _plateController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: AppText.bodyText,
                decoration: InputDecoration(
                  labelText: 'Plate weight ($suffix)',
                ),
                onSubmitted: (_) => _addPlate(),
              ),
            ),
            const SizedBox(width: AppSpacing.small),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.accent),
                foregroundColor: AppColors.accent,
              ),
              onPressed: _addPlate,
              child: const Text('Add'),
            ),
          ],
        ),
        if (_plates.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.standard),
          // Purely visual mirror — same chip list on both sides of a
          // labeled "BAR" divider, so it reads like a loaded barbell rather
          // than a plain list.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: _plateChips(mirrored: true)),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.small,
                ),
                child: Text('BAR', style: AppText.label),
              ),
              Expanded(child: _plateChips(mirrored: false)),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.large),
        GestureDetector(
          onTap: () => _copyTotal(total),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.cardPad),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Per side: ${perSide.toStringAsFixed(1)} $suffix',
                      style: AppText.smallText,
                    ),
                    Text(
                      _justCopied ? 'Copied!' : 'tap to copy',
                      style: AppText.smallText.copyWith(
                        fontStyle: FontStyle.italic,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.micro),
                Text(
                  'Total: ${total.toStringAsFixed(1)} $suffix',
                  style: AppText.bigNumber,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _plateChips({required bool mirrored}) {
    return Wrap(
      alignment: mirrored ? WrapAlignment.end : WrapAlignment.start,
      spacing: AppSpacing.micro,
      runSpacing: AppSpacing.micro,
      children: _plates.asMap().entries.map((entry) {
        final i = entry.key;
        final plate = entry.value;
        return GestureDetector(
          // Removing from either side removes that plate for both, since
          // they're the same underlying per-side list.
          onTap: () {
            setState(() => _plates.removeAt(i));
            widget.onPlatesChanged?.call(_plates);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.button),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              plate.toStringAsFixed(plate == plate.roundToDouble() ? 0 : 1),
              style: AppText.smallText,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _choiceChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppText.smallText.copyWith(
            color: selected ? Colors.white : AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SimpleCalculatorTab extends StatefulWidget {
  const _SimpleCalculatorTab();

  @override
  State<_SimpleCalculatorTab> createState() => _SimpleCalculatorTabState();
}

class _SimpleCalculatorTabState extends State<_SimpleCalculatorTab> {
  final _engine = CalculatorEngine();
  String _display = '0';
  bool _startingNewNumber = true;

  void _pressDigit(String digit) {
    setState(() {
      if (_startingNewNumber) {
        _display = digit;
        _startingNewNumber = false;
      } else {
        _display = _display == '0' ? digit : _display + digit;
      }
    });
  }

  void _pressDot() {
    if (_display.contains('.')) return;
    setState(() {
      _display = _startingNewNumber ? '0.' : '$_display.';
      _startingNewNumber = false;
    });
  }

  void _pressOperator(CalcOp op) {
    final value = double.tryParse(_display) ?? 0;
    setState(() {
      _display = _formatResult(_engine.onOperator(value, op));
      _startingNewNumber = true;
    });
  }

  void _pressEquals() {
    final value = double.tryParse(_display) ?? 0;
    setState(() {
      _display = _formatResult(_engine.onOperator(value, null));
      _startingNewNumber = true;
    });
  }

  void _pressClear() {
    setState(() {
      _engine.clear();
      _display = '0';
      _startingNewNumber = true;
    });
  }

  String _formatResult(double v) {
    if (v.isNaN || v.isInfinite) return 'Error';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.cardPad),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.border),
          ),
          alignment: Alignment.centerRight,
          child: Text(_display, style: AppText.bigNumber),
        ),
        const SizedBox(height: AppSpacing.standard),
        _row(['7', '8', '9', '÷']),
        const SizedBox(height: AppSpacing.small),
        _row(['4', '5', '6', '×']),
        const SizedBox(height: AppSpacing.small),
        _row(['1', '2', '3', '−']),
        const SizedBox(height: AppSpacing.small),
        _row(['C', '0', '.', '+']),
        const SizedBox(height: AppSpacing.small),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
            ),
            onPressed: _pressEquals,
            child: const Text('='),
          ),
        ),
      ],
    );
  }

  Widget _row(List<String> keys) {
    return Row(
      children: [
        for (final key in keys) ...[
          Expanded(child: _key(key)),
          if (key != keys.last) const SizedBox(width: AppSpacing.small),
        ],
      ],
    );
  }

  Widget _key(String label) {
    const opMap = {
      '+': CalcOp.add,
      '−': CalcOp.subtract,
      '×': CalcOp.multiply,
      '÷': CalcOp.divide,
    };
    final isOp = opMap.containsKey(label);
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: isOp ? AppColors.accent : AppColors.border),
          foregroundColor: isOp ? AppColors.accent : AppColors.textPrimary,
        ),
        onPressed: () {
          if (label == 'C') {
            _pressClear();
          } else if (label == '.') {
            _pressDot();
          } else if (isOp) {
            _pressOperator(opMap[label]!);
          } else {
            _pressDigit(label);
          }
        },
        child: Text(label),
      ),
    );
  }
}
