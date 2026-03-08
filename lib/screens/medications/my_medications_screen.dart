import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:mis_medicamentos/db/local/medications_db.dart';
import 'package:mis_medicamentos/screens/new_medication/new_medication_form.dart';

class MyMedicationsScreen extends StatefulWidget {
  const MyMedicationsScreen({super.key});

  @override
  State<MyMedicationsScreen> createState() => _MyMedicationsScreenState();
}

class _MyMedicationsScreenState extends State<MyMedicationsScreen>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  final _pageController = PageController();
  int _tabIndex = 0;
  bool _loading = true;
  bool _wasKeyboardOpen = false;
  List<Map<String, Object?>> _medications = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppDatabase.instance.medicationsChangeToken.addListener(
      _onMedicationsChanged,
    );
    _loadMedications();
  }

  @override
  void dispose() {
    AppDatabase.instance.medicationsChangeToken.removeListener(
      _onMedicationsChanged,
    );
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onMedicationsChanged() {
    if (!mounted) return;
    _loadMedications();
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

  Future<void> _loadMedications() async {
    setState(() {
      _loading = true;
    });
    final meds = await AppDatabase.instance.getMedications();
    final medicationIds = meds
        .map((m) => m['id'])
        .whereType<int>()
        .toList(growable: false);
    final photoPaths = await AppDatabase.instance
        .getMedicationImageAttachmentPaths(medicationIds);
    final medsWithPhoto = meds
        .map((medication) {
          final id = medication['id'] as int?;
          final path = id == null ? null : photoPaths[id];
          return {...medication, '_image_path': path};
        })
        .toList(growable: false);
    if (!mounted) return;
    setState(() {
      _medications = medsWithPhoto;
      _loading = false;
    });
  }

  Future<void> _openNewMedicationModal() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.99,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 14,
            bottom: MediaQuery.of(context).viewInsets.bottom + 18,
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nuevo medicamento',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 12),
              Expanded(child: NewMedicationForm(closeOnSave: true)),
            ],
          ),
        );
      },
    );

    if (saved == true) {
      await _loadMedications();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: Colors.white,
            title: const Text(
              'Medicamento guardado',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            content: const Text('Medicamento guardado correctamente'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text(
                  'Aceptar',
                  style: TextStyle(color: Colors.black),
                ),
              ),
            ],
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredMeds();
    final active = filtered.where((m) => !_isFinished(m)).toList();
    final finished = filtered.where(_isFinished).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        toolbarHeight: 0,
        elevation: 0,
        backgroundColor: Colors.white,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.white,
        shadowColor: Colors.transparent,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.white,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    cursorColor: const Color(0xFF2F80ED),
                    decoration: InputDecoration(
                      hintText: 'Buscar medicamento...',
                      hintStyle: const TextStyle(
                        color: Color.fromARGB(255, 112, 130, 152),
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Color.fromARGB(255, 112, 130, 152),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFEAF1F9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _tabButton('Activos', _tabIndex == 0, () {
                          _selectTab(0);
                        }),
                      ),
                      Expanded(
                        child: _tabButton('Finalizados', _tabIndex == 1, () {
                          _selectTab(1);
                        }),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  if (_tabIndex == index) return;
                  setState(() => _tabIndex = index);
                },
                children: [
                  _medicationsListPage(
                    medications: active,
                    emptyText: 'No hay medicamentos activos.',
                  ),
                  _medicationsListPage(
                    medications: finished,
                    emptyText: 'No hay medicamentos finalizados.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openNewMedicationModal,
        backgroundColor: const Color(0xFF2F80ED),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }

  List<Map<String, Object?>> _filteredMeds() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _medications;
    return _medications.where((m) {
      final name = (m['name']?.toString() ?? '').toLowerCase();
      final form = (m['form']?.toString() ?? '').toLowerCase();
      return name.contains(query) || form.contains(query);
    }).toList();
  }

  void _selectTab(int index) {
    if (_tabIndex != index) {
      setState(() => _tabIndex = index);
    }
    if (!_pageController.hasClients) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _medicationsListPage({
    required List<Map<String, Object?>> medications,
    required String emptyText,
  }) {
    return RefreshIndicator(
      color: const Color(0xFF2F80ED),
      onRefresh: _loadMedications,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 74),
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (medications.isEmpty)
            _emptyCard(emptyText)
          else
            ...medications.map((m) => _medCard(m)),
        ],
      ),
    );
  }

  Widget _tabButton(String text, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              text,
              style: TextStyle(
                color: selected
                    ? const Color(0xFF2F80ED)
                    : const Color(0xFF8A9AAF),
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
          Container(
            height: 2,
            color: selected ? const Color(0xFF2F80ED) : Colors.transparent,
          ),
        ],
      ),
    );
  }

  Widget _medCard(Map<String, Object?> medication) {
    final name = medication['name']?.toString() ?? 'Medicamento';
    final dose = (medication['dose_amount'] as num?)?.toDouble() ?? 0;
    final unit = _shortUnit(medication['dose_unit']?.toString() ?? '');
    final form = medication['form']?.toString() ?? 'Dosis';
    final isIndefinite = (medication['indefinite'] as num?)?.toInt() == 1;
    final hideInventory = _hideInventoryForForm(form) || isIndefinite;
    final frequency = _frequencyLabel(
      medication['frequency_rule']?.toString() ?? '',
    );
    final isFinished = _isFinished(medication);
    final stockCurrent = (medication['stock_current'] as num?)?.toDouble();
    final stockInitial = (medication['stock_initial'] as num?)?.toDouble();
    final lowStock =
        stockCurrent != null &&
        stockCurrent > 0 &&
        stockCurrent <= 5 &&
        stockInitial != null &&
        stockInitial > 5;
    final imagePath = medication['_image_path']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5ECF4)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFDDE7F4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _medicationVisual(form: form, imagePath: imagePath),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${_formatDose(dose)}$unit • ${_pluralize(form)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF3A4E69),
                      ),
                    ),
                  ],
                ),
              ),
              _statusBadge(isFinished: isFinished, lowStock: lowStock),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFE7EDF6)),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.access_time, size: 20, color: Color(0xFF2F80ED)),
              const SizedBox(width: 6),
              Text(
                frequency,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!hideInventory) ...[
                const SizedBox(width: 18),
                Icon(
                  lowStock
                      ? Icons.warning_amber_rounded
                      : Icons.inventory_2_outlined,
                  size: 20,
                  color: lowStock
                      ? const Color(0xFFF07A2C)
                      : const Color(0xFF2F80ED),
                ),
                const SizedBox(width: 6),
                Text(
                  stockCurrent == null
                      ? 'Sin stock'
                      : '${_formatDose(stockCurrent)} restantes',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: lowStock
                        ? const Color(0xFFF07A2C)
                        : const Color(0xFF1A2740),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2F80ED),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => _openMedicationDetails(medication),
                    child: const Text('Ver Detalles'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 40,
                height: 36,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEAF1F9),
                    foregroundColor: const Color(0xFF2F80ED),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: () => _openEditMedicationModal(medication),
                  child: const Icon(Icons.edit, size: 16),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openEditMedicationModal(Map<String, Object?> medication) async {
    final result = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.99,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 14,
            bottom: MediaQuery.of(context).viewInsets.bottom + 18,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Editar medicamento',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: NewMedicationForm(
                  closeOnSave: true,
                  initialMedication: medication,
                ),
              ),
            ],
          ),
        );
      },
    );

    if (result == true || result == 'deleted') {
      await _loadMedications();
      if (!mounted) return;
      final wasDeleted = result == 'deleted';
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: Colors.white,
            title: Text(
              wasDeleted ? 'Medicamento eliminado' : 'Medicamento actualizado',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            content: Text(
              wasDeleted
                  ? 'El medicamento fue eliminado correctamente'
                  : 'Lista de medicamentos actualizada',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text(
                  'Aceptar',
                  style: TextStyle(color: Colors.black),
                ),
              ),
            ],
          );
        },
      );
    }
  }

  Future<void> _openMedicationDetails(Map<String, Object?> medication) async {
    final medicationId = medication['id'] as int?;
    final schedules = medicationId == null
        ? const <Map<String, Object?>>[]
        : await AppDatabase.instance.getMedicationSchedules(medicationId);
    final takenLogs = medicationId == null
        ? const <Map<String, Object?>>[]
        : await AppDatabase.instance.getDoseLogs(
            medicationId: medicationId,
            status: 'taken',
          );
    if (!mounted) return;

    final name = medication['name']?.toString() ?? 'Medicamento';
    final dose = (medication['dose_amount'] as num?)?.toDouble() ?? 0;
    final unit = _shortUnit(medication['dose_unit']?.toString() ?? '');
    final formRaw = medication['form']?.toString() ?? 'Dosis';
    final form = _pluralize(formRaw);
    final isIndefinite = (medication['indefinite'] as num?)?.toInt() == 1;
    final hideInventory = _hideInventoryForForm(formRaw) || isIndefinite;
    final scheduleTitle = _scheduleTitleForForm(formRaw);
    final nextActionTitle = _nextActionTitleForForm(formRaw);
    final frequency = _frequencyLabel(
      medication['frequency_rule']?.toString() ?? '',
    );
    final instructions = medication['instructions']?.toString().trim();
    final stockCurrent = (medication['stock_current'] as num?)?.toDouble() ?? 0;
    final stockInitial =
        (medication['stock_initial'] as num?)?.toDouble() ?? stockCurrent;
    final progress = _inventoryProgress(stockCurrent, stockInitial);
    final nextDose = _nextDoseLabel(medication, schedules, takenLogs);
    final doseTimes = _doseTimesLabel(medication, schedules, takenLogs);
    final imagePath = medication['_image_path']?.toString();

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        final maxModalHeight = mediaQuery.size.height - mediaQuery.padding.top;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxModalHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Detalles del Medicamento',
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Color(0xFF71839F)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF1F9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: _medicationVisual(
                              form: formRaw,
                              imagePath: imagePath,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        name,
                                        style: const TextStyle(
                                          fontSize: 19,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    _detailStatusPill(!_isFinished(medication)),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_formatDose(dose)}$unit • $form',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF5A6D88),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _detailInfoRow(
                        icon: Icons.schedule,
                        title: 'FRECUENCIA',
                        value: frequency,
                      ),
                      const SizedBox(height: 10),
                      _detailInfoRow(
                        icon: Icons.alarm_outlined,
                        title: scheduleTitle,
                        value: doseTimes,
                      ),
                      const SizedBox(height: 10),
                      _detailInfoRow(
                        icon: Icons.info_outline,
                        title: 'INSTRUCCIONES',
                        value: instructions == null || instructions.isEmpty
                            ? 'Sin instrucciones'
                            : instructions,
                      ),
                      if (!hideInventory) ...[
                        const SizedBox(height: 14),
                        const Text(
                          'INVENTARIO',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF90A1B8),
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${_formatDose(stockCurrent)} $form restantes',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1A2740),
                                ),
                              ),
                            ),
                            Text(
                              '${(progress * 100).round()}%',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF2F80ED),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            borderRadius: BorderRadius.circular(999),
                            value: progress,
                            minHeight: 8,
                            backgroundColor: const Color(0xFFDCE8F5),
                            color: const Color(0xFF2F80ED),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF4FA),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.alarm,
                              color: Color(0xFF2F80ED),
                              size: 24,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    nextActionTitle,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF2F80ED),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    nextDose,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2F80ED),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cerrar'),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _detailStatusPill(bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFDFF5E7) : const Color(0xFFE9EDF3),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isActive ? 'EN CURSO' : 'FINALIZADO',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: isActive ? const Color(0xFF2E9B66) : const Color(0xFF72829B),
        ),
      ),
    );
  }

  Widget _detailInfoRow({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF2F80ED), size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF90A1B8),
                  letterSpacing: 0.2,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  double _inventoryProgress(double stockCurrent, double stockInitial) {
    if (stockCurrent <= 0) return 0;
    if (stockInitial <= 0) return 1;
    return (stockCurrent / stockInitial).clamp(0.0, 1.0);
  }

  String _nextDoseLabel(
    Map<String, Object?> medication,
    List<Map<String, Object?>> schedules,
    List<Map<String, Object?>> takenLogs,
  ) {
    final now = DateTime.now();
    final nextSchedules = _nextScheduleDateTimes(
      medication: medication,
      schedules: schedules,
      takenLogs: takenLogs,
      now: now,
    );
    if (nextSchedules.isEmpty) return 'Sin horario programado';
    final next = nextSchedules.first;
    final dayLabel = _relativeDayLabel(next, now);
    final timeLabel = _formatHour12(next);
    return '$dayLabel, $timeLabel';
  }

  Widget _medicationVisual({required String form, required String? imagePath}) {
    final hasImage = imagePath != null && imagePath.trim().isNotEmpty;
    if (hasImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(imagePath),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _medicationIcon(form);
          },
        ),
      );
    }
    return _medicationIcon(form);
  }

  Widget _medicationIcon(String form) {
    return Icon(
      _iconForMedication(form),
      weight: _iconWeightForMedication(form),
      color: const Color(0xFF2F80ED),
      size: 32,
    );
  }

  String _doseTimesLabel(
    Map<String, Object?> medication,
    List<Map<String, Object?>> schedules,
    List<Map<String, Object?>> takenLogs,
  ) {
    final nextSchedules = _nextScheduleDateTimes(
      medication: medication,
      schedules: schedules,
      takenLogs: takenLogs,
      now: DateTime.now(),
    );
    if (nextSchedules.isEmpty) return 'Sin horario programado';
    final labels = nextSchedules
        .map((date) => _formatHour12(date))
        .toList(growable: false);
    return labels.join(' • ');
  }

  List<DateTime> _nextScheduleDateTimes({
    required Map<String, Object?> medication,
    required List<Map<String, Object?>> schedules,
    required List<Map<String, Object?>> takenLogs,
    required DateTime now,
  }) {
    final scheduleMinutes = <int>[];
    for (final row in schedules) {
      final time = row['time_of_day']?.toString() ?? '';
      final parts = time.split(':');
      if (parts.length != 2) continue;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) continue;
      scheduleMinutes.add((hour * 60) + minute);
    }
    if (scheduleMinutes.isEmpty) return const [];
    scheduleMinutes.sort();

    final firstDoseAt = _firstDoseAtForMedication(medication, scheduleMinutes);
    if (firstDoseAt == null) return const [];
    final dayInterval = _dayIntervalFromFrequencyRule(
      medication['frequency_rule']?.toString(),
    );

    final endDateRaw = medication['end_date']?.toString().trim();
    final endDate = (endDateRaw == null || endDateRaw.isEmpty)
        ? null
        : DateTime.tryParse(endDateRaw);
    final endDateExclusive = endDate == null
        ? null
        : DateTime(endDate.year, endDate.month, endDate.day + 1);

    final takenKeys = <String>{};
    for (final log in takenLogs) {
      final scheduledAtRaw = log['scheduled_at']?.toString();
      if (scheduledAtRaw == null || scheduledAtRaw.trim().isEmpty) continue;
      final scheduledAt = DateTime.tryParse(scheduledAtRaw);
      if (scheduledAt == null) continue;
      takenKeys.add(_dateTimeKey(scheduledAt));
    }

    final nextSchedules = <DateTime>[];
    for (final scheduleMinute in scheduleMinutes) {
      var candidate = DateTime(
        now.year,
        now.month,
        now.day,
        scheduleMinute ~/ 60,
        scheduleMinute % 60,
      );
      if (candidate.isBefore(now)) {
        candidate = candidate.add(const Duration(days: 1));
      }
      candidate = _alignToIntervalDay(candidate, firstDoseAt, dayInterval);

      final firstDayCandidate = DateTime(
        firstDoseAt.year,
        firstDoseAt.month,
        firstDoseAt.day,
        scheduleMinute ~/ 60,
        scheduleMinute % 60,
      );
      if (candidate.isBefore(firstDoseAt)) {
        candidate = firstDayCandidate.isBefore(firstDoseAt)
            ? firstDayCandidate.add(Duration(days: dayInterval))
            : firstDayCandidate;
        candidate = _alignToIntervalDay(candidate, firstDoseAt, dayInterval);
      }

      if (endDateExclusive != null && !candidate.isBefore(endDateExclusive)) {
        continue;
      }
      while (takenKeys.contains(_dateTimeKey(candidate))) {
        candidate = candidate.add(Duration(days: dayInterval));
      }
      if (endDateExclusive != null && !candidate.isBefore(endDateExclusive)) {
        continue;
      }
      nextSchedules.add(candidate);
    }
    nextSchedules.sort();
    return nextSchedules;
  }

  String _dateTimeKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  DateTime? _firstDoseAtForMedication(
    Map<String, Object?> medication,
    List<int> scheduleMinutes,
  ) {
    final firstDoseAtRaw = medication['first_dose_at']?.toString().trim();
    final firstDoseAt = (firstDoseAtRaw == null || firstDoseAtRaw.isEmpty)
        ? null
        : DateTime.tryParse(firstDoseAtRaw);
    if (firstDoseAt != null) return firstDoseAt;

    final startDateRaw = medication['start_date']?.toString().trim();
    final startDate = (startDateRaw == null || startDateRaw.isEmpty)
        ? null
        : DateTime.tryParse(startDateRaw);
    if (startDate == null || scheduleMinutes.isEmpty) return null;

    final firstMinute = scheduleMinutes.first;
    return DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
      firstMinute ~/ 60,
      firstMinute % 60,
    );
  }

  String _relativeDayLabel(DateTime date, DateTime today) {
    final onlyToday = DateTime(today.year, today.month, today.day);
    final onlyDate = DateTime(date.year, date.month, date.day);
    final difference = onlyDate.difference(onlyToday).inDays;
    if (difference == 0) return 'Hoy';
    if (difference == 1) return 'Mañana';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  }

  String _formatHour12(DateTime date) {
    final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final suffix = date.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $suffix';
  }

  bool _hideInventoryForForm(String form) {
    final lower = form.toLowerCase();
    return lower.contains('jarabe') ||
        lower.contains('crema') ||
        lower.contains('gota');
  }

  Widget _statusBadge({required bool isFinished, required bool lowStock}) {
    final backgroundColor = isFinished
        ? const Color(0xFFE9EDF3)
        : (lowStock ? const Color(0xFFFEE8D9) : const Color(0xFFDFF5E7));
    final textColor = isFinished
        ? const Color(0xFF72829B)
        : (lowStock ? const Color(0xFFF07A2C) : const Color(0xFF2E9B66));
    final label = isFinished
        ? 'Finalizado'
        : (lowStock ? 'Stock bajo' : 'En curso');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _emptyCard(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        message,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: Color(0xFF5E6F87),
        ),
      ),
    );
  }
}

bool _isFinished(Map<String, Object?> medication) {
  final status = medication['status']?.toString() ?? 'active';
  if (status != 'active') return true;

  final stockCurrent = (medication['stock_current'] as num?)?.toDouble();
  if (stockCurrent != null && stockCurrent <= 0) return true;

  return false;
}

String _shortUnit(String fullUnit) {
  final index = fullUnit.indexOf(' ');
  return index > 0 ? fullUnit.substring(0, index) : fullUnit;
}

String _formatDose(double amount) {
  return amount == amount.roundToDouble()
      ? amount.toInt().toString()
      : amount.toString();
}

String _pluralize(String form) {
  final lower = form.toLowerCase();
  if (lower.endsWith('s')) return lower;
  if (lower.endsWith('ción')) {
    return '${lower.substring(0, lower.length - 4)}ciones';
  }
  if (lower.endsWith('ión')) {
    return '${lower.substring(0, lower.length - 3)}iones';
  }
  if (lower.endsWith('z')) return '${lower.substring(0, lower.length - 1)}ces';
  return '${lower}s';
}

String _frequencyLabel(String rule) {
  if (rule == 'daily' || rule == 'every_24_hours') return 'Cada 24 horas';
  if (rule == 'every_12_hours') return 'Cada 12 horas';
  if (rule == 'every_8_hours') return 'Cada 8 horas';
  if (rule == 'every_6_hours') return 'Cada 6 horas';
  final everyNDaysMatch = RegExp(r'^every_(\d+)_days$').firstMatch(rule);
  if (everyNDaysMatch != null) {
    final days = int.tryParse(everyNDaysMatch.group(1) ?? '');
    if (days != null && days >= 2) return 'Cada $days días';
  }
  if (rule.startsWith('custom_times')) return 'Horas personalizadas';
  if (rule.trim().isEmpty) return 'Sin frecuencia';
  return rule;
}

int _dayIntervalFromFrequencyRule(String? rawRule) {
  final rule = (rawRule ?? '').trim().toLowerCase();
  final match = RegExp(r'^every_(\d+)_days$').firstMatch(rule);
  if (match == null) return 1;
  final parsed = int.tryParse(match.group(1) ?? '');
  if (parsed == null || parsed < 2) return 1;
  return parsed;
}

DateTime _alignToIntervalDay(
  DateTime candidate,
  DateTime firstDoseAt,
  int dayInterval,
) {
  if (dayInterval <= 1) return candidate;
  final candidateDay = DateTime(candidate.year, candidate.month, candidate.day);
  final firstDay = DateTime(
    firstDoseAt.year,
    firstDoseAt.month,
    firstDoseAt.day,
  );
  if (candidateDay.isBefore(firstDay)) return candidate;
  final dayDiff = candidateDay.difference(firstDay).inDays;
  final remainder = dayDiff % dayInterval;
  if (remainder == 0) return candidate;
  final addDays = dayInterval - remainder;
  return candidate.add(Duration(days: addDays));
}

String _scheduleTitleForForm(String form) {
  return switch (_formCategoryFor(form)) {
    _FormCategory.injection => 'HORAS DE APLICACION',
    _FormCategory.patch => 'HORAS DE APLICACION',
    _FormCategory.topical => 'HORAS DE APLICACION',
    _FormCategory.sprayOrInhaler => 'HORAS DE APLICACION',
    _FormCategory.drops => 'HORAS DE APLICACION',
    _FormCategory.suppository => 'HORAS DE DOSIS',
    _ => 'HORAS DE TOMA',
  };
}

String _nextActionTitleForForm(String form) {
  return switch (_formCategoryFor(form)) {
    _FormCategory.injection => 'Próxima aplicación',
    _FormCategory.patch => 'Próxima aplicación',
    _FormCategory.topical => 'Próxima aplicación',
    _FormCategory.sprayOrInhaler => 'Próxima aplicación',
    _FormCategory.drops => 'Próxima aplicación',
    _FormCategory.suppository => 'Próxima dosis',
    _ => 'Próxima toma',
  };
}

_FormCategory _formCategoryFor(String form) {
  final lower = form.toLowerCase();
  if (lower.contains('supositorio')) return _FormCategory.suppository;
  if (lower.contains('parche')) return _FormCategory.patch;
  if (lower.contains('crema')) return _FormCategory.topical;
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

enum _FormCategory {
  solid,
  injection,
  drops,
  sprayOrInhaler,
  patch,
  topical,
  powder,
  suppository,
  other,
}

IconData _iconForMedication(String form) {
  final lower = form.toLowerCase();
  if (lower.contains('tableta') ||
      lower.contains('cápsula') ||
      lower.contains('capsula')) {
    return Symbols.pill;
  }
  if (lower.contains('inyec')) return Icons.vaccines_outlined;
  if (lower.contains('jarabe') || lower.contains('liquid')) {
    return Icons.medication_liquid_outlined;
  }
  if (lower.contains('gota')) return Icons.water_drop_outlined;
  if (lower.contains('crema')) return Icons.sanitizer_outlined;
  if (lower.contains('polvo')) return Icons.grain;
  if (lower.contains('spray')) return Icons.air;
  if (lower.contains('inhalador')) return Icons.air;
  if (lower.contains('parche')) return Icons.healing_outlined;
  if (lower.contains('supositorio')) return Icons.medication_outlined;
  return Icons.medication_outlined;
}

double? _iconWeightForMedication(String form) {
  final lower = form.toLowerCase();
  if (lower.contains('tableta') ||
      lower.contains('cápsula') ||
      lower.contains('capsula')) {
    return 600;
  }
  return null;
}
