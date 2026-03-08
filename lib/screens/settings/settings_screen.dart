import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mis_medicamentos/db/local/medications_db.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mis_medicamentos/services/ai_chat_service.dart';
import 'package:mis_medicamentos/services/notifications_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _appVersionLabel = '1.0.0+6002';
  bool _isSigningIn = false;
  bool _isSyncingData = false;
  bool _isSigningOut = false;
  bool _isClearingData = false;
  bool _isDeletingCloudData = false;
  bool _remindersEnabled = true;
  bool _isUpdatingReminders = false;
  bool _isUpdatingNotificationSound = false;
  String _notificationSoundLabel = 'Cargando...';
  bool _isLoadingAiSettings = true;
  bool _isSavingAiSettings = false;
  bool _usePersonalApiKey = false;
  bool _hasPersonalApiKey = false;
  DateTime? _lastSyncAt;
  StreamSubscription<User?>? _authSubscription;

  Future<void> _showStatusDialog({
    required String message,
    String title = 'Aviso',
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Entendido',
                style: TextStyle(color: Colors.black),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _loadReminderPreference();
    _loadAiSettings();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        if (mounted) {
          setState(() => _lastSyncAt = null);
        }
        return;
      }
      _loadLastSyncFromFirestore(user.uid);
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadReminderPreference() async {
    final enabled = await NotificationsService.instance
        .isDoseRemindersEnabled();
    final soundLabel = await NotificationsService.instance
        .getReminderSoundLabel();
    if (!mounted) return;
    setState(() {
      _remindersEnabled = enabled;
      _notificationSoundLabel = soundLabel;
    });
  }

  Future<void> _loadAiSettings() async {
    await AiChatService.instance.loadApiKeyPreferences();
    if (!mounted) return;
    setState(() {
      _usePersonalApiKey = AiChatService.instance.isUsingPersonalApiKey;
      _hasPersonalApiKey = AiChatService.instance.hasPersonalApiKey;
      _isLoadingAiSettings = false;
    });
  }

  Future<String?> _showApiKeyInputDialog({required bool isEditing}) async {
    String typedKey = '';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Text(
            isEditing ? 'Editar API key personal' : 'Agregar API key personal',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          content: TextField(
            autofocus: true,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            cursorColor: const Color(0xFF2F80ED),
            onChanged: (value) => typedKey = value,
            decoration: const InputDecoration(
              hintText: 'Ingresa tu API key',
              border: OutlineInputBorder(),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF2F80ED), width: 2),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: Colors.black),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(typedKey),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2F80ED),
              ),
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _savePersonalApiKeyFlow({required bool enableAfterSave}) async {
    final key = await _showApiKeyInputDialog(isEditing: _hasPersonalApiKey);
    if (key == null) return;
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await _showStatusDialog(
        title: 'Dato requerido',
        message: 'Debes ingresar una API key válida.',
      );
      return;
    }

    setState(() => _isSavingAiSettings = true);
    try {
      final validationError = await AiChatService.instance
          .validatePersonalApiKey(trimmed);
      if (validationError != null) {
        if (!mounted) return;
        await _showStatusDialog(title: 'Error', message: validationError);
        return;
      }

      await AiChatService.instance.savePersonalApiKey(trimmed);
      await AiChatService.instance.setUsePersonalApiKey(enableAfterSave);
      if (!mounted) return;
      setState(() {
        _hasPersonalApiKey = true;
        _usePersonalApiKey = enableAfterSave;
      });
      await _showStatusDialog(message: 'API key personal guardada.');
    } finally {
      if (mounted) {
        setState(() => _isSavingAiSettings = false);
      }
    }
  }

  Future<void> _onUsePersonalApiKeyChanged(bool value) async {
    if (_isSavingAiSettings || _isLoadingAiSettings) return;

    if (value && !_hasPersonalApiKey) {
      await _savePersonalApiKeyFlow(enableAfterSave: true);
      return;
    }

    setState(() => _isSavingAiSettings = true);
    try {
      await AiChatService.instance.setUsePersonalApiKey(value);
      if (!mounted) return;
      setState(() => _usePersonalApiKey = value);
    } finally {
      if (mounted) {
        setState(() => _isSavingAiSettings = false);
      }
    }
  }

  Future<void> _deletePersonalApiKey() async {
    if (_isSavingAiSettings) return;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Eliminar API key personal',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: const Text(
            'Se borrará tu API key personal guardada y se volverá a usar la API key de la app.',
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
                foregroundColor: const Color(0xFFE85050),
                side: const BorderSide(color: Color(0xFFE85050)),
              ),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;
    setState(() => _isSavingAiSettings = true);
    try {
      await AiChatService.instance.clearPersonalApiKey();
      if (!mounted) return;
      setState(() {
        _hasPersonalApiKey = false;
        _usePersonalApiKey = false;
      });
    } finally {
      if (mounted) {
        setState(() => _isSavingAiSettings = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_isSigningIn) return;

    setState(() => _isSigningIn = true);

    try {
      final googleUser = await GoogleSignIn.instance.authenticate();
      final googleAuth = googleUser.authentication;
      if (googleAuth.idToken == null) {
        throw const GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError,
          description: 'Google no devolvió un idToken.',
        );
      }
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
    } on GoogleSignInException catch (error) {
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint(
          'Google Sign-In error: code=${error.code.name}, description=${error.description}',
        );
      }
      await _showStatusDialog(
        title: 'Error',
        message: 'No se pudo iniciar sesión con Google. Inténtalo de nuevo.',
      );
    } catch (error) {
      if (!mounted) return;
      await _showStatusDialog(
        title: 'Error',
        message: 'No se pudo iniciar sesión: $error',
      );
    } finally {
      if (mounted) {
        setState(() => _isSigningIn = false);
      }
    }
  }

  Future<void> _syncDataToFirestore() async {
    if (_isSyncingData) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text(
              'Inicia sesión',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            content: const Text('Debes iniciar sesión para sincronizar.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Entendido',
                  style: TextStyle(color: Colors.black),
                ),
              ),
            ],
          );
        },
      );
      return;
    }

    setState(() => _isSyncingData = true);

    try {
      final db = AppDatabase.instance;
      final medications = await db.getMedications();
      final firestore = FirebaseFirestore.instance;
      final userRef = firestore.collection('users').doc(user.uid);
      final syncRef = userRef.collection('sync').doc('latest');

      if (medications.isEmpty) {
        final remoteMedications = await syncRef
            .collection('medications')
            .limit(1)
            .get();
        if (remoteMedications.docs.isNotEmpty) {
          await _restoreDataFromFirestore(syncRef: syncRef);
          await _loadLastSyncFromFirestore(user.uid);
          AppDatabase.instance.notifyMedicationsChanged();
          if (!mounted) return;
          await _showStatusDialog(message: 'Datos restaurados exitosamente.');
          return;
        }
      }

      final medicationSchedules = await db.getAllMedicationSchedules();
      final medicationAttachments = await db.getMedicationAttachments();
      final doseLogs = await db.getDoseLogs();
      final notificationLogs = await db.getNotificationLogs(limit: 5000);

      await userRef.set({
        'last_sync_at': FieldValue.serverTimestamp(),
        'email': user.email,
        'display_name': user.displayName,
      }, SetOptions(merge: true));

      await syncRef.set({
        'updated_at': FieldValue.serverTimestamp(),
        'medications_count': medications.length,
        'medication_schedules_count': medicationSchedules.length,
        'medication_attachments_count': medicationAttachments.length,
        'dose_logs_count': doseLogs.length,
        'notification_logs_count': notificationLogs.length,
      }, SetOptions(merge: true));

      Future<void> writeCollection({
        required String collection,
        required List<Map<String, Object?>> rows,
      }) async {
        const batchSize = 400;
        WriteBatch batch = firestore.batch();
        var pendingOps = 0;

        for (final row in rows) {
          final id = row['id'];
          if (id == null) continue;
          final docRef = syncRef.collection(collection).doc(id.toString());
          batch.set(docRef, {
            ...row,
            'synced_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          pendingOps++;

          if (pendingOps >= batchSize) {
            await batch.commit();
            batch = firestore.batch();
            pendingOps = 0;
          }
        }

        if (pendingOps > 0) {
          await batch.commit();
        }
      }

      await writeCollection(
        collection: 'medications',
        rows: medications.map((row) => Map<String, Object?>.from(row)).toList(),
      );
      await writeCollection(
        collection: 'medication_schedules',
        rows: medicationSchedules
            .map((row) => Map<String, Object?>.from(row))
            .toList(),
      );
      await writeCollection(
        collection: 'medication_attachments',
        rows: medicationAttachments
            .map((row) => Map<String, Object?>.from(row))
            .toList(),
      );
      await writeCollection(
        collection: 'dose_logs',
        rows: doseLogs.map((row) => Map<String, Object?>.from(row)).toList(),
      );
      await writeCollection(
        collection: 'notification_logs',
        rows: notificationLogs
            .map((row) => Map<String, Object?>.from(row))
            .toList(),
      );
      await _loadLastSyncFromFirestore(user.uid);
      AppDatabase.instance.notifyMedicationsChanged();

      if (!mounted) return;
      await _showStatusDialog(message: 'Datos sincronizados exitosamente.');
    } catch (error) {
      if (!mounted) return;
      await _showStatusDialog(
        title: 'Error',
        message: 'Error al sincronizar: $error',
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncingData = false);
      }
    }
  }

  Future<void> _loadLastSyncFromFirestore(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('sync')
          .doc('latest')
          .get();
      final data = doc.data();
      final updatedAt = data?['updated_at'];
      if (updatedAt is! Timestamp || !mounted) return;
      setState(() => _lastSyncAt = updatedAt.toDate());
    } catch (_) {
      // Best-effort read for UI label.
    }
  }

  Future<void> _signOut() async {
    if (_isSigningOut) return;

    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Cerrar sesión',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: const Text('¿Estás seguro de que deseas cerrar tu sesión?'),
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
                foregroundColor: const Color(0xFFE85050),
                side: const BorderSide(color: Color(0xFFE85050)),
              ),
              child: const Text('Cerrar sesión'),
            ),
          ],
        );
      },
    );

    if (shouldSignOut != true) return;

    setState(() => _isSigningOut = true);
    try {
      await GoogleSignIn.instance.signOut();
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      await _showStatusDialog(message: 'Sesión cerrada exitosamente.');
    } catch (error) {
      if (!mounted) return;
      await _showStatusDialog(
        title: 'Error',
        message: 'No se pudo cerrar sesión: $error',
      );
    } finally {
      if (mounted) {
        setState(() => _isSigningOut = false);
      }
    }
  }

  Future<void> _restoreDataFromFirestore({
    required DocumentReference<Map<String, dynamic>> syncRef,
  }) async {
    Future<List<Map<String, Object?>>> readCollection(String name) async {
      final snap = await syncRef.collection(name).get();
      return snap.docs.map((doc) {
        final map = Map<String, dynamic>.from(doc.data());
        final id = map['id'];
        if (id == null) {
          final parsed = int.tryParse(doc.id);
          if (parsed != null) {
            map['id'] = parsed;
          }
        }
        map.remove('synced_at');
        return map.map((key, value) => MapEntry(key, value as Object?));
      }).toList();
    }

    final medications = await readCollection('medications');
    final medicationSchedules = await readCollection('medication_schedules');
    final medicationAttachments = await readCollection(
      'medication_attachments',
    );
    final doseLogs = await readCollection('dose_logs');
    final notificationLogs = await readCollection('notification_logs');

    await AppDatabase.instance.replaceAllFromCloud(
      medications: medications,
      medicationSchedules: medicationSchedules,
      medicationAttachments: medicationAttachments,
      doseLogs: doseLogs,
      notificationLogs: notificationLogs,
    );
    NotificationsService.instance.historyChangeToken.value++;

    await NotificationsService.instance
        .syncTodayDoseNotificationsFromDatabase();
  }

  Future<void> _onRemindersChanged(bool value) async {
    if (_isUpdatingReminders) return;
    setState(() => _isUpdatingReminders = true);
    try {
      await NotificationsService.instance.setDoseRemindersEnabled(value);
      if (!mounted) return;
      setState(() => _remindersEnabled = value);
    } catch (error) {
      if (!mounted) return;
      await _showStatusDialog(
        title: 'Error',
        message: 'No se pudo actualizar recordatorios: $error',
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingReminders = false);
      }
    }
  }

  Future<void> _onNotificationSoundTap() async {
    if (_isUpdatingNotificationSound) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      await _showStatusDialog(
        title: 'No disponible',
        message: 'La selección de tono del sistema está disponible en Android.',
      );
      return;
    }

    final action = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Sonidos y alertas',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: const Text('Elige el tono para los recordatorios.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('default'),
              child: const Text(
                'Usar predeterminado',
                style: TextStyle(color: Colors.black),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('pick'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2F80ED),
              ),
              child: const Text('Elegir tono'),
            ),
          ],
        );
      },
    );

    if (action == null) return;

    setState(() => _isUpdatingNotificationSound = true);
    try {
      var changed = false;
      if (action == 'pick') {
        changed = await NotificationsService.instance
            .chooseReminderSoundFromSystem();
      } else if (action == 'default') {
        await NotificationsService.instance.resetReminderSoundToDefault();
        changed = true;
      }

      if (!mounted) return;
      if (!changed) {
        setState(() => _isUpdatingNotificationSound = false);
        return;
      }

      final soundLabel = await NotificationsService.instance
          .getReminderSoundLabel();
      if (!mounted) return;
      setState(() => _notificationSoundLabel = soundLabel);
      await _showStatusDialog(message: 'Tono de notificación actualizado.');
    } catch (error) {
      if (!mounted) return;
      await _showStatusDialog(
        title: 'Error',
        message: 'No se pudo actualizar el tono: $error',
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingNotificationSound = false);
      }
    }
  }

  Future<bool?> _showConfirmClearDataDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Eliminar datos de la app',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: const Text(
            'Se eliminaran todos los datos locales: medicamentos, horarios, tomas y notificaciones guardadas. Esta accion no se puede deshacer.',
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
                foregroundColor: const Color(0xFFE85050),
                side: const BorderSide(color: Color(0xFFE85050)),
              ),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _clearAllAppData() async {
    if (_isClearingData) return;

    final confirmed = await _showConfirmClearDataDialog();
    if (confirmed != true) return;

    setState(() => _isClearingData = true);
    try {
      await AppDatabase.instance.clearAllData();
      await NotificationsService.instance.syncTodayDoseNotifications(
        doses: const [],
      );
      NotificationsService.instance.historyChangeToken.value++;
      if (!mounted) return;
      await _showStatusDialog(
        title: 'Datos eliminados',
        message: 'Todos los datos locales de la app fueron eliminados.',
      );
    } catch (error) {
      if (!mounted) return;
      await _showStatusDialog(
        title: 'Error',
        message: 'No se pudieron eliminar los datos: $error',
      );
    } finally {
      if (mounted) {
        setState(() => _isClearingData = false);
      }
    }
  }

  Future<bool?> _showConfirmDeleteFirestoreDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Eliminar datos de la nube',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: const Text(
            'Se eliminara tu respaldo en la nube (medicamentos, horarios, tomas e historial). Esta accion no se puede deshacer.',
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
                foregroundColor: const Color(0xFFE85050),
                side: const BorderSide(color: Color(0xFFE85050)),
              ),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteFirestoreData() async {
    if (_isDeletingCloudData) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await _showStatusDialog(
        title: 'Inicia sesión',
        message: 'Debes iniciar sesión para borrar datos de Firestore.',
      );
      return;
    }

    final confirmed = await _showConfirmDeleteFirestoreDialog();
    if (confirmed != true) return;

    setState(() => _isDeletingCloudData = true);
    try {
      final firestore = FirebaseFirestore.instance;
      final userRef = firestore.collection('users').doc(user.uid);
      final syncRef = userRef.collection('sync').doc('latest');

      Future<void> deleteCollection(
        CollectionReference<Map<String, dynamic>> collection,
      ) async {
        const batchSize = 350;
        while (true) {
          final snap = await collection.limit(batchSize).get();
          if (snap.docs.isEmpty) break;
          final batch = firestore.batch();
          for (final doc in snap.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit();
          if (snap.docs.length < batchSize) break;
        }
      }

      await deleteCollection(syncRef.collection('medications'));
      await deleteCollection(syncRef.collection('medication_schedules'));
      await deleteCollection(syncRef.collection('medication_attachments'));
      await deleteCollection(syncRef.collection('dose_logs'));
      await deleteCollection(syncRef.collection('notification_logs'));
      await syncRef.delete();
      await userRef.delete();

      if (!mounted) return;
      setState(() => _lastSyncAt = null);
      await _showStatusDialog(
        title: 'Datos eliminados',
        message: 'Tus datos en la nube fueron eliminados.',
      );
    } catch (error) {
      if (!mounted) return;
      await _showStatusDialog(
        title: 'Error',
        message: 'No se pudieron eliminar tus datos en la nube: $error',
      );
    } finally {
      if (mounted) {
        setState(() => _isDeletingCloudData = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: const Text(
          'Ajustes',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shadowColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, size: 28),
            tooltip: 'Ayuda de sincronización',
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: const Text(
                      'Cómo funciona la sincronización',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    content: const Text(
                      '• Si ya tienes datos en la app, al sincronizar se guardan en la nube.\n'
                      '• Si la app está vacía, al sincronizar recupera lo que ya tenías guardado en la nube.\n'
                      '• Esa recuperación automática solo pasa cuando la app está vacía.\n'
                      '• Si borras un medicamento en la app y aún quedan otros, ese borrado no se refleja solo en la nube.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'Entendido',
                          style: TextStyle(color: Colors.black),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.white,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          child: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              final user = snapshot.data;
              final userName = (user?.displayName?.trim().isNotEmpty ?? false)
                  ? user!.displayName!.trim()
                  : '';
              final userEmail = (user?.email?.trim().isNotEmpty ?? false)
                  ? user!.email!.trim()
                  : '';
              final lastSyncText = _lastSyncAt == null
                  ? 'Última sincronización: nunca'
                  : 'Última sincronización: ${DateFormat('dd/MM/yyyy hh:mm a', 'es_ES').format(_lastSyncAt!)}';

              return Column(
                children: [
                  if (isAndroid && user == null) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isSigningIn ? null : _signInWithGoogle,
                        icon: _isSigningIn
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Color(0xFF1F2B3A),
                                  strokeWidth: 2,
                                ),
                              )
                            : Image.asset(
                                'assets/google_logo.ico',
                                width: 20,
                                height: 20,
                              ),
                        label: Text(
                          _isSigningIn
                              ? 'Iniciando sesión...'
                              : 'Iniciar sesión con Google',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1F2B3A),
                          side: const BorderSide(color: Color(0xFFD3DCE9)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (user != null) ...[
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 124,
                          height: 124,
                          decoration: const BoxDecoration(
                            color: Color(0xFFD6DEE9),
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(6),
                          child: Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [Color(0xFFEFE7DA), Color(0xFFD8E2EE)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                            child:
                                (user.photoURL != null &&
                                    user.photoURL!.trim().isNotEmpty)
                                ? ClipOval(
                                    child: Image.network(
                                      user.photoURL!,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : const Icon(
                                    Icons.person_rounded,
                                    size: 74,
                                    color: Color(0xFF4D5B73),
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      userName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      userEmail,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF70819A),
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Sincronizar datos',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F9FE),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE3EBF6)),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          onTap: _isSyncingData ? null : _syncDataToFirestore,
                          titleAlignment: ListTileTitleAlignment.center,
                          leading: Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCE8F8),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.sync_rounded,
                              color: Color(0xFF2F80ED),
                              size: 31,
                            ),
                          ),
                          title: const Text(
                            'Sincronizar ahora',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            'Copia de medicamentos e historial en la nube\n$lastSyncText',
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                              color: Color(0xFF5F7190),
                            ),
                          ),
                          isThreeLine: true,
                          trailing: _isSyncingData
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF2F80ED),
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Notificaciones',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F9FE),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE3EBF6)),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          leading: Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCE8F8),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.notifications_active_rounded,
                              color: Color(0xFF2F80ED),
                              size: 31,
                            ),
                          ),
                          title: const Text(
                            'Recordatorios',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: const Text(
                            'Avisos de dosis programadas',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF5F7190),
                            ),
                          ),
                          trailing: Switch(
                            value: _remindersEnabled,
                            onChanged: _isUpdatingReminders
                                ? null
                                : _onRemindersChanged,
                            activeTrackColor: const Color(0xFF2F80ED),
                            activeThumbColor: Colors.white,
                          ),
                        ),
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        ListTile(
                          onTap: _isUpdatingNotificationSound
                              ? null
                              : _onNotificationSoundTap,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          leading: Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCE8F8),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.volume_up_rounded,
                              color: Color(0xFF2F80ED),
                              size: 31,
                            ),
                          ),
                          title: const Text(
                            'Sonidos y alertas',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            _notificationSoundLabel,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF5F7190),
                            ),
                          ),
                          trailing: _isUpdatingNotificationSound
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF2F80ED),
                                  ),
                                )
                              : const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Color(0xFF98A4BA),
                                  size: 28,
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Asistente IA',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F9FE),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE3EBF6)),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          leading: Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCE8F8),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.key_rounded,
                              color: Color(0xFF2F80ED),
                              size: 31,
                            ),
                          ),
                          title: const Text(
                            'Usar mi API key',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            _isLoadingAiSettings
                                ? 'Cargando configuración...'
                                : _hasPersonalApiKey
                                ? (_usePersonalApiKey
                                      ? 'Activa: usando tu API key personal.'
                                      : 'Guardada, pero actualmente se usa la key de la app.')
                                : 'No hay API key personal guardada. Se usa la key de la app.',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF5F7190),
                            ),
                          ),
                          trailing: _isSavingAiSettings || _isLoadingAiSettings
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF2F80ED),
                                  ),
                                )
                              : Switch(
                                  value: _usePersonalApiKey,
                                  onChanged: _onUsePersonalApiKeyChanged,
                                  activeTrackColor: const Color(0xFF2F80ED),
                                  activeThumbColor: Colors.white,
                                ),
                        ),
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        ListTile(
                          onTap: _isSavingAiSettings || _isLoadingAiSettings
                              ? null
                              : () => _savePersonalApiKeyFlow(
                                  enableAfterSave: _usePersonalApiKey,
                                ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          leading: Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCE8F8),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Icon(
                              _hasPersonalApiKey
                                  ? Icons.edit_rounded
                                  : Icons.add_circle_outline_rounded,
                              color: const Color(0xFF2F80ED),
                              size: 31,
                            ),
                          ),
                          title: Text(
                            _hasPersonalApiKey
                                ? 'Editar API key personal'
                                : 'Agregar API key personal',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: const Text(
                            'Tu API key se valida antes de guardarse. Obten una en groq.com',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF5F7190),
                            ),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            color: Color(0xFF98A4BA),
                            size: 28,
                          ),
                        ),
                        if (_hasPersonalApiKey) ...[
                          const Divider(height: 1, color: Color(0xFFE2E8F0)),
                          Container(
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFF6F6),
                              borderRadius: BorderRadius.vertical(
                                bottom: Radius.circular(18),
                              ),
                            ),
                            child: ListTile(
                              onTap: _isSavingAiSettings || _isLoadingAiSettings
                                  ? null
                                  : _deletePersonalApiKey,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              leading: Container(
                                width: 58,
                                height: 58,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFDE6E6),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Color(0xFFE85050),
                                  size: 31,
                                ),
                              ),
                              title: const Text(
                                'Eliminar API key personal',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFB23434),
                                ),
                              ),
                              subtitle: const Text(
                                'Volverás a usar la API key de la app.',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF8A5858),
                                ),
                              ),
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                                color: Color(0xFFBE8D8D),
                                size: 28,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Datos de la App',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF6F6),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFF3DADA)),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          onTap: _isClearingData ? null : _clearAllAppData,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          leading: Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFDE6E6),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.delete_forever_rounded,
                              color: Color(0xFFE85050),
                              size: 31,
                            ),
                          ),
                          title: const Text(
                            'Eliminar datos de la app',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFB23434),
                            ),
                          ),
                          subtitle: const Text(
                            'Borra medicamentos, horarios, tomas e historial local.',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF8A5858),
                            ),
                          ),
                          trailing: _isClearingData
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFFE85050),
                                  ),
                                )
                              : const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Color(0xFFBE8D8D),
                                  size: 28,
                                ),
                        ),
                        if (user != null) ...[
                          const Divider(height: 1, color: Color(0xFFF3DADA)),
                          ListTile(
                            onTap: _isDeletingCloudData
                                ? null
                                : _deleteFirestoreData,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            leading: Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFDE6E6),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Icon(
                                Icons.cloud_off_rounded,
                                color: Color(0xFFE85050),
                                size: 31,
                              ),
                            ),
                            title: const Text(
                              'Eliminar datos de la nube',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFB23434),
                              ),
                            ),
                            subtitle: const Text(
                              'Borra el respaldo de tu cuenta en la nube.',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF8A5858),
                              ),
                            ),
                            trailing: _isDeletingCloudData
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFFE85050),
                                    ),
                                  )
                                : const Icon(
                                    Icons.chevron_right_rounded,
                                    color: Color(0xFFBE8D8D),
                                    size: 28,
                                  ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (user != null) ...[
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isSigningOut ? null : _signOut,
                        icon: _isSigningOut
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.logout_rounded, size: 24),
                        label: Text(
                          _isSigningOut
                              ? 'Cerrando sesión...'
                              : 'Cerrar sesión',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFE85050),
                          side: const BorderSide(color: Color(0xFFF3CACA)),
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 38 / 2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 30),
                  const Text(
                    'Mis Medicamentos v$_appVersionLabel',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF70819A),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
