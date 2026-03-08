import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mis_medicamentos/db/local/medications_db.dart';
import 'package:mis_medicamentos/services/notifications_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';

enum _FrequencyType {
  every24Hours,
  every12Hours,
  every8Hours,
  every6Hours,
  everyNDays,
  custom,
}

enum _FormCategory {
  solid,
  injection,
  drops,
  sprayOrInhaler,
  patch,
  powder,
  suppository,
  other,
}

class NewMedicationForm extends StatefulWidget {
  const NewMedicationForm({
    super.key,
    this.closeOnSave = false,
    this.initialMedication,
  });

  final bool closeOnSave;
  final Map<String, Object?>? initialMedication;

  @override
  State<NewMedicationForm> createState() => _NewMedicationFormState();
}

class _NewMedicationFormState extends State<NewMedicationForm>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _doseController = TextEditingController();
  final _stockController = TextEditingController();
  final _intakeQuantityController = TextEditingController();
  final _durationDaysController = TextEditingController();
  final _everyNDaysController = TextEditingController();
  final _customFrequencyController = TextEditingController();
  final _instructionsController = TextEditingController();
  final _imagePicker = ImagePicker();

  final _allUnits = const [
    'mg (Miligramos)',
    'g (Gramos)',
    'ml (Mililitros)',
    'UI (Unidades internacionales)',
    'gotas',
    'puff(s)',
    'aplicación(es)',
    'parche(s)',
    'sobre(s)',
    'unidad(es)',
  ];
  final _forms = const [
    'Tableta',
    'Cápsula',
    'Jarabe',
    'Inyección',
    'Gotas',
    'Crema',
    'Polvo',
    'Spray',
    'Inhalador',
    'Parche',
    'Supositorio',
  ];
  final _routes = const [
    'Oral',
    'Inhalatoria',
    'Suspensión oral',
    'Nasal',
    'Oftálmica',
    'Ótica',
    'Intramuscular',
    'Intravenosa',
    'Subcutánea',
    'Tópica',
    'Sublingual',
    'Bucal (sin tragar)',
    'Masticable',
    'Efervescente',
    'Rectal',
    'Vaginal',
  ];

  String _selectedUnit = 'mg (Miligramos)';
  String _selectedForm = 'Tableta';
  String _selectedRoute = 'Oral';
  _FrequencyType _frequency = _FrequencyType.every24Hours;
  DateTime _firstDoseDate = DateTime.now();
  TimeOfDay _firstDoseTime = const TimeOfDay(hour: 8, minute: 0);
  List<TimeOfDay> _customTimes = [];
  bool _markAsFinished = false;
  bool _isIndefiniteTreatment = false;
  bool _isSaving = false;
  bool _wasKeyboardOpen = false;
  String? _photoPath;
  bool _photoDirty = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hydrateInitialValues();
    _syncCompatibility();
    _loadInitialPhotoPath();
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final keyboardOpen = View.of(context).viewInsets.bottom > 0;
    if (_wasKeyboardOpen && !keyboardOpen) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    _wasKeyboardOpen = keyboardOpen;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nameController.dispose();
    _doseController.dispose();
    _stockController.dispose();
    _intakeQuantityController.dispose();
    _durationDaysController.dispose();
    _everyNDaysController.dispose();
    _customFrequencyController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialMedication != null;

    return Theme(
      data: Theme.of(context).copyWith(
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: Color(0xFF2F80ED),
        ),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Nombre del medicamento'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameController,
                      decoration: _inputDecoration(
                        'Ej. Paracetamol',
                        icon: Icons.medication_outlined,
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? 'Ingresa un nombre'
                          : null,
                    ),
                    const SizedBox(height: 20),
                    _sectionTitle('Tipo y vía'),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedForm,
                            isExpanded: true,
                            decoration: _inputDecoration('Tipo'),
                            items: _forms
                                .map(
                                  (form) => DropdownMenuItem(
                                    value: form,
                                    child: Text(form),
                                  ),
                                )
                                .toList(),
                            selectedItemBuilder: (context) {
                              return _forms
                                  .map(
                                    (form) => Text(
                                      form,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )
                                  .toList();
                            },
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                _selectedForm = value;
                                _syncCompatibility();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            key: ValueKey(
                              'route_${_selectedForm}_$_selectedRoute',
                            ),
                            initialValue: _selectedRoute,
                            isExpanded: true,
                            decoration: _inputDecoration('Vía'),
                            items: _availableRoutes
                                .map(
                                  (route) => DropdownMenuItem(
                                    value: route,
                                    child: Text(route),
                                  ),
                                )
                                .toList(),
                            selectedItemBuilder: (context) {
                              return _availableRoutes
                                  .map(
                                    (route) => Text(
                                      route,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )
                                  .toList();
                            },
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _selectedRoute = value);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _sectionTitle(_doseSectionTitle),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _doseController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: _inputDecoration(_doseHint),
                            validator: (value) {
                              final parsed = double.tryParse(
                                (value ?? '').replaceAll(',', '.'),
                              );
                              return (parsed == null || parsed <= 0)
                                  ? 'Inválida'
                                  : null;
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey(
                              'unit_${_selectedForm}_$_selectedUnit',
                            ),
                            initialValue: _selectedUnit,
                            isExpanded: true,
                            decoration: _inputDecoration(_unitFieldLabel),
                            items: _availableUnits
                                .map(
                                  (unit) => DropdownMenuItem(
                                    value: unit,
                                    child: Text(unit),
                                  ),
                                )
                                .toList(),
                            selectedItemBuilder: (context) {
                              return _availableUnits
                                  .map(
                                    (unit) => Text(
                                      unit,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )
                                  .toList();
                            },
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _selectedUnit = value);
                            },
                          ),
                        ),
                      ],
                    ),
                    if (_requiresStockFields || _showsIntakeField) ...[
                      const SizedBox(height: 20),
                      _sectionTitle('Cantidad del medicamento'),
                      const SizedBox(height: 8),
                    ],
                    if (_requiresStockFields) ...[
                      TextFormField(
                        controller: _stockController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {}),
                        decoration: _inputDecoration(_stockTotalHint),
                        validator: (value) {
                          if (_isIndefiniteTreatment) return null;
                          final parsed = _parsePositiveNumber(value);
                          return (parsed == null || parsed <= 0)
                              ? 'Inválida'
                              : null;
                        },
                      ),
                      const SizedBox(height: 10),
                      _intakeField(),
                    ] else if (_showsIntakeField)
                      _intakeField(),
                    if (_requiresStockFields || _showsIntakeField)
                      const SizedBox(height: 20),
                    if (!_requiresStockFields && !_showsIntakeField)
                      const SizedBox(height: 20),
                    if (_requiresStockFields || _showsDurationDaysField) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F7FB),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFD9E2EE)),
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Tratamiento de por vida',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF1A2740),
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'No requiere duración ni cantidad total',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF5E6F87),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              activeThumbColor: Colors.white,
                              activeTrackColor: const Color(0xFF2F80ED),
                              value: _isIndefiniteTreatment,
                              onChanged: (value) {
                                setState(() {
                                  _isIndefiniteTreatment = value;
                                  if (value) {
                                    _stockController.clear();
                                    _durationDaysController.clear();
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    _sectionTitle('Frecuencia'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _frequencyButton(
                            label: 'Cada 24 horas',
                            selected: _frequency == _FrequencyType.every24Hours,
                            onTap: () => setState(
                              () => _frequency = _FrequencyType.every24Hours,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _frequencyButton(
                            label: 'Cada 12 horas',
                            selected: _frequency == _FrequencyType.every12Hours,
                            onTap: () => setState(
                              () => _frequency = _FrequencyType.every12Hours,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _frequencyButton(
                            label: 'Cada 8 horas',
                            selected: _frequency == _FrequencyType.every8Hours,
                            onTap: () => setState(
                              () => _frequency = _FrequencyType.every8Hours,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _frequencyButton(
                            label: 'Cada 6 horas',
                            selected: _frequency == _FrequencyType.every6Hours,
                            onTap: () => setState(
                              () => _frequency = _FrequencyType.every6Hours,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _frequencyButton(
                            label: 'Cada N días',
                            selected: _frequency == _FrequencyType.everyNDays,
                            onTap: () => setState(
                              () => _frequency = _FrequencyType.everyNDays,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _frequencyButton(
                            label: 'Horas personalizadas',
                            selected: _frequency == _FrequencyType.custom,
                            onTap: () => setState(
                              () => _frequency = _FrequencyType.custom,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_frequency == _FrequencyType.everyNDays) ...[
                      TextFormField(
                        controller: _everyNDaysController,
                        keyboardType: TextInputType.number,
                        decoration: _inputDecoration(
                          'Cada cuántos días (mínimo 2)',
                          icon: Icons.event_repeat_outlined,
                        ),
                        validator: (value) {
                          if (_frequency != _FrequencyType.everyNDays) {
                            return null;
                          }
                          final parsed = int.tryParse((value ?? '').trim());
                          if (parsed == null || parsed < 2) {
                            return 'Ingresa un número válido (>= 2)';
                          }
                          return null;
                        },
                      ),
                    ],
                    if (_frequency == _FrequencyType.custom) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF6FAFF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFD9E2EE)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _customTimes.isEmpty
                                  ? const [
                                      Text(
                                        'Aun no hay horas personalizadas.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF5E6F87),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ]
                                  : List.generate(_customTimes.length, (index) {
                                      final time = _customTimes[index];
                                      return InputChip(
                                        label: Text(_formatTime(time)),
                                        onDeleted: () =>
                                            _removeCustomTimeAt(index),
                                        deleteIcon: const Icon(
                                          Icons.close,
                                          size: 16,
                                        ),
                                      );
                                    }),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _pickCustomTime,
                              icon: const Icon(Icons.add_alarm),
                              label: const Text('Agregar hora'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _customFrequencyController,
                        decoration: _inputDecoration(
                          'Nota de frecuencia (opcional)',
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _sectionTitle('Primera dosis'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _pickFirstDoseDate,
                            borderRadius: BorderRadius.circular(12),
                            child: InputDecorator(
                              decoration: _inputDecoration('').copyWith(
                                suffixIcon: const Icon(
                                  Icons.calendar_today_outlined,
                                  color: Color(0xFF8BA0BC),
                                ),
                              ),
                              child: Text(
                                _formatDate(_firstDoseDate),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: _pickTime,
                            borderRadius: BorderRadius.circular(12),
                            child: InputDecorator(
                              decoration: _inputDecoration('').copyWith(
                                suffixIcon: const Icon(
                                  Icons.access_time,
                                  color: Color(0xFF8BA0BC),
                                ),
                              ),
                              child: Text(
                                _formatTimeWithMeridiem(_firstDoseTime),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_showsDurationDaysField && !_isIndefiniteTreatment) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _durationDaysController,
                        keyboardType: TextInputType.number,
                        decoration: _inputDecoration(
                          'Días de tratamiento (ej. 7)',
                          icon: Icons.timelapse_outlined,
                        ),
                        validator: (value) {
                          if (!_showsDurationDaysField) return null;
                          final parsed = int.tryParse((value ?? '').trim());
                          return (parsed == null || parsed <= 0)
                              ? 'Ingresa días válidos'
                              : null;
                        },
                      ),
                    ],
                    if (_showsDurationDaysField && _isIndefiniteTreatment) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF6FAFF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFD9E2EE)),
                        ),
                        child: const Text(
                          'Duración no definida por tratarse de un tratamiento de por vida.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF5E6F87),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _sectionTitle('Instrucciones (opcional)'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _instructionsController,
                      minLines: 3,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: _inputDecoration(
                        'Ej. Tomar después de comer y con agua.',
                        icon: Icons.notes_outlined,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _sectionTitle('Foto del medicamento (opcional)'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickMedicationPhoto,
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Seleccionar foto'),
                          ),
                        ),
                        if (_photoPath != null) ...[
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: _removeMedicationPhoto,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Quitar'),
                          ),
                        ],
                      ],
                    ),
                    if (_photoPath != null) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(_photoPath!),
                          height: 140,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              height: 60,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF6FAFF),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFD9E2EE),
                                ),
                              ),
                              child: const Text(
                                'No se pudo cargar la foto seleccionada.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF5E6F87),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (isEditing) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F7FB),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFD9E2EE)),
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Estado del medicamento',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF1A2740),
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Marcar como finalizado',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF5E6F87),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              activeThumbColor: Colors.white,
                              activeTrackColor: const Color(0xFF2F80ED),
                              value: _markAsFinished,
                              onChanged: (value) =>
                                  setState(() => _markAsFinished = value),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE5ECF4))),
              ),
              child: isEditing
                  ? Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isSaving ? null : _deleteMedication,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFD93B3B),
                              side: const BorderSide(color: Color(0xFFF3B3B3)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Eliminar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: _isSaving ? null : _saveMedication,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF2F80ED),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            child: Text(
                              _isSaving ? 'Guardando...' : 'Guardar cambios',
                            ),
                          ),
                        ),
                      ],
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isSaving ? null : _saveMedication,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2F80ED),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: Text(
                          _isSaving ? 'Guardando...' : 'Guardar medicamento',
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _hydrateInitialValues() {
    final medication = widget.initialMedication;
    if (medication == null) return;

    final name = medication['name']?.toString();
    if (name != null) _nameController.text = name;

    final dose = (medication['dose_amount'] as num?)?.toDouble();
    if (dose != null) {
      _doseController.text = dose == dose.roundToDouble()
          ? dose.toInt().toString()
          : dose.toString();
    }

    final stockInitial = (medication['stock_initial'] as num?)?.toInt();
    final stockCurrent = (medication['stock_current'] as num?)?.toDouble();
    if (stockInitial != null) {
      _stockController.text = _formatNumber(stockInitial.toDouble());
    } else if (stockCurrent != null) {
      _stockController.text = _formatNumber(stockCurrent);
    }

    final intakeQuantity = (medication['intake_quantity'] as num?)?.toDouble();
    if (intakeQuantity != null) {
      _intakeQuantityController.text = _formatNumber(intakeQuantity);
    }

    final instructions = medication['instructions']?.toString();
    if (instructions != null) _instructionsController.text = instructions;

    final unit = medication['dose_unit']?.toString();
    if (unit != null && _allUnits.contains(unit)) _selectedUnit = unit;

    final form = medication['form']?.toString();
    if (form != null && _forms.contains(form)) _selectedForm = form;

    final route = medication['route']?.toString();
    if (route != null && _routes.contains(route)) _selectedRoute = route;
    _syncCompatibility();

    final frequencyRule = medication['frequency_rule']?.toString().trim() ?? '';
    if (frequencyRule == 'daily' || frequencyRule == 'every_24_hours') {
      _frequency = _FrequencyType.every24Hours;
    } else if (frequencyRule == 'every_12_hours') {
      _frequency = _FrequencyType.every12Hours;
    } else if (frequencyRule == 'every_8_hours') {
      _frequency = _FrequencyType.every8Hours;
    } else if (frequencyRule == 'every_6_hours') {
      _frequency = _FrequencyType.every6Hours;
    } else if (RegExp(r'^every_(\d+)_days$').hasMatch(frequencyRule)) {
      final match = RegExp(r'^every_(\d+)_days$').firstMatch(frequencyRule);
      final everyNDays = int.tryParse(match?.group(1) ?? '');
      if (everyNDays != null && everyNDays >= 2) {
        _frequency = _FrequencyType.everyNDays;
        _everyNDaysController.text = everyNDays.toString();
      } else {
        _frequency = _FrequencyType.every24Hours;
      }
    } else if (frequencyRule.startsWith('custom_times')) {
      _frequency = _FrequencyType.custom;
      final separatorIndex = frequencyRule.indexOf(':');
      if (separatorIndex > 0 && separatorIndex < frequencyRule.length - 1) {
        _customFrequencyController.text = frequencyRule
            .substring(separatorIndex + 1)
            .trim();
      }
    } else if (frequencyRule.isNotEmpty) {
      _frequency = _FrequencyType.custom;
      _customFrequencyController.text = frequencyRule;
    }

    _markAsFinished =
        (medication['status']?.toString() ?? 'active') != 'active';
    _isIndefiniteTreatment = (medication['indefinite'] as num?)?.toInt() == 1;

    final firstDoseAtRaw = medication['first_dose_at']?.toString().trim();
    final firstDoseAt = (firstDoseAtRaw == null || firstDoseAtRaw.isEmpty)
        ? null
        : DateTime.tryParse(firstDoseAtRaw);
    if (firstDoseAt != null) {
      _firstDoseDate = DateTime(
        firstDoseAt.year,
        firstDoseAt.month,
        firstDoseAt.day,
      );
      _firstDoseTime = TimeOfDay(
        hour: firstDoseAt.hour,
        minute: firstDoseAt.minute,
      );
    }

    final startDateRaw = medication['start_date']?.toString().trim();
    final startDate = (startDateRaw == null || startDateRaw.isEmpty)
        ? null
        : DateTime.tryParse(startDateRaw);
    if (startDate != null && firstDoseAt == null) {
      _firstDoseDate = DateTime(startDate.year, startDate.month, startDate.day);
    }
    final endDateRaw = medication['end_date']?.toString().trim();
    final endDate = (endDateRaw == null || endDateRaw.isEmpty)
        ? null
        : DateTime.tryParse(endDateRaw);
    if (startDate != null && endDate != null) {
      final startOnly = DateTime(
        startDate.year,
        startDate.month,
        startDate.day,
      );
      final endOnly = DateTime(endDate.year, endDate.month, endDate.day);
      final durationDays = endOnly.difference(startOnly).inDays + 1;
      if (durationDays > 0) {
        _durationDaysController.text = durationDays.toString();
      }
    }

    _loadInitialScheduleTime();
  }

  Future<void> _loadInitialScheduleTime() async {
    final medicationId = (widget.initialMedication?['id'] as num?)?.toInt();
    if (medicationId == null) return;

    final schedules = await AppDatabase.instance.getMedicationSchedules(
      medicationId,
    );
    if (!mounted || schedules.isEmpty) return;

    final loadedTimes = <TimeOfDay>[];
    for (final row in schedules) {
      final raw = row['time_of_day']?.toString() ?? '';
      final parts = raw.split(':');
      if (parts.length != 2) continue;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) continue;
      loadedTimes.add(TimeOfDay(hour: hour, minute: minute));
    }
    if (loadedTimes.isEmpty) return;
    loadedTimes.sort((a, b) => _timeToMinutes(a).compareTo(_timeToMinutes(b)));

    final firstDoseAtRaw = widget.initialMedication?['first_dose_at']
        ?.toString()
        .trim();
    final hasStoredFirstDoseAt =
        firstDoseAtRaw != null && DateTime.tryParse(firstDoseAtRaw) != null;

    setState(() {
      if (!hasStoredFirstDoseAt) {
        _firstDoseTime = loadedTimes.first;
      }
      if (_frequency == _FrequencyType.custom) {
        _customTimes = loadedTimes;
      }
    });
  }

  Future<void> _loadInitialPhotoPath() async {
    final medicationId = (widget.initialMedication?['id'] as num?)?.toInt();
    if (medicationId == null) return;
    final existingPath = await AppDatabase.instance
        .getMedicationImageAttachmentPath(medicationId);
    if (!mounted || existingPath == null || existingPath.isEmpty) return;
    setState(() {
      _photoPath = existingPath;
    });
  }

  double? _parsePositiveNumber(String? raw) {
    final normalized = (raw ?? '').trim().replaceAll(',', '.');
    final parsed = double.tryParse(normalized);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  List<String> get _availableUnits {
    final lower = _selectedForm.toLowerCase();
    if (lower.contains('jarabe')) return const ['ml (Mililitros)'];
    if (lower.contains('gota')) return const ['gotas', 'ml (Mililitros)'];
    if (lower.contains('crema')) {
      return const ['g (Gramos)', 'ml (Mililitros)', 'aplicación(es)'];
    }
    if (lower.contains('spray') || lower.contains('inhalador')) {
      return const [
        'puff(s)',
        'ml (Mililitros)',
        'UI (Unidades internacionales)',
      ];
    }
    if (lower.contains('parche')) {
      return const [
        'parche(s)',
        'mg (Miligramos)',
        'UI (Unidades internacionales)',
      ];
    }
    if (lower.contains('polvo')) {
      return const ['g (Gramos)', 'mg (Miligramos)', 'sobre(s)'];
    }
    if (lower.contains('inyec')) {
      return const [
        'ml (Mililitros)',
        'mg (Miligramos)',
        'UI (Unidades internacionales)',
      ];
    }
    if (lower.contains('tableta') ||
        lower.contains('masticable') ||
        lower.contains('cápsula') ||
        lower.contains('capsula') ||
        lower.contains('supositorio')) {
      return const [
        'mg (Miligramos)',
        'g (Gramos)',
        'UI (Unidades internacionales)',
        'unidad(es)',
      ];
    }
    return _allUnits;
  }

  List<String> get _availableRoutes {
    final lower = _selectedForm.toLowerCase();
    if (lower.contains('jarabe')) return const ['Oral'];
    if (lower.contains('tableta')) {
      return const [
        'Oral',
        'Sublingual',
        'Bucal (sin tragar)',
        'Masticable',
        'Efervescente',
        'Vaginal',
      ];
    }
    if (lower.contains('cápsula') || lower.contains('capsula')) {
      return const ['Oral', 'Rectal', 'Vaginal'];
    }
    if (lower.contains('polvo')) {
      return const ['Oral', 'Suspensión oral', 'Inhalatoria', 'Tópica'];
    }
    if (lower.contains('crema')) {
      return const ['Tópica', 'Rectal', 'Vaginal'];
    }
    if (lower.contains('parche')) return const ['Tópica'];
    if (lower.contains('inhalador')) return const ['Inhalatoria'];
    if (lower.contains('spray')) {
      return const ['Nasal', 'Tópica', 'Inhalatoria', 'Oral'];
    }
    if (lower.contains('gota')) {
      return const ['Oftálmica', 'Ótica', 'Nasal', 'Oral'];
    }
    if (lower.contains('supositorio')) return const ['Rectal', 'Vaginal'];
    if (lower.contains('inyec')) {
      return const [
        'Intramuscular',
        'Intravenosa',
        'Subcutánea',
        'Intradérmica',
      ];
    }
    return _routes;
  }

  void _syncCompatibility() {
    if (!_availableUnits.contains(_selectedUnit)) {
      _selectedUnit = _availableUnits.first;
    }
    if (!_availableRoutes.contains(_selectedRoute)) {
      _selectedRoute = _availableRoutes.first;
    }
  }

  bool get _isSyrupOrCreamForm {
    final lower = _selectedForm.toLowerCase();
    return lower.contains('jarabe') || lower.contains('crema');
  }

  bool get _requiresStockFields {
    final lower = _selectedForm.toLowerCase();
    if (_isSyrupOrCreamForm) return false;
    if (lower.contains('gota')) return false;
    if (lower.contains('spray') || lower.contains('inhalador')) return false;
    return true;
  }

  bool get _showsIntakeField => !_isSyrupOrCreamForm;
  bool get _showsDurationDaysField {
    final lower = _selectedForm.toLowerCase();
    return lower.contains('gota') ||
        lower.contains('jarabe') ||
        lower.contains('crema') ||
        lower.contains('spray') ||
        lower.contains('inhalador');
  }

  String get _doseSectionTitle {
    switch (_formCategory) {
      case _FormCategory.sprayOrInhaler:
        return 'Potencia por aplicación';
      case _FormCategory.drops:
        return 'Concentración';
      case _FormCategory.patch:
        return 'Potencia del parche';
      case _FormCategory.powder:
        return 'Dosis por sobre';
      case _FormCategory.injection:
        return 'Dosis por aplicación';
      default:
        return 'Dosis y Unidad';
    }
  }

  String get _doseHint {
    switch (_formCategory) {
      case _FormCategory.sprayOrInhaler:
        return 'Ej. 100';
      case _FormCategory.drops:
        return 'Ej. 0.5';
      case _FormCategory.patch:
        return 'Ej. 21';
      case _FormCategory.powder:
        return 'Ej. 500';
      case _FormCategory.injection:
        return 'Ej. 1';
      default:
        return 'Ej. 500';
    }
  }

  String get _unitFieldLabel {
    return 'Unidad';
  }

  String get _stockTotalHint {
    switch (_formCategory) {
      case _FormCategory.suppository:
        return 'Supositorios totales (ej. 10)';
      case _FormCategory.patch:
        return 'Parches totales (ej. 8)';
      case _FormCategory.powder:
        return 'Sobres totales (ej. 12)';
      case _FormCategory.solid:
        return 'Unidades totales (ej. 30)';
      case _FormCategory.injection:
        return 'Aplicaciones totales (ej. 10)';
      default:
        return 'Cantidad total (ej. 30)';
    }
  }

  _FormCategory get _formCategory {
    final lower = _selectedForm.toLowerCase();
    if (lower.contains('supositorio')) return _FormCategory.suppository;
    if (lower.contains('parche')) return _FormCategory.patch;
    if (lower.contains('polvo')) return _FormCategory.powder;
    if (lower.contains('tableta') ||
        lower.contains('cápsula') ||
        lower.contains('capsula')) {
      return _FormCategory.solid;
    }
    if (lower.contains('inyec')) return _FormCategory.injection;
    if (lower.contains('gota')) return _FormCategory.drops;
    if (lower.contains('spray') || lower.contains('inhalador')) {
      return _FormCategory.sprayOrInhaler;
    }
    return _FormCategory.other;
  }

  Widget _intakeField() {
    final hint = switch (_formCategory) {
      _FormCategory.drops => 'Gotas por toma (ej. 8)',
      _FormCategory.sprayOrInhaler => 'Puff(s) por toma (ej. 2)',
      _FormCategory.suppository => 'Supositorios por dosis (ej. 1)',
      _FormCategory.patch => 'Parches por aplicación (ej. 1)',
      _FormCategory.powder => 'Sobres por toma (ej. 1)',
      _FormCategory.solid => 'Unidades por toma (ej. 1)',
      _FormCategory.injection => 'Aplicaciones por toma (ej. 1)',
      _FormCategory.other => 'Cantidad por toma',
    };
    return TextFormField(
      controller: _intakeQuantityController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: _inputDecoration(hint),
      validator: (value) {
        final parsed = _parsePositiveNumber(value);
        return (parsed == null || parsed <= 0) ? 'Inválida' : null;
      },
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
      ),
    );
  }

  Widget _frequencyButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final selectedColor = const Color(0xFF2F80ED);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF3FF) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? selectedColor : const Color(0xFFD9E2EE),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 8.5,
            fontWeight: FontWeight.w700,
            color: selected ? selectedColor : const Color(0xFF4A5970),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, {IconData? icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF7D8CA3)),
      filled: true,
      fillColor: Colors.white,
      prefixIcon: icon == null
          ? null
          : Icon(icon, color: const Color(0xFF8BA0BC)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD9E2EE)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD9E2EE)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2F80ED), width: 1.4),
      ),
    );
  }

  Future<void> _pickTime() async {
    final selected = await _showAmPmTimePicker(initialTime: _firstDoseTime);
    if (selected == null) return;
    setState(() => _firstDoseTime = selected);
  }

  Future<void> _pickFirstDoseDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      locale: const Locale('es', 'ES'),
      initialDate: _firstDoseDate,
      firstDate: DateTime(now.year - 10, 1, 1),
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (selected == null) return;
    setState(() {
      _firstDoseDate = DateTime(selected.year, selected.month, selected.day);
    });
  }

  Future<void> _pickCustomTime() async {
    final selected = await _showAmPmTimePicker(
      initialTime: _customTimes.isEmpty ? _firstDoseTime : _customTimes.last,
    );
    if (selected == null) return;
    setState(() {
      final exists = _customTimes.any(
        (time) => time.hour == selected.hour && time.minute == selected.minute,
      );
      if (!exists) {
        _customTimes.add(selected);
        _customTimes.sort(
          (a, b) => _timeToMinutes(a).compareTo(_timeToMinutes(b)),
        );
      }
    });
  }

  Future<TimeOfDay?> _showAmPmTimePicker({required TimeOfDay initialTime}) {
    return showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        final media = MediaQuery.of(context);
        return Localizations.override(
          context: context,
          locale: const Locale('en', 'US'),
          child: MediaQuery(
            data: media.copyWith(alwaysUse24HourFormat: false),
            child: child,
          ),
        );
      },
    );
  }

  void _removeCustomTimeAt(int index) {
    setState(() {
      if (index >= 0 && index < _customTimes.length) {
        _customTimes.removeAt(index);
      }
    });
  }

  Future<void> _saveMedication() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final editingId = (widget.initialMedication?['id'] as num?)?.toInt();
      final medicationName = _nameController.text.trim();
      final dose = double.parse(
        _doseController.text.trim().replaceAll(',', '.'),
      );
      final intakeQuantity = _showsIntakeField
          ? _parsePositiveNumber(_intakeQuantityController.text)!
          : 1.0;
      final stock = _requiresStockFields && !_isIndefiniteTreatment
          ? _parsePositiveNumber(_stockController.text)
          : null;
      final existingCurrent =
          (widget.initialMedication?['stock_current'] as num?)?.toDouble();
      final stockCurrent = stock == null
          ? null
          : (editingId != null
                ? (existingCurrent ?? stock).clamp(0.0, stock)
                : stock);
      final durationDays = _showsDurationDaysField && !_isIndefiniteTreatment
          ? int.tryParse(_durationDaysController.text.trim())
          : null;
      final endDate = durationDays == null
          ? null
          : _firstDoseDate.add(Duration(days: durationDays - 1));

      final medication = <String, Object?>{
        'name': _nameController.text.trim(),
        'dose_amount': dose,
        'dose_unit': _selectedUnit,
        'form': _selectedForm,
        'route': _selectedRoute,
        'instructions': _instructionsController.text.trim().isEmpty
            ? null
            : _instructionsController.text.trim(),
        'frequency_rule': _frequencyRuleValue(),
        'days_of_week': _frequency == _FrequencyType.every24Hours
            ? '1,2,3,4,5,6,7'
            : null,
        'stock_current': stockCurrent,
        'stock_initial': stock,
        'intake_quantity': intakeQuantity,
        'reminder_minutes_before': 15,
        'reminder_sound': 1,
        'reminder_vibration': 1,
        'start_date': _toIsoDate(_firstDoseDate),
        'end_date': endDate == null ? null : _toIsoDate(endDate),
        'indefinite': _isIndefiniteTreatment ? 1 : 0,
        'first_dose_at': _firstDoseAtIso(),
        'status': _markAsFinished ? 'finished' : 'active',
      };

      if (editingId != null) {
        await AppDatabase.instance.updateMedication(
          editingId,
          medication,
          times: _scheduleTimes(),
        );
        if (_photoDirty) {
          await _persistMedicationPhoto(editingId);
        }
      } else {
        final firstDoseAt = DateTime(
          _firstDoseDate.year,
          _firstDoseDate.month,
          _firstDoseDate.day,
          _firstDoseTime.hour,
          _firstDoseTime.minute,
        );
        final createdId = await AppDatabase.instance.createMedication({
          ...medication,
          'active_ingredient': null,
          'diagnosis': null,
          'prescribed_by': null,
          'stock_minimum': null,
          'interactions_notes': null,
          'side_effects_notes': null,
          'notes': null,
        }, times: _scheduleTimes());
        await _persistMedicationPhoto(createdId);
        if (_markAsFinished) {
          await NotificationsService.instance.showMedicationFinished(
            medicationName: medicationName,
            medicationForm: _selectedForm,
          );
        } else if (await NotificationsService.instance
            .isDoseRemindersEnabled()) {
          await NotificationsService.instance.showMedicationScheduled(
            medicationName: medicationName,
            medicationForm: _selectedForm,
            firstDoseAt: firstDoseAt,
          );
        }
      }

      if (editingId != null && _markAsFinished) {
        await NotificationsService.instance.showMedicationFinished(
          medicationName: medicationName,
          medicationForm: _selectedForm,
        );
      } else if (editingId != null) {
        await NotificationsService.instance.showMedicationUpdated(
          medicationName: medicationName,
          medicationForm: _selectedForm,
        );
      }
      await NotificationsService.instance
          .syncTodayDoseNotificationsFromDatabase();

      if (!mounted) return;
      if (widget.closeOnSave) {
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Medicamento guardado')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteMedication() async {
    final editingId = (widget.initialMedication?['id'] as num?)?.toInt();
    if (editingId == null) return;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Eliminar medicamento',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: const Text(
            'Esta acción eliminará el medicamento y su programación. ¿Deseas continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: Colors.black),
              ),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFD93B3B)),
              ),
              child: const Text(
                'Eliminar',
                style: TextStyle(color: Color(0xFFD93B3B)),
              ),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    setState(() => _isSaving = true);
    try {
      final initialName = widget.initialMedication?['name']?.toString().trim();
      final medicationName = _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : (initialName == null || initialName.isEmpty)
          ? 'Medicamento'
          : initialName;
      await AppDatabase.instance.deleteMedication(editingId);
      await NotificationsService.instance.showMedicationDeleted(
        medicationName: medicationName,
        medicationForm: _selectedForm,
      );
      await NotificationsService.instance
          .syncTodayDoseNotificationsFromDatabase();
      if (!mounted) return;
      if (widget.closeOnSave) {
        Navigator.of(context).pop('deleted');
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Medicamento eliminado')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickMedicationPhoto() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;

    final copiedPath = await _copyImageToAppStorage(picked.path);
    if (!mounted) return;
    setState(() {
      _photoPath = copiedPath;
      _photoDirty = true;
    });
  }

  void _removeMedicationPhoto() {
    setState(() {
      _photoPath = null;
      _photoDirty = true;
    });
  }

  Future<String> _copyImageToAppStorage(String sourcePath) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(docsDir.path, 'medication_photos'));
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }

    final extension = p.extension(sourcePath).toLowerCase();
    final safeExt = extension.isEmpty ? '.jpg' : extension;
    final fileName = 'med_${DateTime.now().millisecondsSinceEpoch}$safeExt';
    final targetPath = p.join(photosDir.path, fileName);
    await File(sourcePath).copy(targetPath);
    return targetPath;
  }

  Future<void> _persistMedicationPhoto(int medicationId) async {
    final previousPath = await AppDatabase.instance
        .getMedicationImageAttachmentPath(medicationId);
    await AppDatabase.instance.replaceMedicationImageAttachment(
      medicationId,
      _photoPath,
    );
    if (previousPath != null &&
        previousPath.isNotEmpty &&
        previousPath != _photoPath) {
      await _deleteManagedPhoto(previousPath);
    }
  }

  Future<void> _deleteManagedPhoto(String filePath) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final managedPrefix = p.join(docsDir.path, 'medication_photos');
      if (!p.isWithin(managedPrefix, filePath) &&
          !p.equals(managedPrefix, p.dirname(filePath))) {
        return;
      }
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Keep save flow resilient even if local file cleanup fails.
    }
  }

  String _frequencyRuleValue() {
    switch (_frequency) {
      case _FrequencyType.every24Hours:
        return 'every_24_hours';
      case _FrequencyType.every12Hours:
        return 'every_12_hours';
      case _FrequencyType.every8Hours:
        return 'every_8_hours';
      case _FrequencyType.every6Hours:
        return 'every_6_hours';
      case _FrequencyType.everyNDays:
        final everyNDays = int.tryParse(_everyNDaysController.text.trim()) ?? 2;
        return 'every_${everyNDays < 2 ? 2 : everyNDays}_days';
      case _FrequencyType.custom:
        final note = _customFrequencyController.text.trim();
        return note.isEmpty ? 'custom_times' : 'custom_times:$note';
    }
  }

  List<String> _scheduleTimes() {
    final minutes = _firstDoseTime.hour * 60 + _firstDoseTime.minute;
    switch (_frequency) {
      case _FrequencyType.every24Hours:
        return [_toHourMinute(minutes)];
      case _FrequencyType.every12Hours:
        return List.generate(
          2,
          (index) => _toHourMinute((minutes + (index * 720)) % 1440),
        );
      case _FrequencyType.every8Hours:
        return List.generate(
          3,
          (index) => _toHourMinute((minutes + (index * 480)) % 1440),
        );
      case _FrequencyType.every6Hours:
        return List.generate(
          4,
          (index) => _toHourMinute((minutes + (index * 360)) % 1440),
        );
      case _FrequencyType.everyNDays:
        return [_toHourMinute(minutes)];
      case _FrequencyType.custom:
        if (_customTimes.isEmpty) return [_toHourMinute(minutes)];
        return _customTimes.map(_toHourMinuteFromTimeOfDay).toList();
    }
  }

  String _toHourMinuteFromTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  int _timeToMinutes(TimeOfDay time) => (time.hour * 60) + time.minute;

  String _toHourMinute(int totalMinutes) {
    final hour = (totalMinutes ~/ 60).toString().padLeft(2, '0');
    final minute = (totalMinutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatTimeWithMeridiem(TimeOfDay time) {
    final isPm = time.hour >= 12;
    final hour12 = (time.hour % 12 == 0) ? 12 : (time.hour % 12);
    final minute = time.minute.toString().padLeft(2, '0');
    final suffix = isPm ? 'PM' : 'AM';
    return '$hour12:$minute $suffix';
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString().padLeft(4, '0');
    return '$day/$month/$year';
  }

  String _toIsoDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString().padLeft(4, '0');
    return '$year-$month-$day';
  }

  String _firstDoseAtIso() {
    final value = DateTime(
      _firstDoseDate.year,
      _firstDoseDate.month,
      _firstDoseDate.day,
      _firstDoseTime.hour,
      _firstDoseTime.minute,
    );
    return value.toIso8601String();
  }
}
