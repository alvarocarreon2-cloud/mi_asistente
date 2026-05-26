import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'student_extra_screens.dart';

enum AppRole { student, professional }

class SystemNotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const AndroidNotificationChannel _appointmentsChannel =
      AndroidNotificationChannel(
        'kaia_appointments_channel',
        'Citas KAIA',
        description: 'Notificaciones de nuevas citas clinicas',
        importance: Importance.max,
      );

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
    );
    const settings = InitializationSettings(android: android, iOS: ios);

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (_) {},
    );
    await _createAndroidChannel();
    await _requestPermissions();
    _initialized = true;
  }

  Future<void> _createAndroidChannel() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(_appointmentsChannel);
  }

  Future<void> _requestPermissions() async {
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);

    final macos = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    await macos?.requestPermissions(alert: true, badge: true, sound: true);

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
  }

  Future<void> showNewAppointmentNotification({
    required String studentName,
    required DateTime startsAt,
    required String clinicalReason,
  }) async {
    await initialize();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'kaia_appointments_channel',
        'Citas KAIA',
        channelDescription: 'Notificaciones de nuevas citas clinicas',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    final hh = startsAt.hour.toString().padLeft(2, '0');
    final mm = startsAt.minute.toString().padLeft(2, '0');

    await _plugin.show(
      id: startsAt.millisecondsSinceEpoch.remainder(2147483647),
      title: 'Tienes una cita nueva',
      body: '$studentName · $hh:$mm · Motivo clinico: $clinicalReason',
      notificationDetails: details,
    );
  }

  Future<void> showRealtimeEventNotification({
    required int eventId,
    required String title,
    required String detail,
  }) async {
    await initialize();

    const detailsConfig = NotificationDetails(
      android: AndroidNotificationDetails(
        'kaia_appointments_channel',
        'Citas KAIA',
        channelDescription: 'Notificaciones de nuevas citas clinicas',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    await _plugin.show(
      id: eventId,
      title: title,
      body: detail,
      notificationDetails: detailsConfig,
    );
  }
}

class RealtimePollResult {
  final List<RealtimeEventItem> events;
  final int latestEventId;

  const RealtimePollResult({required this.events, required this.latestEventId});
}

class RealtimeEventItem {
  final int id;
  final String title;
  final String detail;

  const RealtimeEventItem({
    required this.id,
    required this.title,
    required this.detail,
  });
}

class PushBridgeService {
  static const String _defaultPublicBackendUrl = String.fromEnvironment(
    'AI_BACKEND_URL',
    defaultValue: 'https://mi-app-ai-backend.onrender.com',
  );

  Future<void> notifyAppointmentCreated({
    required String userId,
    required String appointmentId,
    required DateTime startsAt,
    required String reason,
  }) async {
    final hh = startsAt.hour.toString().padLeft(2, '0');
    final mm = startsAt.minute.toString().padLeft(2, '0');

    await _post('/events/publish', {
      'role': 'student',
      'userId': userId,
      'title': 'Nueva cita pendiente',
      'detail': 'Tienes cita a las $hh:$mm. Motivo: $reason',
      'type': 'appointment_created',
      'payload': {
        'appointmentId': appointmentId,
        'startsAtIso': startsAt.toIso8601String(),
      },
    });
  }

  Future<void> notifyAppointmentResponse({
    required String userId,
    required String studentName,
    required String appointmentId,
    required AppointmentStatus status,
  }) async {
    final statusLabel = status == AppointmentStatus.confirmed
        ? 'confirmo la cita'
        : 'indico que no puede asistir';

    await _post('/events/publish', {
      'role': 'professional',
      'userId': userId,
      'title': 'Respuesta de cita',
      'detail': '$studentName $statusLabel.',
      'type': 'appointment_response',
      'payload': {
        'appointmentId': appointmentId,
        'status': status.name,
        'studentName': studentName,
      },
    });
  }

  Future<RealtimePollResult> pollEvents({
    required String role,
    required String userId,
    required int afterEventId,
  }) async {
    final uri = _uriFor('/events/poll').replace(
      queryParameters: {
        'role': role,
        'userId': userId,
        'after': '$afterEventId',
      },
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return RealtimePollResult(
          events: const [],
          latestEventId: afterEventId,
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return RealtimePollResult(
          events: const [],
          latestEventId: afterEventId,
        );
      }

      final rawEvents = decoded['events'];
      final events = rawEvents is List
          ? rawEvents
                .whereType<Map<String, dynamic>>()
                .map(
                  (raw) => RealtimeEventItem(
                    id: (raw['id'] is num) ? (raw['id'] as num).toInt() : 0,
                    title: (raw['title'] ?? '').toString().trim(),
                    detail: (raw['detail'] ?? '').toString().trim(),
                  ),
                )
                .where((event) => event.id > 0 && event.title.isNotEmpty)
                .toList()
          : const <RealtimeEventItem>[];

      final latest = decoded['latestEventId'];
      final latestEventId = latest is num ? latest.toInt() : afterEventId;
      return RealtimePollResult(events: events, latestEventId: latestEventId);
    } catch (_) {
      return RealtimePollResult(events: const [], latestEventId: afterEventId);
    }
  }

  Future<void> syncStudentAppointments({
    required String studentName,
    required List<Map<String, dynamic>> appointments,
  }) async {
    await _post('/appointments/sync-student', {
      'studentName': studentName,
      'appointments': appointments,
    });
  }

  Future<List<Map<String, dynamic>>> fetchAppointmentsByStudent({
    required String studentName,
  }) async {
    final uri = _uriFor(
      '/appointments/by-student',
    ).replace(queryParameters: {'studentName': studentName});

    try {
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const [];
      final raw = decoded['appointments'];
      if (raw is! List) return const [];
      return raw.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>> fetchAllAppointments() async {
    final uri = _uriFor('/appointments/all');
    try {
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const {};
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const {};
      final rawStudents = decoded['students'];
      if (rawStudents is! List) return const {};

      final result = <String, List<Map<String, dynamic>>>{};
      for (final item in rawStudents.whereType<Map<String, dynamic>>()) {
        final name = (item['studentName'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final rawAppointments = item['appointments'];
        if (rawAppointments is! List) {
          result[name] = const [];
          continue;
        }
        result[name] = rawAppointments
            .whereType<Map<String, dynamic>>()
            .toList();
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  Future<void> syncStudentTreatmentPlans({
    required String studentName,
    required List<Map<String, dynamic>> plans,
  }) async {
    await _post('/treatments/sync-student', {
      'studentName': studentName,
      'plans': plans,
    });
  }

  Future<List<Map<String, dynamic>>> fetchTreatmentPlansByStudent({
    required String studentName,
  }) async {
    final uri = _uriFor(
      '/treatments/by-student',
    ).replace(queryParameters: {'studentName': studentName});

    try {
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const [];
      final raw = decoded['plans'];
      if (raw is! List) return const [];
      return raw.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>>
  fetchAllTreatmentPlans() async {
    final uri = _uriFor('/treatments/all');
    try {
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const {};
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const {};
      final rawStudents = decoded['students'];
      if (rawStudents is! List) return const {};

      final result = <String, List<Map<String, dynamic>>>{};
      for (final item in rawStudents.whereType<Map<String, dynamic>>()) {
        final name = (item['studentName'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final rawPlans = item['plans'];
        if (rawPlans is! List) {
          result[name] = const [];
          continue;
        }
        result[name] = rawPlans.whereType<Map<String, dynamic>>().toList();
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  Future<void> syncStudentCheckIns({
    required String studentName,
    required List<Map<String, dynamic>> checkIns,
  }) async {
    await _post('/checkins/sync-student', {
      'studentName': studentName,
      'checkIns': checkIns,
    });
  }

  Future<List<Map<String, dynamic>>> fetchCheckInsByStudent({
    required String studentName,
  }) async {
    final uri = _uriFor(
      '/checkins/by-student',
    ).replace(queryParameters: {'studentName': studentName});

    try {
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const [];
      final raw = decoded['checkIns'];
      if (raw is! List) return const [];
      return raw.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>> fetchAllCheckIns() async {
    final uri = _uriFor('/checkins/all');
    try {
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const {};
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const {};
      final rawStudents = decoded['students'];
      if (rawStudents is! List) return const {};

      final result = <String, List<Map<String, dynamic>>>{};
      for (final item in rawStudents.whereType<Map<String, dynamic>>()) {
        final name = (item['studentName'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final rawCheckIns = item['checkIns'];
        if (rawCheckIns is! List) {
          result[name] = const [];
          continue;
        }
        result[name] = rawCheckIns.whereType<Map<String, dynamic>>().toList();
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  Future<void> syncStudentReflections({
    required String studentName,
    required List<Map<String, dynamic>> reflections,
  }) async {
    await _post('/reflections/sync-student', {
      'studentName': studentName,
      'reflections': reflections,
    });
  }

  Future<List<Map<String, dynamic>>> fetchReflectionsByStudent({
    required String studentName,
  }) async {
    final uri = _uriFor(
      '/reflections/by-student',
    ).replace(queryParameters: {'studentName': studentName});

    try {
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const [];
      final raw = decoded['reflections'];
      if (raw is! List) return const [];
      return raw.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>> fetchAllReflections() async {
    final uri = _uriFor('/reflections/all');
    try {
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const {};
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const {};
      final rawStudents = decoded['students'];
      if (rawStudents is! List) return const {};

      final result = <String, List<Map<String, dynamic>>>{};
      for (final item in rawStudents.whereType<Map<String, dynamic>>()) {
        final name = (item['studentName'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final rawReflections = item['reflections'];
        if (rawReflections is! List) {
          result[name] = const [];
          continue;
        }
        result[name] =
            rawReflections.whereType<Map<String, dynamic>>().toList();
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  Uri _uriFor(String path) {
    final base = _defaultPublicBackendUrl.endsWith('/')
        ? _defaultPublicBackendUrl.substring(
            0,
            _defaultPublicBackendUrl.length - 1,
          )
        : _defaultPublicBackendUrl;
    return Uri.parse('$base$path');
  }

  Future<void> _post(String path, Map<String, dynamic> body) async {
    try {
      await http.post(
        _uriFor(path),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
    } catch (_) {
      // Silent by design: realtime notification failures should not block flow.
    }
  }
}

class SchoolMentalHealthFlow extends StatefulWidget {
  final bool isDarkMode;
  final VoidCallback onToggleThemeMode;

  const SchoolMentalHealthFlow({
    super.key,
    required this.isDarkMode,
    required this.onToggleThemeMode,
  });

  @override
  State<SchoolMentalHealthFlow> createState() => _SchoolMentalHealthFlowState();
}

class _SchoolMentalHealthFlowState extends State<SchoolMentalHealthFlow> {
  AppRole? _activeRole;
  bool _loadingRole = true;
  StudentCase _studentCase = StudentCase.empty();
  final SystemNotificationService _notificationService =
      SystemNotificationService();
  final PushBridgeService _pushBridgeService = PushBridgeService();
  Timer? _realtimePollTimer;
  int _lastRealtimeEventId = 0;
  late final List<StudentCase> _demoStudents;
  final Map<String, List<ProfessionalAppointment>> _appointmentsByStudent = {};
  final Map<String, List<TreatmentPlan>> _treatmentsByStudent = {};
  final Map<String, List<DailyCheckIn>> _checkInsByStudent = {};
  final Map<String, List<StudentReflection>> _reflectionsByStudent = {};
  final List<ProfessionalAgendaNotification> _professionalNotifications = [];

  @override
  void initState() {
    super.initState();
    unawaited(_notificationService.initialize());
    _demoStudents = [
      StudentCase.demo(
        studentName: 'Valeria Torres',
        photoUrl: 'https://i.pravatar.cc/240?img=47',
        latestCheckIn: DailyCheckIn(
          date: DateTime.now().subtract(const Duration(hours: 3)),
          answers: const {},
          wellbeingScore: 34,
          riskLevel: RiskLevel.high,
          summary: 'WHO-5 bajo y elevacion simultanea en PHQ-2 y GAD-2.',
          who5Percent: 28,
          phq2Score: 4,
          gad2Score: 5,
        ),
      ),
      StudentCase.demo(
        studentName: 'Mateo Rojas',
        photoUrl: 'https://i.pravatar.cc/240?img=12',
        latestCheckIn: DailyCheckIn(
          date: DateTime.now().subtract(const Duration(days: 1, hours: 2)),
          answers: const {},
          wellbeingScore: 61,
          riskLevel: RiskLevel.medium,
          summary: 'Malestar moderado con un instrumento en rango de alerta.',
          who5Percent: 48,
          phq2Score: 2,
          gad2Score: 3,
        ),
      ),
      StudentCase.demo(
        studentName: 'Sofia Mendez',
        photoUrl: 'https://i.pravatar.cc/240?img=5',
        latestCheckIn: DailyCheckIn(
          date: DateTime.now().subtract(const Duration(days: 2, hours: 5)),
          answers: const {},
          wellbeingScore: 84,
          riskLevel: RiskLevel.low,
          summary: 'Check-in estable sin indicadores clinicos de alerta.',
          who5Percent: 72,
          phq2Score: 1,
          gad2Score: 1,
        ),
      ),
    ];
    _appointmentsByStudent[_studentCase.studentName] =
        _studentCase.appointments;
    _treatmentsByStudent[_studentCase.studentName] =
        _studentCase.treatmentPlans;
    _checkInsByStudent[_studentCase.studentName] = _studentCase.checkIns;
    _reflectionsByStudent[_studentCase.studentName] = _studentCase.reflections;
    for (final demo in _demoStudents) {
      _appointmentsByStudent[demo.studentName] = demo.appointments;
      _treatmentsByStudent[demo.studentName] = demo.treatmentPlans;
      _checkInsByStudent[demo.studentName] = demo.checkIns;
      _reflectionsByStudent[demo.studentName] = demo.reflections;
    }
    _loadSavedRole();
  }

  Future<void> _loadSavedRole() async {
    final prefs = await SharedPreferences.getInstance();
    final rawRole = prefs.getString('kaia_active_role');

    if (!mounted) return;

    setState(() {
      if (rawRole == AppRole.professional.name) {
        _activeRole = AppRole.professional;
      } else if (rawRole == AppRole.student.name) {
        _activeRole = AppRole.student;
      }
      _loadingRole = false;
    });

    _configureRealtimePolling();
  }

  Future<void> _setRole(AppRole role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('kaia_active_role', role.name);
    if (!mounted) return;
    setState(() {
      _activeRole = role;
    });
    _configureRealtimePolling();
  }

  Future<void> _logoutRole() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('kaia_active_role');
    if (!mounted) return;
    setState(() {
      _activeRole = null;
    });
    _configureRealtimePolling();
  }

  List<StudentCase> get _professionalStudents {
    final students = [_studentCase, ..._demoStudents];

    final withAppointments = students.map((student) {
      final appointments =
          _appointmentsByStudent[student.studentName] ?? student.appointments;
      final treatmentPlans =
          _treatmentsByStudent[student.studentName] ?? student.treatmentPlans;
      final checkIns =
          _checkInsByStudent[student.studentName] ?? student.checkIns;
      final reflections =
          _reflectionsByStudent[student.studentName] ?? student.reflections;
      return student.copyWith(
        checkIns: checkIns,
        reflections: reflections,
        appointments: appointments,
        treatmentPlans: treatmentPlans,
      );
    }).toList();

    withAppointments.sort((a, b) {
      final riskCompare = b.riskLevel.index.compareTo(a.riskLevel.index);
      if (riskCompare != 0) return riskCompare;

      final dateA = a.latestCheckIn?.date;
      final dateB = b.latestCheckIn?.date;
      if (dateA == null && dateB == null) {
        return a.studentName.compareTo(b.studentName);
      }
      if (dateA == null) return 1;
      if (dateB == null) return -1;
      return dateB.compareTo(dateA);
    });

    return withAppointments;
  }

  bool get _checkInCompletedToday {
    final checkIn = _studentCase.latestCheckIn;
    if (checkIn == null) return false;
    final now = DateTime.now();
    return checkIn.date.year == now.year &&
        checkIn.date.month == now.month &&
        checkIn.date.day == now.day;
  }

  void _onCheckInCompleted(DailyCheckIn checkIn) {
    final updatedCheckIns = [..._studentCase.checkIns, checkIn];
    setState(() {
      _studentCase = _studentCase.copyWith(
        checkIns: updatedCheckIns,
        riskLevel: _mergeRisk(_studentCase.riskLevel, checkIn.riskLevel),
      );
      _appointmentsByStudent[_studentCase.studentName] =
          _studentCase.appointments;
      _treatmentsByStudent[_studentCase.studentName] =
          _studentCase.treatmentPlans;
      _checkInsByStudent[_studentCase.studentName] = updatedCheckIns;
      _reflectionsByStudent[_studentCase.studentName] = _studentCase.reflections;
    });

    unawaited(
      _syncStudentCheckInsToBackend(
        studentName: _studentCase.studentName,
        checkIns: updatedCheckIns,
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'KAIA: Gracias por tu check-in. Ya lo guardé y seguimos acompañándote.',
        ),
      ),
    );
  }

  void _onReflectionSubmitted(ReflectionAnalysis analysis) {
    final updatedReflections = [
      ..._studentCase.reflections,
      analysis.reflection,
    ];
    setState(() {
      _studentCase = _studentCase.copyWith(
        reflections: updatedReflections,
        alerts: [..._studentCase.alerts, ...analysis.newAlerts],
        riskLevel: _mergeRisk(_studentCase.riskLevel, analysis.caseRisk),
      );
      _appointmentsByStudent[_studentCase.studentName] =
          _studentCase.appointments;
      _treatmentsByStudent[_studentCase.studentName] =
          _studentCase.treatmentPlans;
      _checkInsByStudent[_studentCase.studentName] = _studentCase.checkIns;
      _reflectionsByStudent[_studentCase.studentName] = updatedReflections;
    });

    unawaited(
      _syncStudentReflectionsToBackend(
        studentName: _studentCase.studentName,
        reflections: updatedReflections,
      ),
    );
  }

  Future<void> _assignTreatmentPlan(
    TreatmentPlan plan,
    String studentName,
  ) async {
    final current =
        _treatmentsByStudent[studentName] ?? const <TreatmentPlan>[];
    final updated = [
      plan,
      ...current.where((existing) => existing.id != plan.id),
    ];

    setState(() {
      _treatmentsByStudent[studentName] = updated;
      if (studentName == _studentCase.studentName) {
        _studentCase = _studentCase.copyWith(treatmentPlans: updated);
      }
    });

    await _syncTreatmentPlansToBackend(
      studentName: studentName,
      plans: updated,
    );
    unawaited(
      _publishTreatmentEvent(
        role: 'student',
        userId: studentName,
        title: 'Nuevo plan de tratamiento',
        detail: 'Tu profesional agrego actividades para trabajar esta semana.',
      ),
    );
  }

  Future<void> _toggleTreatmentTask({
    required String studentName,
    required String planId,
    required String taskId,
    required bool completed,
  }) async {
    final current =
        _treatmentsByStudent[studentName] ?? const <TreatmentPlan>[];
    final updated = current.map((plan) {
      if (plan.id != planId) return plan;
      final tasks = plan.tasks.map((task) {
        if (task.id != taskId) return task;
        return task.copyWith(
          completed: completed,
          completedAt: completed ? DateTime.now() : null,
        );
      }).toList();
      return plan.copyWith(tasks: tasks);
    }).toList();

    setState(() {
      _treatmentsByStudent[studentName] = updated;
      if (studentName == _studentCase.studentName) {
        _studentCase = _studentCase.copyWith(treatmentPlans: updated);
      }
    });

    await _syncTreatmentPlansToBackend(
      studentName: studentName,
      plans: updated,
    );
    unawaited(
      _publishTreatmentEvent(
        role: 'professional',
        userId: 'default-professional',
        title: 'Actualizacion de tratamiento',
        detail: completed
            ? '$studentName marco una actividad como realizada.'
            : '$studentName marco una actividad como pendiente.',
      ),
    );
  }

  void _onStudentAppointmentResponse(AppointmentStudentResponse response) {
    final currentStudentName = _studentCase.studentName;
    final current =
        _appointmentsByStudent[currentStudentName] ?? _studentCase.appointments;

    ProfessionalAppointment? previous;
    final updated = current.map((appointment) {
      if (appointment.id != response.appointmentId) return appointment;
      previous = appointment;
      if (appointment.status == response.status) {
        return appointment;
      }
      return appointment.copyWith(
        status: response.status,
        statusHistory: [
          ...appointment.statusHistory,
          AppointmentStatusEvent(
            status: response.status,
            actor: AppointmentActor.student,
            changedAt: DateTime.now(),
            note: response.status == AppointmentStatus.confirmed
                ? 'El alumno confirmo disponibilidad para la cita.'
                : 'El alumno indico que no puede asistir en la fecha propuesta.',
          ),
        ],
      );
    }).toList()..sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));

    final didChangeStatus =
        previous != null && previous!.status != response.status;

    final updatedAlerts = didChangeStatus
        ? [
            ..._studentCase.alerts,
            ProfessionalAlert(
              title: response.status == AppointmentStatus.confirmed
                  ? 'Cita confirmada por el alumno'
                  : 'Cita rechazada por el alumno',
              detail: response.status == AppointmentStatus.confirmed
                  ? 'El alumno acepto la cita de seguimiento.'
                  : 'El alumno no puede asistir; se requiere reprogramacion.',
              createdAt: DateTime.now(),
            ),
          ]
        : _studentCase.alerts;

    setState(() {
      _appointmentsByStudent[currentStudentName] = updated;
      _studentCase = _studentCase.copyWith(
        appointments: updated,
        alerts: updatedAlerts,
      );
      if (didChangeStatus) {
        _professionalNotifications.insert(
          0,
          ProfessionalAgendaNotification(
            title: response.status == AppointmentStatus.confirmed
                ? 'Alumno confirmo cita'
                : 'Alumno rechazo cita',
            detail: response.status == AppointmentStatus.confirmed
                ? '$currentStudentName confirmo la cita programada.'
                : '$currentStudentName no puede en la fecha propuesta.',
            createdAt: DateTime.now(),
            status: response.status,
          ),
        );
      }
    });

    if (didChangeStatus) {
      unawaited(
        _syncStudentAppointmentsToBackend(
          studentName: currentStudentName,
          appointments: updated,
        ),
      );
      unawaited(
        _pushBridgeService.notifyAppointmentResponse(
          userId: 'default-professional',
          studentName: currentStudentName,
          appointmentId: response.appointmentId,
          status: response.status,
        ),
      );
    }
  }

  Future<AppointmentScheduleResult> _scheduleAppointment(
    AppointmentRequest request,
  ) async {
    final start = request.scheduledFor;
    final end = start.add(Duration(minutes: request.durationMinutes));

    for (final student in _professionalStudents) {
      for (final appointment in student.appointments) {
        if (appointment.status == AppointmentStatus.declined) {
          continue;
        }
        final apptStart = appointment.scheduledFor;
        final apptEnd = appointment.endAt;
        final overlaps = start.isBefore(apptEnd) && end.isAfter(apptStart);

        if (overlaps) {
          final hh = apptStart.hour.toString().padLeft(2, '0');
          final mm = apptStart.minute.toString().padLeft(2, '0');
          return AppointmentScheduleResult(
            ok: false,
            message:
                'Horario ocupado. Ya hay una cita con ${student.studentName} a las $hh:$mm.',
          );
        }
      }
    }

    final appointment = ProfessionalAppointment(
      id: '${request.studentName}-${DateTime.now().microsecondsSinceEpoch}',
      scheduledFor: request.scheduledFor,
      durationMinutes: request.durationMinutes,
      reason: request.reason,
      createdAt: DateTime.now(),
      status: AppointmentStatus.pending,
      statusHistory: [
        AppointmentStatusEvent(
          status: AppointmentStatus.pending,
          actor: AppointmentActor.professional,
          changedAt: DateTime.now(),
          note: 'Cita creada con motivo clinico: ${request.reason}',
        ),
      ],
    );

    final current = _appointmentsByStudent[request.studentName] ?? const [];
    final updatedAppointments = [...current, appointment]
      ..sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));

    setState(() {
      _appointmentsByStudent[request.studentName] = updatedAppointments;
      if (request.studentName == _studentCase.studentName) {
        _studentCase = _studentCase.copyWith(appointments: updatedAppointments);
      }
    });

    await _notificationService.showNewAppointmentNotification(
      studentName: request.studentName,
      startsAt: request.scheduledFor,
      clinicalReason: request.reason,
    );

    unawaited(
      _syncStudentAppointmentsToBackend(
        studentName: request.studentName,
        appointments: updatedAppointments,
      ),
    );

    unawaited(
      _pushBridgeService.notifyAppointmentCreated(
        userId: request.studentName,
        appointmentId: appointment.id,
        startsAt: request.scheduledFor,
        reason: request.reason,
      ),
    );

    return const AppointmentScheduleResult(
      ok: true,
      message:
          'Cita agendada en estado pendiente. Se envio notificacion al alumno con el motivo clinico.',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingRole) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_activeRole == null) {
      return KaiaLoginScreen(
        onLoginAsStudent: () => _setRole(AppRole.student),
        onLoginAsProfessional: () => _setRole(AppRole.professional),
      );
    }

    final isStudent = _activeRole == AppRole.student;

    // Student: daily check-in gate
    if (isStudent && !_checkInCompletedToday) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('KAIA · Check-in diario'),
          actions: [
            IconButton(
              tooltip: widget.isDarkMode ? 'Modo claro' : 'Modo oscuro',
              onPressed: widget.onToggleThemeMode,
              icon: Icon(
                widget.isDarkMode
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
              ),
            ),
            IconButton(
              tooltip: 'Cambiar perfil',
              onPressed: _logoutRole,
              icon: const Icon(Icons.logout_rounded),
            ),
          ],
        ),
        body: DailyCheckInScreen(onCompleted: _onCheckInCompleted),
      );
    }

    // Student: main home (full Scaffold owned by StudentAiHome)
    if (isStudent) {
      return StudentAiHome(
        studentCase: _studentCase,
        onReflectionSubmitted: _onReflectionSubmitted,
        onAppointmentResponse: _onStudentAppointmentResponse,
        onToggleTreatmentTask: (planId, taskId, completed) =>
            _toggleTreatmentTask(
              studentName: _studentCase.studentName,
              planId: planId,
              taskId: taskId,
              completed: completed,
            ),
        isDarkMode: widget.isDarkMode,
        onToggleThemeMode: widget.onToggleThemeMode,
        onLogout: _logoutRole,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard Profesional'),
        actions: [
          IconButton(
            tooltip: widget.isDarkMode ? 'Modo claro' : 'Modo oscuro',
            onPressed: widget.onToggleThemeMode,
            icon: Icon(
              widget.isDarkMode
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
            ),
          ),
          IconButton(
            tooltip: 'Cambiar perfil',
            onPressed: _logoutRole,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: ProfessionalDashboard(
        students: _professionalStudents,
        onScheduleAppointment: _scheduleAppointment,
        notifications: _professionalNotifications,
        onAssignTreatmentPlan: _assignTreatmentPlan,
      ),
    );
  }

  RiskLevel _mergeRisk(RiskLevel current, RiskLevel incoming) {
    if (incoming.index > current.index) return incoming;
    return current;
  }

  void _configureRealtimePolling() {
    _realtimePollTimer?.cancel();
    _realtimePollTimer = null;

    if (_activeRole == null) return;

    unawaited(_pollRealtimeEventsOnce());
    unawaited(_syncAppointmentsFromBackendOnce());
    _realtimePollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(_pollRealtimeEventsOnce());
      unawaited(_syncAppointmentsFromBackendOnce());
    });
  }

  Future<void> _pollRealtimeEventsOnce() async {
    final target = _pollingTarget;
    if (target == null) return;

    final result = await _pushBridgeService.pollEvents(
      role: target.$1,
      userId: target.$2,
      afterEventId: _lastRealtimeEventId,
    );

    if (!mounted) return;

    if (result.latestEventId > _lastRealtimeEventId) {
      _lastRealtimeEventId = result.latestEventId;
    }

    for (final event in result.events) {
      await _notificationService.showRealtimeEventNotification(
        eventId: event.id,
        title: event.title,
        detail: event.detail,
      );
    }
  }

  Future<void> _syncStudentAppointmentsToBackend({
    required String studentName,
    required List<ProfessionalAppointment> appointments,
  }) async {
    await _pushBridgeService.syncStudentAppointments(
      studentName: studentName,
      appointments: appointments.map(_appointmentToJson).toList(),
    );
  }

  Future<void> _syncTreatmentPlansToBackend({
    required String studentName,
    required List<TreatmentPlan> plans,
  }) async {
    await _pushBridgeService.syncStudentTreatmentPlans(
      studentName: studentName,
      plans: plans.map(_treatmentPlanToJson).toList(),
    );
  }

  Future<void> _syncStudentCheckInsToBackend({
    required String studentName,
    required List<DailyCheckIn> checkIns,
  }) async {
    await _pushBridgeService.syncStudentCheckIns(
      studentName: studentName,
      checkIns: checkIns.map(_checkInToJson).toList(),
    );
  }

  Future<void> _syncStudentReflectionsToBackend({
    required String studentName,
    required List<StudentReflection> reflections,
  }) async {
    await _pushBridgeService.syncStudentReflections(
      studentName: studentName,
      reflections: reflections.map(_reflectionToJson).toList(),
    );
  }

  Future<void> _publishTreatmentEvent({
    required String role,
    required String userId,
    required String title,
    required String detail,
  }) async {
    await _pushBridgeService._post('/events/publish', {
      'role': role,
      'userId': userId,
      'title': title,
      'detail': detail,
      'type': 'treatment_update',
    });
  }

  Future<void> _syncAppointmentsFromBackendOnce() async {
    if (_activeRole == AppRole.student) {
      final rawList = await _pushBridgeService.fetchAppointmentsByStudent(
        studentName: _studentCase.studentName,
      );
      final rawPlans = await _pushBridgeService.fetchTreatmentPlansByStudent(
        studentName: _studentCase.studentName,
      );
      final rawCheckIns = await _pushBridgeService.fetchCheckInsByStudent(
        studentName: _studentCase.studentName,
      );
      final rawReflections = await _pushBridgeService.fetchReflectionsByStudent(
        studentName: _studentCase.studentName,
      );
      final parsed =
          rawList
              .map(_appointmentFromJson)
              .whereType<ProfessionalAppointment>()
              .toList()
            ..sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));
      final parsedPlans = rawPlans
          .map(_treatmentPlanFromJson)
          .whereType<TreatmentPlan>()
          .toList();
      final parsedCheckIns = rawCheckIns
          .map(_checkInFromJson)
          .whereType<DailyCheckIn>()
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      final parsedReflections = rawReflections
          .map(_reflectionFromJson)
          .whereType<StudentReflection>()
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final effectiveCheckIns = parsedCheckIns.isEmpty
          ? _studentCase.checkIns
          : parsedCheckIns;
      final effectiveReflections = parsedReflections.isEmpty
          ? _studentCase.reflections
          : parsedReflections;

      if (!mounted) return;
      setState(() {
        _appointmentsByStudent[_studentCase.studentName] = parsed;
        _treatmentsByStudent[_studentCase.studentName] = parsedPlans;
        _checkInsByStudent[_studentCase.studentName] = effectiveCheckIns;
        _reflectionsByStudent[_studentCase.studentName] = effectiveReflections;
        _studentCase = _studentCase.copyWith(
          checkIns: effectiveCheckIns,
          reflections: effectiveReflections,
          appointments: parsed,
          treatmentPlans: parsedPlans,
        );
      });
      return;
    }

    if (_activeRole == AppRole.professional) {
      final all = await _pushBridgeService.fetchAllAppointments();
      final allPlans = await _pushBridgeService.fetchAllTreatmentPlans();
      final allCheckIns = await _pushBridgeService.fetchAllCheckIns();
      final allReflections = await _pushBridgeService.fetchAllReflections();
      if (!mounted) return;
      setState(() {
        all.forEach((studentName, rawAppointments) {
          final parsed =
              rawAppointments
                  .map(_appointmentFromJson)
                  .whereType<ProfessionalAppointment>()
                  .toList()
                ..sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));
          _appointmentsByStudent[studentName] = parsed;
          if (studentName == _studentCase.studentName) {
            _studentCase = _studentCase.copyWith(appointments: parsed);
          }
        });
        allPlans.forEach((studentName, rawPlans) {
          final parsedPlans = rawPlans
              .map(_treatmentPlanFromJson)
              .whereType<TreatmentPlan>()
              .toList();
          _treatmentsByStudent[studentName] = parsedPlans;
          if (studentName == _studentCase.studentName) {
            _studentCase = _studentCase.copyWith(treatmentPlans: parsedPlans);
          }
        });
        allCheckIns.forEach((studentName, rawCheckIns) {
          final parsedCheckIns = rawCheckIns
              .map(_checkInFromJson)
              .whereType<DailyCheckIn>()
              .toList()
            ..sort((a, b) => a.date.compareTo(b.date));
          _checkInsByStudent[studentName] = parsedCheckIns;
          if (studentName == _studentCase.studentName) {
            _studentCase = _studentCase.copyWith(checkIns: parsedCheckIns);
          }
        });
        allReflections.forEach((studentName, rawReflections) {
          final parsedReflections = rawReflections
              .map(_reflectionFromJson)
              .whereType<StudentReflection>()
              .toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          _reflectionsByStudent[studentName] = parsedReflections;
          if (studentName == _studentCase.studentName) {
            _studentCase = _studentCase.copyWith(
              reflections: parsedReflections,
            );
          }
        });
      });
    }
  }

  Map<String, dynamic> _appointmentToJson(ProfessionalAppointment appointment) {
    return {
      'id': appointment.id,
      'scheduledFor': appointment.scheduledFor.toIso8601String(),
      'durationMinutes': appointment.durationMinutes,
      'reason': appointment.reason,
      'createdAt': appointment.createdAt.toIso8601String(),
      'status': appointment.status.name,
      'statusHistory': appointment.statusHistory
          .map(
            (event) => {
              'status': event.status.name,
              'actor': event.actor.name,
              'changedAt': event.changedAt.toIso8601String(),
              'note': event.note,
            },
          )
          .toList(),
    };
  }

  ProfessionalAppointment? _appointmentFromJson(Map<String, dynamic> raw) {
    final id = (raw['id'] ?? '').toString().trim();
    final reason = (raw['reason'] ?? '').toString().trim();
    final scheduledForRaw = (raw['scheduledFor'] ?? '').toString().trim();
    if (id.isEmpty || reason.isEmpty || scheduledForRaw.isEmpty) return null;

    final scheduledFor = DateTime.tryParse(scheduledForRaw);
    final createdAt = DateTime.tryParse((raw['createdAt'] ?? '').toString());
    if (scheduledFor == null || createdAt == null) return null;

    final status = _statusFromString((raw['status'] ?? '').toString());
    final rawHistory = raw['statusHistory'];
    final history = rawHistory is List
        ? rawHistory.whereType<Map<String, dynamic>>().map((eventRaw) {
            final changedAt =
                DateTime.tryParse((eventRaw['changedAt'] ?? '').toString()) ??
                DateTime.now();
            return AppointmentStatusEvent(
              status: _statusFromString((eventRaw['status'] ?? '').toString()),
              actor: _actorFromString((eventRaw['actor'] ?? '').toString()),
              changedAt: changedAt,
              note: (eventRaw['note'] ?? '').toString(),
            );
          }).toList()
        : <AppointmentStatusEvent>[];

    return ProfessionalAppointment(
      id: id,
      scheduledFor: scheduledFor,
      durationMinutes: (raw['durationMinutes'] is num)
          ? (raw['durationMinutes'] as num).toInt()
          : 45,
      reason: reason,
      createdAt: createdAt,
      status: status,
      statusHistory: history,
    );
  }

  AppointmentStatus _statusFromString(String value) {
    switch (value.trim().toLowerCase()) {
      case 'confirmed':
        return AppointmentStatus.confirmed;
      case 'declined':
        return AppointmentStatus.declined;
      default:
        return AppointmentStatus.pending;
    }
  }

  AppointmentActor _actorFromString(String value) {
    switch (value.trim().toLowerCase()) {
      case 'professional':
        return AppointmentActor.professional;
      case 'student':
        return AppointmentActor.student;
      default:
        return AppointmentActor.system;
    }
  }

  Map<String, dynamic> _treatmentPlanToJson(TreatmentPlan plan) {
    return {
      'id': plan.id,
      'title': plan.title,
      'summary': plan.summary,
      'createdAt': plan.createdAt.toIso8601String(),
      'assignedBy': plan.assignedBy,
      'tasks': plan.tasks
          .map(
            (task) => {
              'id': task.id,
              'title': task.title,
              'completed': task.completed,
              'completedAt': task.completedAt?.toIso8601String(),
            },
          )
          .toList(),
    };
  }

  TreatmentPlan? _treatmentPlanFromJson(Map<String, dynamic> raw) {
    final id = (raw['id'] ?? '').toString().trim();
    final title = (raw['title'] ?? '').toString().trim();
    if (id.isEmpty || title.isEmpty) return null;
    final createdAt =
        DateTime.tryParse((raw['createdAt'] ?? '').toString()) ??
        DateTime.now();
    final rawTasks = raw['tasks'];
    final tasks = rawTasks is List
        ? rawTasks
              .whereType<Map<String, dynamic>>()
              .map((taskRaw) {
                return TreatmentTask(
                  id: (taskRaw['id'] ?? '').toString(),
                  title: (taskRaw['title'] ?? '').toString(),
                  completed: taskRaw['completed'] == true,
                  completedAt: taskRaw['completedAt'] == null
                      ? null
                      : DateTime.tryParse(taskRaw['completedAt'].toString()),
                );
              })
              .where((task) => task.id.isNotEmpty && task.title.isNotEmpty)
              .toList()
        : <TreatmentTask>[];

    return TreatmentPlan(
      id: id,
      title: title,
      summary: (raw['summary'] ?? '').toString(),
      createdAt: createdAt,
      assignedBy: (raw['assignedBy'] ?? 'Profesional KAIA').toString(),
      tasks: tasks,
    );
  }

  Map<String, dynamic> _checkInToJson(DailyCheckIn checkIn) {
    return {
      'date': checkIn.date.toIso8601String(),
      'answers': checkIn.answers,
      'wellbeingScore': checkIn.wellbeingScore,
      'riskLevel': checkIn.riskLevel.name,
      'summary': checkIn.summary,
      'who5Percent': checkIn.who5Percent,
      'phq2Score': checkIn.phq2Score,
      'gad2Score': checkIn.gad2Score,
    };
  }

  DailyCheckIn? _checkInFromJson(Map<String, dynamic> raw) {
    final dateRaw = (raw['date'] ?? '').toString().trim();
    final date = DateTime.tryParse(dateRaw);
    if (date == null) return null;

    final answersRaw = raw['answers'];
    final answers = <int, int>{};
    if (answersRaw is Map) {
      answersRaw.forEach((key, value) {
        final i = int.tryParse(key.toString());
        final v = int.tryParse(value.toString());
        if (i != null && v != null) {
          answers[i] = v;
        }
      });
    }

    return DailyCheckIn(
      date: date,
      answers: answers,
      wellbeingScore: (raw['wellbeingScore'] is num)
          ? (raw['wellbeingScore'] as num).toInt()
          : 0,
      riskLevel: _riskLevelFromString((raw['riskLevel'] ?? '').toString()),
      summary: (raw['summary'] ?? '').toString(),
      who5Percent: (raw['who5Percent'] is num)
          ? (raw['who5Percent'] as num).toInt()
          : 0,
      phq2Score: (raw['phq2Score'] is num)
          ? (raw['phq2Score'] as num).toInt()
          : 0,
      gad2Score: (raw['gad2Score'] is num)
          ? (raw['gad2Score'] as num).toInt()
          : 0,
    );
  }

  Map<String, dynamic> _reflectionToJson(StudentReflection reflection) {
    return {
      'text': reflection.text,
      'createdAt': reflection.createdAt.toIso8601String(),
      'patterns': reflection.patterns,
      'interpretation': reflection.interpretation,
      'detectedFindings': reflection.detectedFindings,
      'rationale': reflection.rationale,
      'evidenceTerms': reflection.evidenceTerms,
      'reasoningSummary': reflection.reasoningSummary,
      'source': reflection.source,
      'detectedRisk': reflection.detectedRisk.name,
    };
  }

  StudentReflection? _reflectionFromJson(Map<String, dynamic> raw) {
    final text = (raw['text'] ?? '').toString().trim();
    final createdAtRaw = (raw['createdAt'] ?? '').toString().trim();
    final createdAt = DateTime.tryParse(createdAtRaw);
    if (text.isEmpty || createdAt == null) return null;

    List<String> listOf(dynamic value) {
      if (value is! List) return const [];
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }

    return StudentReflection(
      text: text,
      createdAt: createdAt,
      patterns: listOf(raw['patterns']),
      interpretation: (raw['interpretation'] ?? '').toString(),
      detectedFindings: listOf(raw['detectedFindings']),
      rationale: (raw['rationale'] ?? '').toString(),
      evidenceTerms: listOf(raw['evidenceTerms']),
      reasoningSummary: (raw['reasoningSummary'] ?? '').toString(),
      source: (raw['source'] ?? '').toString(),
      detectedRisk: _riskLevelFromString((raw['detectedRisk'] ?? '').toString()),
    );
  }

  RiskLevel _riskLevelFromString(String value) {
    switch (value.trim().toLowerCase()) {
      case 'high':
        return RiskLevel.high;
      case 'medium':
        return RiskLevel.medium;
      default:
        return RiskLevel.low;
    }
  }

  (String, String)? get _pollingTarget {
    if (_activeRole == AppRole.student) {
      return ('student', _studentCase.studentName);
    }
    if (_activeRole == AppRole.professional) {
      return ('professional', 'default-professional');
    }
    return null;
  }

  @override
  void dispose() {
    _realtimePollTimer?.cancel();
    super.dispose();
  }
}

class _KaiaMessageCard extends StatefulWidget {
  final String message;

  const _KaiaMessageCard({required this.message});

  @override
  State<_KaiaMessageCard> createState() => _KaiaMessageCardState();
}

class _KaiaMessageCardState extends State<_KaiaMessageCard>
  with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  late final AnimationController _breathController;
  late final Animation<double> _breath;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _breath = Tween<double>(
      begin: 0.985,
      end: 1.015,
    ).animate(
      CurvedAnimation(parent: _breathController, curve: Curves.easeInOut),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _breathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF3EEFF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.purple.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                height: 150,
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: 0.95,
                    child: ScaleTransition(
                      scale: _breath,
                      child: Image.asset(
                        'assets/logo/kaia_character_clean.png',
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(
                            Icons.psychology_rounded,
                            size: 60,
                            color: Color(0xFF7C3AED),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.78),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'KAIA: ${widget.message}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'SF Pro Text',
                    color: Color(0xFF4C1D95),
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Widget de fade-in con delay para animaciones de aparición ──────────────
class _FadeInCard extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const _FadeInCard({required this.child, required this.delay});

  @override
  State<_FadeInCard> createState() => _FadeInCardState();
}

class _FadeInCardState extends State<_FadeInCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(_anim),
        child: widget.child,
      ),
    );
  }
}

class RoleAccessScreen extends StatelessWidget {
  final ValueChanged<AppRole> onRoleSelected;

  const RoleAccessScreen({super.key, required this.onRoleSelected});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Ingresa a KAIA',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.purple[900],
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Selecciona tu perfil para abrir la experiencia correcta.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[700], fontSize: 15),
                  ),
                  const SizedBox(height: 28),
                  ElevatedButton.icon(
                    onPressed: () => onRoleSelected(AppRole.student),
                    icon: const Icon(Icons.psychology_outlined),
                    label: const Text('Entrar como Alumno'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => onRoleSelected(AppRole.professional),
                    icon: const Icon(Icons.monitor_heart_outlined),
                    label: const Text('Entrar como Profesional'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DailyCheckInScreen extends StatefulWidget {
  final ValueChanged<DailyCheckIn> onCompleted;

  const DailyCheckInScreen({super.key, required this.onCompleted});

  @override
  State<DailyCheckInScreen> createState() => _DailyCheckInScreenState();
}

class _DailyCheckInScreenState extends State<DailyCheckInScreen> {
  static const List<_CheckInItem> _questions = [
    _CheckInItem(
      id: 'who5_1',
      scale: ClinicalScale.who5,
      question: 'Me he sentido alegre y de buen ánimo.',
    ),
    _CheckInItem(
      id: 'who5_2',
      scale: ClinicalScale.who5,
      question: 'Me he sentido calmado y relajado.',
    ),
    _CheckInItem(
      id: 'who5_3',
      scale: ClinicalScale.who5,
      question: 'Me he sentido activo y con energía.',
    ),
    _CheckInItem(
      id: 'who5_4',
      scale: ClinicalScale.who5,
      question: 'Me desperté sintiéndome fresco y descansado.',
    ),
    _CheckInItem(
      id: 'who5_5',
      scale: ClinicalScale.who5,
      question: 'Mi vida diaria ha tenido cosas que me interesan.',
    ),
    _CheckInItem(
      id: 'phq2_1',
      scale: ClinicalScale.phq2,
      question: 'En los últimos 14 días: poco interés o placer al hacer cosas.',
    ),
    _CheckInItem(
      id: 'phq2_2',
      scale: ClinicalScale.phq2,
      question:
          'En los últimos 14 días: sentirse decaído, triste o sin esperanza.',
    ),
    _CheckInItem(
      id: 'gad2_1',
      scale: ClinicalScale.gad2,
      question:
          'En los últimos 14 días: sentirse nervioso, ansioso o al límite.',
    ),
    _CheckInItem(
      id: 'gad2_2',
      scale: ClinicalScale.gad2,
      question: 'En los últimos 14 días: no poder controlar la preocupación.',
    ),
  ];

  int _index = 0;
  final Map<int, int> _answers = {};

  @override
  Widget build(BuildContext context) {
    final progress = (_index + 1) / _questions.length;
    final current = _questions[_index];
    final options = _optionsFor(current.scale);
    final scaleLabel = _labelFor(current.scale);
    final intro = _introFor(current.scale);
    final kaiaPrompt =
        'Estoy contigo en esta pregunta del check-in. Elige la opción que más se parezca a cómo te sentiste.';

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Check-in diario guiado',
            style: TextStyle(
              color: Colors.purple[800],
              fontFamily: 'SF Pro Display',
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Hagamos una pregunta a la vez con WHO-5, PHQ-2 y GAD-2. Toma menos de dos minutos y mantiene el mismo seguimiento clínico.',
            style: TextStyle(
              color: Colors.grey[700],
              fontFamily: 'SF Pro Text',
            ),
          ),
          const SizedBox(height: 12),
          _KaiaMessageCard(message: kaiaPrompt),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(99),
            backgroundColor: Colors.purple[50],
            color: Colors.purple[300],
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '$scaleLabel · Pregunta ${_index + 1} de ${_questions.length}',
                      style: TextStyle(
                        color: Colors.purple[500],
                        fontFamily: 'SF Pro Text',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    intro,
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontFamily: 'SF Pro Text',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    current.question,
                    style: TextStyle(
                      color: Colors.purple[900],
                      fontFamily: 'SF Pro Text',
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...options.map((option) {
                    final score = option.value;
                    final selected = _answers[_index] == score;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => setState(() => _answers[_index] = score),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: selected
                                ? Colors.purple.shade50
                                : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected
                                  ? Colors.purple.shade300
                                  : Colors.purple.shade100,
                              width: selected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  option.label,
                                  style: const TextStyle(
                                    fontFamily: 'SF Pro Text',
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (selected)
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.purple[400],
                                )
                              else
                                Icon(
                                  Icons.radio_button_unchecked,
                                  color: Colors.grey[400],
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (_index > 0)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _index -= 1),
                    child: const Text('Anterior'),
                  ),
                ),
              if (_index > 0) const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _answers.containsKey(_index)
                      ? () {
                          if (_index < _questions.length - 1) {
                            setState(() => _index += 1);
                          } else {
                            widget.onCompleted(_buildCheckIn());
                          }
                        }
                      : null,
                  child: Text(
                    _index == _questions.length - 1 ? 'Finalizar' : 'Siguiente',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  DailyCheckIn _buildCheckIn() {
    final who5Indexes = _indexesFor(ClinicalScale.who5);
    final phq2Indexes = _indexesFor(ClinicalScale.phq2);
    final gad2Indexes = _indexesFor(ClinicalScale.gad2);

    final who5Raw = who5Indexes.fold<int>(
      0,
      (sum, i) => sum + (_answers[i] ?? 0),
    );
    final phq2Raw = phq2Indexes.fold<int>(
      0,
      (sum, i) => sum + (_answers[i] ?? 0),
    );
    final gad2Raw = gad2Indexes.fold<int>(
      0,
      (sum, i) => sum + (_answers[i] ?? 0),
    );

    final who5Percent = (who5Raw * 4).clamp(0, 100);
    final combinedDistress = ((phq2Raw + gad2Raw) / 12 * 100).round();
    final healthScore = (who5Percent * 0.65 + (100 - combinedDistress) * 0.35)
        .round()
        .clamp(0, 100);

    final risk = _riskFromScales(
      who5Percent: who5Percent,
      phq2: phq2Raw,
      gad2: gad2Raw,
    );

    return DailyCheckIn(
      date: DateTime.now(),
      answers: Map<int, int>.from(_answers),
      wellbeingScore: healthScore,
      riskLevel: risk,
      summary: _buildClinicalSummary(risk, who5Percent, phq2Raw, gad2Raw),
      who5Percent: who5Percent,
      phq2Score: phq2Raw,
      gad2Score: gad2Raw,
    );
  }

  List<int> _indexesFor(ClinicalScale scale) {
    final indexes = <int>[];
    for (var i = 0; i < _questions.length; i++) {
      if (_questions[i].scale == scale) {
        indexes.add(i);
      }
    }
    return indexes;
  }

  List<_ScaleOption> _optionsFor(ClinicalScale scale) {
    switch (scale) {
      case ClinicalScale.who5:
        return const [
          _ScaleOption(0, 'Nunca'),
          _ScaleOption(1, 'Rara vez'),
          _ScaleOption(2, 'A veces'),
          _ScaleOption(3, 'Frecuente'),
          _ScaleOption(4, 'Casi siempre'),
          _ScaleOption(5, 'Siempre'),
        ];
      case ClinicalScale.phq2:
      case ClinicalScale.gad2:
        return const [
          _ScaleOption(0, 'Nada'),
          _ScaleOption(1, 'Varios días'),
          _ScaleOption(2, 'Más de la mitad'),
          _ScaleOption(3, 'Casi diario'),
        ];
    }
  }

  RiskLevel _riskFromScales({
    required int who5Percent,
    required int phq2,
    required int gad2,
  }) {
    final thresholdsMet = [
      who5Percent < 50,
      phq2 >= 3,
      gad2 >= 3,
    ].where((met) => met).length;

    if (thresholdsMet == 3) {
      return RiskLevel.high;
    }
    if (thresholdsMet >= 1) {
      return RiskLevel.medium;
    }
    return RiskLevel.low;
  }

  String _labelFor(ClinicalScale scale) {
    switch (scale) {
      case ClinicalScale.who5:
        return 'Bienestar WHO-5';
      case ClinicalScale.phq2:
        return 'Estado de animo PHQ-2';
      case ClinicalScale.gad2:
        return 'Ansiedad GAD-2';
    }
  }

  String _introFor(ClinicalScale scale) {
    switch (scale) {
      case ClinicalScale.who5:
        return 'Para empezar, cuentame como ha estado tu bienestar general durante estos dias.';
      case ClinicalScale.phq2:
        return 'Ahora revisemos rapidamente senales de animo bajo en las ultimas dos semanas.';
      case ClinicalScale.gad2:
        return 'Terminemos con dos preguntas breves sobre ansiedad y preocupacion reciente.';
    }
  }

  String _buildClinicalSummary(
    RiskLevel risk,
    int who5Percent,
    int phq2,
    int gad2,
  ) {
    final base = 'WHO-5: $who5Percent/100, PHQ-2: $phq2/6, GAD-2: $gad2/6.';
    if (risk == RiskLevel.high) {
      return '$base Señales compatibles con malestar alto; se sugiere evaluación profesional prioritaria.';
    }
    if (risk == RiskLevel.medium) {
      return '$base Señales de riesgo moderado; recomendable seguimiento clínico en 24-72h.';
    }
    return '$base Perfil de riesgo bajo en este check-in; mantener seguimiento preventivo.';
  }
}

class StudentAiHome extends StatefulWidget {
  final StudentCase studentCase;
  final ValueChanged<ReflectionAnalysis> onReflectionSubmitted;
  final ValueChanged<AppointmentStudentResponse> onAppointmentResponse;
  final Future<void> Function(String planId, String taskId, bool completed)
  onToggleTreatmentTask;
  final bool isDarkMode;
  final VoidCallback onToggleThemeMode;
  final VoidCallback onLogout;

  const StudentAiHome({
    super.key,
    required this.studentCase,
    required this.onReflectionSubmitted,
    required this.onAppointmentResponse,
    required this.onToggleTreatmentTask,
    required this.isDarkMode,
    required this.onToggleThemeMode,
    required this.onLogout,
  });

  @override
  State<StudentAiHome> createState() => _StudentAiHomeState();
}

class _StudentAiHomeState extends State<StudentAiHome>
    with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _backendController = TextEditingController();
  bool _isSending = false;
  int _tabIndex = 0; // 0=Inicio 1=Progreso 2=Apoyo

  // Glow animation for FAB
  late AnimationController _glowController;
  late Animation<double> _glowAnim;

  static const String _defaultPublicBackendUrl = String.fromEnvironment(
    'AI_BACKEND_URL',
    defaultValue: 'https://mi-app-ai-backend.onrender.com',
  );
  String _backendUrl = const String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: _defaultPublicBackendUrl,
  );
  SensorContext _sensorContext = SensorContext(
    sleepHours: 7.0,
    screenMinutes: 240,
    steps: 5000,
    restingHeartRate: 72,
  );

  @override
  void initState() {
    super.initState();
    _loadChatSettings();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  Future<void> _loadChatSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('wellbeing_backend_url');
    if (!mounted) return;
    setState(() {
      if (savedUrl != null && savedUrl.trim().isNotEmpty) {
        _backendUrl = savedUrl.trim();
      }
      _backendUrl = _resolveBackendUrl(_backendUrl);
      _backendController.text = _backendUrl;
      _sensorContext = SensorContext(
        sleepHours:
            prefs.getDouble('sensor_sleep_hours') ?? _sensorContext.sleepHours,
        screenMinutes:
            prefs.getInt('sensor_screen_minutes') ??
            _sensorContext.screenMinutes,
        steps: prefs.getInt('sensor_steps') ?? _sensorContext.steps,
        restingHeartRate:
            prefs.getInt('sensor_rest_hr') ?? _sensorContext.restingHeartRate,
      );
    });
  }

  Future<void> _saveChatSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wellbeing_backend_url', _backendUrl);
    await prefs.setDouble('sensor_sleep_hours', _sensorContext.sleepHours);
    await prefs.setInt('sensor_screen_minutes', _sensorContext.screenMinutes);
    await prefs.setInt('sensor_steps', _sensorContext.steps);
    await prefs.setInt('sensor_rest_hr', _sensorContext.restingHeartRate);
  }

  @override
  void dispose() {
    _controller.dispose();
    _backendController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    final tabTitles = ['Mi espacio', 'Mi Progreso', 'Apoyo'];

    // Build check-in summaries for the Progreso tab
    final checkInSummaries = widget.studentCase.checkIns.map((c) {
      return CheckInSummary(
        date: c.date,
        wellbeingScore: c.wellbeingScore.toDouble(),
        who5Percent: c.who5Percent.toDouble(),
        phq2Score: c.phq2Score,
        gad2Score: c.gad2Score,
        riskLevel: c.riskLevel.name,
      );
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F3FF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          tabTitles[_tabIndex],
          style: const TextStyle(
            fontFamily: 'SF Pro Display',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF3B1B8F),
          ),
        ),
        actions: [
          // Emergency button — always visible, red heart
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              tooltip: 'Emergencia',
              onPressed: _showEmergencyModal,
              icon: Icon(
                Icons.favorite_rounded,
                color: Colors.red.shade600,
              ),
            ),
          ),
          IconButton(
            tooltip: widget.isDarkMode ? 'Modo claro' : 'Modo oscuro',
            onPressed: widget.onToggleThemeMode,
            icon: Icon(
              widget.isDarkMode
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
              color: const Color(0xFF3B1B8F),
            ),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout_rounded, color: Color(0xFF3B1B8F)),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          _buildHomeTab(),
          MiProgresoBody(checkIns: checkInSummaries),
          const ApoyoBody(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFEDE9FE),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded, color: Color(0xFF6D28D9)),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart_outlined),
            selectedIcon: Icon(Icons.show_chart_rounded, color: Color(0xFF6D28D9)),
            label: 'Progreso',
          ),
          NavigationDestination(
            icon: Icon(Icons.spa_outlined),
            selectedIcon: Icon(Icons.spa_rounded, color: Color(0xFF6D28D9)),
            label: 'Apoyo',
          ),
        ],
      ),
      floatingActionButton:
          (_tabIndex == 0 && !keyboardVisible) ? _buildGlowFAB() : null,
    );
  }

  // ── FAB con animación de glow ──────────────────────────────────────────────
  Widget _buildGlowFAB() {
    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (_, child) {
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C3AED).withOpacity(_glowAnim.value * 0.7),
                blurRadius: 20 + (_glowAnim.value * 12),
                spreadRadius: 2,
              ),
            ],
          ),
          child: child,
        );
      },
      child: FloatingActionButton(
        onPressed: _openChatSettings,
        backgroundColor: const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
        tooltip: 'Ajustes IA',
        child: const Icon(Icons.insights_rounded),
      ),
    );
  }

  // ── Modal emergencia ───────────────────────────────────────────────────────
  void _showEmergencyModal() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.favorite_rounded, color: Colors.red.shade600, size: 28),
                const SizedBox(width: 10),
                const Text(
                  '¿Necesitas apoyo ahora?',
                  style: TextStyle(
                    fontFamily: 'SF Pro Display',
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E1B4B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'No estás solo/a. Hay personas disponibles para escucharte en este momento.',
              style: TextStyle(
                fontFamily: 'SF Pro Text',
                fontSize: 14,
                color: Color(0xFF6B7280),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            _emergencyTile(
              icon: Icons.person_outlined,
              color: const Color(0xFF7C3AED),
              title: 'Tu psicóloga escolar',
              subtitle: 'Agenda una cita desde la pantalla de inicio',
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.phone_rounded, color: Colors.red.shade700),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Línea de la Vida',
                          style: TextStyle(
                            fontFamily: 'SF Pro Display',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: Colors.red.shade800,
                          ),
                        ),
                        Text(
                          '800-911-2000',
                          style: TextStyle(
                            fontFamily: 'SF Pro Display',
                            fontWeight: FontWeight.w800,
                            fontSize: 22,
                            color: Colors.red.shade700,
                          ),
                        ),
                        Text(
                          '24 h · Gratuito · Confidencial',
                          style: TextStyle(
                            fontFamily: 'SF Pro Text',
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emergencyTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.purple.shade100),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'SF Pro Display',
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: 'SF Pro Text',
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Pestaña Inicio (Home) ──────────────────────────────────────────────────
  Widget _buildHomeTab() {
    final latest = widget.studentCase.latestCheckIn;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final pendingAppointments =
        widget.studentCase.appointments
            .where(
              (appointment) => appointment.status == AppointmentStatus.pending,
            )
            .toList()
          ..sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));
    final confirmedAppointments =
        widget.studentCase.appointments
            .where(
              (appointment) =>
                  appointment.status == AppointmentStatus.confirmed,
            )
            .toList()
          ..sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));
    final treatmentPlans = widget.studentCase.treatmentPlans;
    final usingPublicBackend = _effectiveBackendUrl != _backendUrl;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Stack(
        children: [
          Positioned.fill(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 132),
              children: [
                // ── Hero card mejorada ────────────────────────────────────
                _buildHeroCard(latest),
                const SizedBox(height: 12),
                // ── Estado de hoy ─────────────────────────────────────────
                if (latest != null) ...[
                  _buildEstadoDeHoyCard(latest),
                  const SizedBox(height: 12),
                ],
                // ── Citas con fade-in ─────────────────────────────────────
                _FadeInCard(
                  delay: const Duration(milliseconds: 100),
                  child: _studentSection(
                    title: 'Citas',
                    icon: Icons.event_available_outlined,
                    child: _buildAppointmentsContent(
                      pendingAppointments,
                      confirmedAppointments,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // ── Tratamiento con fade-in ───────────────────────────────
                _FadeInCard(
                  delay: const Duration(milliseconds: 200),
                  child: _studentSection(
                    title: 'Tratamiento',
                    icon: Icons.favorite_outline,
                    child: _buildTreatmentContent(treatmentPlans),
                  ),
                ),
                const SizedBox(height: 12),
                // ── Registro personal ─────────────────────────────────────
                _FadeInCard(
                  delay: const Duration(milliseconds: 300),
                  child: _studentSection(
                    title: 'Registro personal',
                    icon: Icons.edit_note_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _KaiaMessageCard(
                          message:
                              'Te escucho. Cuéntame cómo te fue hoy y lo guardo en tu registro.',
                        ),
                        const SizedBox(height: 10),
                        Text(
                          latest == null
                              ? 'Cuando quieras, puedes dejar un comentario breve sobre como te fue hoy.'
                              : latest.summary,
                          style: TextStyle(color: Colors.grey[800]),
                        ),
                        if (usingPublicBackend) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F0FF),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.purple.shade100,
                              ),
                            ),
                            child: Text(
                              'Se uso el backend publico para mantener la conexion activa.',
                              style: TextStyle(
                                color: Colors.purple[900],
                                fontFamily: 'SF Pro Text',
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Chat input bar ─────────────────────────────────────────────
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: EdgeInsets.fromLTRB(16, 8, 16, keyboardInset + 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 2,
                        maxLines: 4,
                        onTapOutside: (_) => FocusScope.of(context).unfocus(),
                        decoration: const InputDecoration(
                          hintText:
                              'Comentario opcional: escribe como te sentiste hoy...',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _isSending
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton.filled(
                            onPressed: _send,
                            icon: const Icon(Icons.insights_outlined),
                          ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero card con gradiente morado vibrante ────────────────────────────────
  Widget _buildHeroCard(DailyCheckIn? latest) {
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Buenos días'
        : now.hour < 18
        ? 'Buenas tardes'
        : 'Buenas noches';
    final name = widget.studentCase.studentName;
    final risk = widget.studentCase.riskLevel;
    final (badgeColor, riskLabel) = switch (risk) {
      RiskLevel.high   => (Colors.red, 'Riesgo alto'),
      RiskLevel.medium => (Colors.orange, 'Riesgo medio'),
      _                => (Colors.green, 'Sin riesgo'),
    };

    final confirmedCount = widget.studentCase.appointments
        .where((a) => a.status == AppointmentStatus.confirmed)
        .length;
    final tasksTotal = widget.studentCase.treatmentPlans
        .expand((p) => p.tasks)
        .length;
    final tasksCompleted = widget.studentCase.treatmentPlans
        .expand((p) => p.tasks)
        .where((t) => t.completed)
        .length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3B1B8F), Color(0xFF7C3AED), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Saludo + badge riesgo
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$greeting,',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontFamily: 'SF Pro Text',
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'SF Pro Display',
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: badgeColor.withOpacity(0.6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 8, color: badgeColor),
                    const SizedBox(width: 5),
                    Text(
                      riskLabel,
                      style: TextStyle(
                        color: badgeColor,
                        fontFamily: 'SF Pro Text',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            latest == null
                ? 'Todavía no registras tu check-in de hoy.'
                : 'Tu check-in de hoy ya quedó registrado. Seguimos acompañando tu proceso.',
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'SF Pro Text',
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _infoChip(
                icon: Icons.calendar_today_outlined,
                label: confirmedCount == 0
                    ? 'Sin citas confirmadas'
                    : '$confirmedCount cita(s) confirmada(s)',
              ),
              _infoChip(
                icon: Icons.task_alt_outlined,
                label: tasksTotal == 0
                    ? 'Sin tareas asignadas'
                    : '$tasksCompleted/$tasksTotal tareas listas',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Estado de hoy con barras de progreso ───────────────────────────────────
  Widget _buildEstadoDeHoyCard(DailyCheckIn c) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.purple.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withOpacity(0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mood_rounded, color: Colors.purple.shade600),
              const SizedBox(width: 8),
              const Text(
                'Estado de hoy',
                style: TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF3B1B8F),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _scoreBar(
            label: 'WHO-5',
            value: c.who5Percent / 100,
            color: const Color(0xFF10B981),
            display: '${c.who5Percent.toStringAsFixed(0)}%',
          ),
          const SizedBox(height: 8),
          _scoreBar(
            label: 'PHQ-2',
            value: (6 - c.phq2Score.clamp(0, 6)) / 6,
            color: const Color(0xFFF59E0B),
            display: '${c.phq2Score}/6',
            invertLabel: true,
          ),
          const SizedBox(height: 8),
          _scoreBar(
            label: 'GAD-2',
            value: (6 - c.gad2Score.clamp(0, 6)) / 6,
            color: const Color(0xFF3B82F6),
            display: '${c.gad2Score}/6',
            invertLabel: true,
          ),
        ],
      ),
    );
  }

  Widget _scoreBar({
    required String label,
    required double value,
    required Color color,
    required String display,
    bool invertLabel = false,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'SF Pro Text',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151),
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              backgroundColor: color.withOpacity(0.12),
              color: color,
              minHeight: 10,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          display,
          style: TextStyle(
            fontFamily: 'SF Pro Text',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  // ── Citas ──────────────────────────────────────────────────────────────────
  Widget _buildAppointmentsContent(
    List<ProfessionalAppointment> pending,
    List<ProfessionalAppointment> confirmed,
  ) {
    if (pending.isEmpty && confirmed.isEmpty) {
      return Text(
        'No tienes citas registradas por ahora.',
        style: TextStyle(color: Colors.grey[700]),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pending.isNotEmpty) ...[
          Text(
            'Pendientes de confirmar',
            style: TextStyle(
              color: Colors.orange[800],
              fontFamily: 'SF Pro Display',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ...pending.map((appointment) {
            final startsAt = _formatDateTime(appointment.scheduledFor);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF5D494)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    startsAt,
                    style: const TextStyle(
                      fontFamily: 'SF Pro Text',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(appointment.reason),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            widget.onAppointmentResponse(
                              AppointmentStudentResponse(
                                appointmentId: appointment.id,
                                status: AppointmentStatus.declined,
                              ),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Avisaste que no puedes asistir en ese horario.',
                                ),
                              ),
                            );
                          },
                          child: const Text('No puedo'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            widget.onAppointmentResponse(
                              AppointmentStudentResponse(
                                appointmentId: appointment.id,
                                status: AppointmentStatus.confirmed,
                              ),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Confirmaste tu disponibilidad para la cita.',
                                ),
                              ),
                            );
                          },
                          child: const Text('Confirmar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
        if (confirmed.isNotEmpty) ...[
          Text(
            'Próximas',
            style: TextStyle(
              color: Colors.green[800],
              fontFamily: 'SF Pro Display',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ...confirmed.take(3).map((appointment) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: Colors.green.shade700,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_formatDateTime(appointment.scheduledFor)} · ${appointment.reason}',
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  // ── Tratamiento ────────────────────────────────────────────────────────────
  Widget _buildTreatmentContent(List<TreatmentPlan> treatmentPlans) {
    if (treatmentPlans.isEmpty) {
      return Text(
        'Tu profesional aún no te ha compartido tareas o seguimiento.',
        style: TextStyle(color: Colors.grey[700]),
      );
    }
    return Column(
      children: treatmentPlans.map((plan) {
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.blue.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                plan.title,
                style: const TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (plan.summary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(plan.summary),
              ],
              const SizedBox(height: 10),
              ...plan.tasks.map((task) {
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: task.completed,
                  title: Text(task.title),
                  subtitle: task.completedAt == null
                      ? null
                      : Text(
                          'Marcada el ${_formatDateTime(task.completedAt!)}',
                        ),
                  onChanged: (value) {
                    widget.onToggleTreatmentTask(
                      plan.id,
                      task.id,
                      value ?? false,
                    );
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                );
              }),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _formatDateTime(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    return '$day/$month/${date.year} $hh:$mm';
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;
    FocusScope.of(context).unfocus();

    setState(() => _isSending = true);

    try {
      final analysis = await SchoolAiEngine.analyzeReflection(
        reflectionText: text,
        currentRisk: widget.studentCase.riskLevel,
        latestCheckIn: widget.studentCase.latestCheckIn,
        recentReflections: widget.studentCase.reflections,
        backendUrl: _effectiveBackendUrl,
        sensorContext: _sensorContext,
      );

      if (!mounted) return;
      _controller.clear();
      widget.onReflectionSubmitted(analysis);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'KAIA: Gracias por tu confianza y por tomarte este tiempo. Tu mensaje quedó guardado.',
          ),
        ),
      );
    } on AiAnalysisException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo analizar el comentario con el backend IA remoto.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Widget _studentSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _infoChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'SF Pro Text',
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openChatSettings() async {
    _backendController.text = _backendUrl;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Conexion analisis IA',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _backendController,
                    decoration: const InputDecoration(
                      hintText: 'https://mi-app-ai-backend.onrender.com',
                      labelText: 'Backend URL',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Sueno: ${_sensorContext.sleepHours.toStringAsFixed(1)} h',
                  ),
                  Slider(
                    value: _sensorContext.sleepHours,
                    min: 3,
                    max: 10,
                    divisions: 14,
                    onChanged: (v) => setModalState(
                      () => _sensorContext = _sensorContext.copyWith(
                        sleepHours: v,
                      ),
                    ),
                  ),
                  Text('Pantalla: ${_sensorContext.screenMinutes} min'),
                  Slider(
                    value: _sensorContext.screenMinutes.toDouble(),
                    min: 30,
                    max: 720,
                    divisions: 23,
                    onChanged: (v) => setModalState(
                      () => _sensorContext = _sensorContext.copyWith(
                        screenMinutes: v.round(),
                      ),
                    ),
                  ),
                  Text('Pasos: ${_sensorContext.steps}'),
                  Slider(
                    value: _sensorContext.steps.toDouble(),
                    min: 0,
                    max: 15000,
                    divisions: 30,
                    onChanged: (v) => setModalState(
                      () => _sensorContext = _sensorContext.copyWith(
                        steps: v.round(),
                      ),
                    ),
                  ),
                  Text('FC reposo: ${_sensorContext.restingHeartRate} bpm'),
                  Slider(
                    value: _sensorContext.restingHeartRate.toDouble(),
                    min: 45,
                    max: 130,
                    divisions: 17,
                    onChanged: (v) => setModalState(
                      () => _sensorContext = _sensorContext.copyWith(
                        restingHeartRate: v.round(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final navigator = Navigator.of(context);
                        final typed = _backendController.text.trim();
                        if (typed.isNotEmpty) {
                          setState(
                            () => _backendUrl = _resolveBackendUrl(typed),
                          );
                        }
                        await _saveChatSettings();
                        if (!mounted) return;
                        navigator.pop();
                      },
                      child: const Text('Guardar'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String get _effectiveBackendUrl {
    return _resolveBackendUrl(_backendUrl);
  }

  String _resolveBackendUrl(String url) {
    if (_isLocalBackendUrl(url)) {
      return _defaultPublicBackendUrl;
    }
    return url;
  }

  bool _isLocalBackendUrl(String url) {
    final normalized = url.toLowerCase();
    return normalized.contains('localhost') || normalized.contains('127.0.0.1');
  }
}

class AppointmentRequest {
  final String studentName;
  final DateTime scheduledFor;
  final int durationMinutes;
  final String reason;

  const AppointmentRequest({
    required this.studentName,
    required this.scheduledFor,
    required this.durationMinutes,
    required this.reason,
  });
}

enum AppointmentStatus { pending, confirmed, declined }

enum AppointmentActor { professional, student, system }

class AppointmentStatusEvent {
  final AppointmentStatus status;
  final AppointmentActor actor;
  final DateTime changedAt;
  final String note;

  const AppointmentStatusEvent({
    required this.status,
    required this.actor,
    required this.changedAt,
    required this.note,
  });
}

class ProfessionalAgendaNotification {
  final String title;
  final String detail;
  final DateTime createdAt;
  final AppointmentStatus status;

  const ProfessionalAgendaNotification({
    required this.title,
    required this.detail,
    required this.createdAt,
    required this.status,
  });
}

class AppointmentStudentResponse {
  final String appointmentId;
  final AppointmentStatus status;

  const AppointmentStudentResponse({
    required this.appointmentId,
    required this.status,
  });
}

class AppointmentScheduleResult {
  final bool ok;
  final String message;

  const AppointmentScheduleResult({required this.ok, required this.message});
}

class ProfessionalDashboard extends StatefulWidget {
  final List<StudentCase> students;
  final Future<AppointmentScheduleResult> Function(AppointmentRequest request)
  onScheduleAppointment;
  final List<ProfessionalAgendaNotification> notifications;
  final Future<void> Function(TreatmentPlan plan, String studentName)
  onAssignTreatmentPlan;

  const ProfessionalDashboard({
    super.key,
    required this.students,
    required this.onScheduleAppointment,
    required this.notifications,
    required this.onAssignTreatmentPlan,
  });

  @override
  State<ProfessionalDashboard> createState() => _ProfessionalDashboardState();
}

class _ProfessionalDashboardState extends State<ProfessionalDashboard> {
  static const int _agendaStartHour = 8;
  static const int _agendaEndHour = 18;
  static const int _slotStepMinutes = 15;
  static const Color _medicalBlue = Color(0xFF0B4A6F);
  static const Color _medicalTeal = Color(0xFF0A7B83);
  static const Color _medicalMint = Color(0xFFE8F7F6);

  String? _selectedStudentName;
  final TextEditingController _reasonController = TextEditingController(
    text: 'Seguimiento clinico preventivo por riesgo detectado.',
  );
  final TextEditingController _treatmentTitleController = TextEditingController(
    text: 'Plan semanal de autocuidado',
  );
  final TextEditingController
  _treatmentSummaryController = TextEditingController(
    text:
        'Pequenas acciones diarias para sostener rutina, descanso y regulacion emocional.',
  );
  final TextEditingController _treatmentTasksController = TextEditingController(
    text:
        'Dormir antes de las 11 pm\nCaminar 15 minutos\nRegistrar una emocion del dia',
  );
  DateTime _selectedDateTime = DateTime.now().add(const Duration(days: 1));
  int _selectedDurationMinutes = 45;
  bool _scheduling = false;
  bool _isUsingAutoSlot = true;
  AppointmentStatus? _agendaStatusFilter;
    final Map<String, _ProfessionalRecord> _recordsByStudent =
      <String, _ProfessionalRecord>{};
    final TextEditingController _contactPhoneController = TextEditingController();
    final TextEditingController _contactEmailController = TextEditingController();
    final TextEditingController _contactGuardianController =
      TextEditingController();
    final TextEditingController _contactEmergencyController =
      TextEditingController();
    final TextEditingController _contactMetaController = TextEditingController();
    final TextEditingController _clinicalContextController =
      TextEditingController();
    final TextEditingController _professionalNoteController =
      TextEditingController();
    final TextEditingController _bitacoraController = TextEditingController();
    String _bitacoraType = 'Seguimiento';
    int? _editingNoteIndex;
    int? _editingBitacoraIndex;
    String? _recordControllersForStudent;

  static const List<int> _heatmapHours = <int>[
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
  ];

  @override
  void initState() {
    super.initState();
    _seedProfessionalRecords();
    if (widget.students.isNotEmpty) {
      _selectedStudentName = widget.students.first.studentName;
    }
    _syncRecordControllersForSelectedStudent(force: true);
    _applySuggestedSlot();
  }

  @override
  void didUpdateWidget(covariant ProfessionalDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final names = widget.students.map((s) => s.studentName).toSet();
    if (_selectedStudentName == null && widget.students.isNotEmpty) {
      _selectedStudentName = widget.students.first.studentName;
    } else if (_selectedStudentName != null &&
        !names.contains(_selectedStudentName)) {
      _selectedStudentName = widget.students.isEmpty
          ? null
          : widget.students.first.studentName;
    }

    if (_isUsingAutoSlot) {
      _applySuggestedSlot();
    }
    _seedProfessionalRecords();
    _syncRecordControllersForSelectedStudent(force: true);
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _treatmentTitleController.dispose();
    _treatmentSummaryController.dispose();
    _treatmentTasksController.dispose();
    _contactPhoneController.dispose();
    _contactEmailController.dispose();
    _contactGuardianController.dispose();
    _contactEmergencyController.dispose();
    _contactMetaController.dispose();
    _clinicalContextController.dispose();
    _professionalNoteController.dispose();
    _bitacoraController.dispose();
    super.dispose();
  }

  void _seedProfessionalRecords() {
    for (final student in widget.students) {
      _recordsByStudent.putIfAbsent(
        student.studentName,
        () => _ProfessionalRecord(
          contact: _PatientContactInfo(
            phone: 'Sin registrar',
            email:
                '${student.studentName.toLowerCase().replaceAll(' ', '.')}@colegio.edu',
            guardianName: 'Tutor de ${student.studentName}',
            emergencyContact: '911 / Enfermeria escolar',
            relevantMeta: 'Grupo escolar sin registrar',
          ),
          clinicalContext:
              'Contexto inicial: seguimiento preventivo de salud mental escolar.',
          notes: const <_ProfessionalNote>[],
          bitacora: const <_BitacoraEntry>[],
        ),
      );
    }
  }

  void _syncRecordControllersForSelectedStudent({bool force = false}) {
    final studentName = _selectedStudentName;
    if (studentName == null) return;
    if (!force && _recordControllersForStudent == studentName) return;

    final record = _recordsByStudent[studentName];
    if (record == null) return;

    _contactPhoneController.text = record.contact.phone;
    _contactEmailController.text = record.contact.email;
    _contactGuardianController.text = record.contact.guardianName;
    _contactEmergencyController.text = record.contact.emergencyContact;
    _contactMetaController.text = record.contact.relevantMeta;
    _clinicalContextController.text = record.clinicalContext;
    _professionalNoteController.clear();
    _bitacoraController.clear();
    _editingNoteIndex = null;
    _editingBitacoraIndex = null;
    _recordControllersForStudent = studentName;
  }

  void _selectStudent(String studentName) {
    setState(() {
      _selectedStudentName = studentName;
    });
    _syncRecordControllersForSelectedStudent(force: true);
  }

  _ProfessionalRecord? get _selectedProfessionalRecord {
    final student = _selectedStudentName;
    if (student == null) return null;
    return _recordsByStudent[student];
  }

  void _saveContactAndContext() {
    final student = _selectedStudentName;
    if (student == null) return;
    final record = _recordsByStudent[student];
    if (record == null) return;

    final updated = record.copyWith(
      contact: record.contact.copyWith(
        phone: _contactPhoneController.text.trim(),
        email: _contactEmailController.text.trim(),
        guardianName: _contactGuardianController.text.trim(),
        emergencyContact: _contactEmergencyController.text.trim(),
        relevantMeta: _contactMetaController.text.trim(),
      ),
      clinicalContext: _clinicalContextController.text.trim(),
      bitacora: [
        _BitacoraEntry(
          id: 'log-${DateTime.now().microsecondsSinceEpoch}',
          type: 'Actualizacion',
          text: 'Se actualizaron datos de contacto y contexto clinico.',
          createdAt: DateTime.now(),
        ),
        ...record.bitacora,
      ],
    );

    setState(() {
      _recordsByStudent[student] = updated;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Expediente actualizado.')),
    );
  }

  void _saveProfessionalNote() {
    final student = _selectedStudentName;
    if (student == null) return;
    final record = _recordsByStudent[student];
    if (record == null) return;

    final text = _professionalNoteController.text.trim();
    if (text.isEmpty) return;

    final notes = [...record.notes];
    if (_editingNoteIndex != null &&
        _editingNoteIndex! >= 0 &&
        _editingNoteIndex! < notes.length) {
      final existing = notes[_editingNoteIndex!];
      notes[_editingNoteIndex!] = existing.copyWith(
        text: text,
        updatedAt: DateTime.now(),
      );
    } else {
      notes.insert(
        0,
        _ProfessionalNote(
          id: 'note-${DateTime.now().microsecondsSinceEpoch}',
          text: text,
          author: 'Profesional KAIA',
          createdAt: DateTime.now(),
        ),
      );
    }

    setState(() {
      _recordsByStudent[student] = record.copyWith(notes: notes);
      _professionalNoteController.clear();
      _editingNoteIndex = null;
    });
  }

  void _beginEditNote(int index, String text) {
    setState(() {
      _editingNoteIndex = index;
      _professionalNoteController.text = text;
    });
  }

  void _deleteNote(int index) {
    final student = _selectedStudentName;
    if (student == null) return;
    final record = _recordsByStudent[student];
    if (record == null) return;
    final notes = [...record.notes];
    if (index < 0 || index >= notes.length) return;
    notes.removeAt(index);
    setState(() {
      _recordsByStudent[student] = record.copyWith(notes: notes);
      if (_editingNoteIndex == index) {
        _editingNoteIndex = null;
        _professionalNoteController.clear();
      }
    });
  }

  void _saveBitacoraEntry() {
    final student = _selectedStudentName;
    if (student == null) return;
    final record = _recordsByStudent[student];
    if (record == null) return;

    final text = _bitacoraController.text.trim();
    if (text.isEmpty) return;

    final entries = [...record.bitacora];
    if (_editingBitacoraIndex != null &&
        _editingBitacoraIndex! >= 0 &&
        _editingBitacoraIndex! < entries.length) {
      final existing = entries[_editingBitacoraIndex!];
      entries[_editingBitacoraIndex!] = existing.copyWith(
        type: _bitacoraType,
        text: text,
        createdAt: DateTime.now(),
      );
    } else {
      entries.insert(
        0,
        _BitacoraEntry(
          id: 'log-${DateTime.now().microsecondsSinceEpoch}',
          type: _bitacoraType,
          text: text,
          createdAt: DateTime.now(),
        ),
      );
    }

    final updated = record.copyWith(bitacora: entries);

    setState(() {
      _recordsByStudent[student] = updated;
      _bitacoraController.clear();
      _editingBitacoraIndex = null;
    });
  }

  void _beginEditBitacora(int index, _BitacoraEntry entry) {
    setState(() {
      _editingBitacoraIndex = index;
      _bitacoraType = entry.type;
      _bitacoraController.text = entry.text;
    });
  }

  void _deleteBitacoraEntry(int index) {
    final student = _selectedStudentName;
    if (student == null) return;
    final record = _recordsByStudent[student];
    if (record == null) return;
    final entries = [...record.bitacora];
    if (index < 0 || index >= entries.length) return;
    entries.removeAt(index);
    setState(() {
      _recordsByStudent[student] = record.copyWith(bitacora: entries);
      if (_editingBitacoraIndex == index) {
        _editingBitacoraIndex = null;
        _bitacoraController.clear();
      }
    });
  }

  StudentCase? get _selectedStudent {
    if (_selectedStudentName == null) return null;
    for (final student in widget.students) {
      if (student.studentName == _selectedStudentName) {
        return student;
      }
    }
    return null;
  }

  List<_AgendaItem> get _agendaItems {
    final items = <_AgendaItem>[];
    for (final student in widget.students) {
      for (final appointment in student.appointments) {
        items.add(_AgendaItem(student: student, appointment: appointment));
      }
    }
    items.sort(
      (a, b) =>
          a.appointment.scheduledFor.compareTo(b.appointment.scheduledFor),
    );
    return items;
  }

  List<_AgendaItem> get _filteredAgendaItems {
    if (_agendaStatusFilter == null) return _agendaItems;
    return _agendaItems
        .where((item) => item.appointment.status == _agendaStatusFilter)
        .toList();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (pickedDate == null) return;

    if (!mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
    );
    if (pickedTime == null) return;

    final merged = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    if (!mounted) return;
    setState(() {
      _selectedDateTime = merged;
      _isUsingAutoSlot = false;
    });
  }

  void _applySuggestedSlot() {
    final suggested = _findNextAvailableSlot(
      from: DateTime.now(),
      durationMinutes: _selectedDurationMinutes,
    );
    setState(() {
      _selectedDateTime = suggested;
      _isUsingAutoSlot = true;
    });
  }

  DateTime _findNextAvailableSlot({
    required DateTime from,
    required int durationMinutes,
  }) {
    DateTime cursor = _roundUpToStep(
      from.add(const Duration(minutes: 30)),
      _slotStepMinutes,
    );

    for (int dayOffset = 0; dayOffset < 30; dayOffset++) {
      final day = DateTime(cursor.year, cursor.month, cursor.day + dayOffset);
      DateTime slot = DateTime(day.year, day.month, day.day, _agendaStartHour);
      if (dayOffset == 0 && cursor.isAfter(slot)) {
        slot = cursor;
      }

      final dayEnd = DateTime(day.year, day.month, day.day, _agendaEndHour);

      while (slot.add(Duration(minutes: durationMinutes)).isBefore(dayEnd) ||
          slot
              .add(Duration(minutes: durationMinutes))
              .isAtSameMomentAs(dayEnd)) {
        if (!_hasOverlap(slot, durationMinutes)) {
          return slot;
        }
        slot = slot.add(const Duration(minutes: _slotStepMinutes));
      }
    }

    return _roundUpToStep(from.add(const Duration(days: 1)), _slotStepMinutes);
  }

  DateTime _roundUpToStep(DateTime dateTime, int stepMinutes) {
    final remainder = dateTime.minute % stepMinutes;
    final needsRound =
        remainder != 0 || dateTime.second != 0 || dateTime.millisecond != 0;
    if (!needsRound) {
      return DateTime(
        dateTime.year,
        dateTime.month,
        dateTime.day,
        dateTime.hour,
        dateTime.minute,
      );
    }

    final delta = stepMinutes - remainder;
    final rounded = dateTime.add(Duration(minutes: delta));
    return DateTime(
      rounded.year,
      rounded.month,
      rounded.day,
      rounded.hour,
      rounded.minute,
    );
  }

  bool _hasOverlap(DateTime candidateStart, int durationMinutes) {
    final candidateEnd = candidateStart.add(Duration(minutes: durationMinutes));
    for (final item in _agendaItems) {
      final start = item.appointment.scheduledFor;
      final end = item.appointment.endAt;
      final overlaps =
          candidateStart.isBefore(end) && candidateEnd.isAfter(start);
      if (overlaps) return true;
    }
    return false;
  }

  Future<void> _scheduleAppointment() async {
    final selectedStudent = _selectedStudent;
    if (selectedStudent == null) return;

    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega un motivo para la cita.')),
      );
      return;
    }

    if (_selectedDateTime.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una fecha y hora futura.')),
      );
      return;
    }

    setState(() => _scheduling = true);
    final result = await widget.onScheduleAppointment(
      AppointmentRequest(
        studentName: selectedStudent.studentName,
        scheduledFor: _selectedDateTime,
        durationMinutes: _selectedDurationMinutes,
        reason: reason,
      ),
    );
    if (!mounted) return;
    setState(() => _scheduling = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _saveTreatmentPlan() async {
    final selectedStudent = _selectedStudent;
    if (selectedStudent == null) return;

    final title = _treatmentTitleController.text.trim();
    final summary = _treatmentSummaryController.text.trim();
    final tasks = _treatmentTasksController.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    if (title.isEmpty || tasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega un titulo y al menos una tarea.')),
      );
      return;
    }

    final plan = TreatmentPlan(
      id: '${selectedStudent.studentName}-${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      summary: summary,
      createdAt: DateTime.now(),
      assignedBy: 'Profesional KAIA',
      tasks: tasks
          .map(
            (task) => TreatmentTask(
              id: '${selectedStudent.studentName}-${task.hashCode}-${DateTime.now().millisecondsSinceEpoch}',
              title: task,
              completed: false,
            ),
          )
          .toList(),
    );

    await widget.onAssignTreatmentPlan(plan, selectedStudent.studentName);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tratamiento asignado al alumno.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedStudent = _selectedStudent;
    final selectedRecord = _selectedProfessionalRecord;
    final alerts =
        selectedStudent?.alerts.reversed.take(5).toList() ??
        const <ProfessionalAlert>[];
    final highRisk = widget.students
        .where((s) => s.riskLevel == RiskLevel.high)
        .length;
    final mediumRisk = widget.students
        .where((s) => s.riskLevel == RiskLevel.medium)
        .length;
    final today = DateTime.now();
    final appointmentsToday = _agendaItems.where((item) {
      final date = item.appointment.scheduledFor;
      return date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
    }).length;
    final pendingCount = _agendaItems
        .where((item) => item.appointment.status == AppointmentStatus.pending)
        .length;
    final confirmedCount = _agendaItems
        .where((item) => item.appointment.status == AppointmentStatus.confirmed)
        .length;
    final declinedCount = _agendaItems
        .where((item) => item.appointment.status == AppointmentStatus.declined)
        .length;
    final withCheckIn = widget.students
        .where((student) => student.latestCheckIn != null)
        .toList();
    final avgWellbeing = withCheckIn.isEmpty
        ? 0
        : (withCheckIn
                      .map((student) => student.latestCheckIn!.wellbeingScore)
                      .reduce((a, b) => a + b) /
                  withCheckIn.length)
              .round();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1180;
        final isTablet = constraints.maxWidth >= 860;

        final kpiRow = Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _kpiTile(
              title: 'Pacientes Activos',
              value: '${widget.students.length}',
              subtitle: 'Casos en seguimiento',
              icon: Icons.groups_2_outlined,
              accent: _medicalBlue,
            ),
            _kpiTile(
              title: 'Riesgo Alto',
              value: '$highRisk',
              subtitle: 'Atencion prioritaria',
              icon: Icons.priority_high_rounded,
              accent: const Color(0xFFB42318),
            ),
            _kpiTile(
              title: 'Indice de Bienestar',
              value: '$avgWellbeing',
              subtitle: 'Promedio WHO-5 / escalas',
              icon: Icons.health_and_safety_outlined,
              accent: _medicalTeal,
            ),
            _kpiTile(
              title: 'Citas Hoy',
              value: '$appointmentsToday',
              subtitle: 'Agenda del dia',
              icon: Icons.today_outlined,
              accent: const Color(0xFF155EEF),
            ),
          ],
        );

        final headerCard = _medicalHeroCard(
          avgWellbeing: avgWellbeing,
          highRisk: highRisk,
          mediumRisk: mediumRisk,
          pendingCount: pendingCount,
          confirmedCount: confirmedCount,
          declinedCount: declinedCount,
          child: kpiRow,
        );

        final loadState = _clinicalLoadState(
          highRisk: highRisk,
          pendingCount: pendingCount,
          appointmentsToday: appointmentsToday,
          avgWellbeing: avgWellbeing,
        );
        final heatmapData = _agendaHeatmapData();
        final criticalStudents = _criticalRanking();

        final loadPanel = _surfaceCard(
          title: 'Semaforo de Carga Clinica',
          subtitle: 'Capacidad operativa y presion asistencial del turno.',
          icon: Icons.traffic_rounded,
          child: _buildLoadCard(loadState),
        );

        final heatmapPanel = _surfaceCard(
          title: 'Heatmap de Agenda',
          subtitle: 'Concentracion de citas por hora (proximos 7 dias).',
          icon: Icons.grid_on_rounded,
          child: _buildAgendaHeatmap(heatmapData),
        );

        final rankingPanel = _surfaceCard(
          title: 'Ranking de Casos Criticos',
          subtitle: 'Prioridad sugerida por riesgo, sintomas y alertas.',
          icon: Icons.leaderboard_rounded,
          child: _buildCriticalRanking(criticalStudents),
        );

        final patientPanel = _surfaceCard(
          title: 'Pacientes Priorizados',
          subtitle: 'Ordenados por riesgo y recencia clinica.',
          icon: Icons.people_alt_outlined,
          child: Column(
            children: widget.students.map((student) {
              final latest = student.latestCheckIn;
              final selected = student.studentName == _selectedStudentName;
              final score = latest == null
                  ? '--'
                  : '${latest.wellbeingScore}/100';

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: selected ? _medicalMint : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? _medicalTeal : Colors.grey.shade200,
                    width: selected ? 1.4 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _selectStudent(student.studentName),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: _medicalMint,
                              backgroundImage: student.photoUrl == null
                                  ? null
                                  : NetworkImage(student.photoUrl!),
                              child: student.photoUrl == null
                                  ? Text(
                                      student.studentName.characters.first,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    student.studentName,
                                    style: const TextStyle(
                                      fontFamily: 'SF Pro Text',
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Score $score · Citas ${student.appointments.length}',
                                    style: TextStyle(
                                      color: Colors.grey[700],
                                      fontFamily: 'SF Pro Text',
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            RiskPill(level: student.riskLevel),
                          ],
                        ),
                        if (latest != null) ...[
                          const SizedBox(height: 10),
                          _clinicalGauge(
                            label: 'WHO-5',
                            value: latest.who5Percent,
                            maxValue: 100,
                            color: _medicalTeal,
                            highIsGood: true,
                          ),
                          const SizedBox(height: 6),
                          _clinicalGauge(
                            label: 'PHQ-2',
                            value: latest.phq2Score,
                            maxValue: 6,
                            color: const Color(0xFFB54708),
                            highIsGood: false,
                          ),
                          const SizedBox(height: 6),
                          _clinicalGauge(
                            label: 'GAD-2',
                            value: latest.gad2Score,
                            maxValue: 6,
                            color: const Color(0xFFB42318),
                            highIsGood: false,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );

        final detailPanel = _surfaceCard(
          title: selectedStudent == null
              ? 'Expediente del Paciente'
              : 'Expediente de ${selectedStudent.studentName}',
          subtitle: 'Ficha clinica completa para seguimiento profesional.',
          icon: Icons.badge_outlined,
          child: selectedStudent == null
              ? Text(
                  'Selecciona un paciente para ver su detalle clinico.',
                  style: TextStyle(color: Colors.grey[700]),
                )
              : selectedRecord == null
              ? Text(
                  'No se encontro expediente editable para este paciente.',
                  style: TextStyle(color: Colors.grey[700]),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        RiskPill(level: selectedStudent.riskLevel),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Check-ins ${selectedStudent.checkIns.length} · Reflexiones ${selectedStudent.reflections.length} · Citas ${selectedStudent.appointments.length}',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontFamily: 'SF Pro Text',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildExpedienteSnapshot(selectedStudent),
                    if (selectedStudent.latestCheckIn != null) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _statusMetric(
                            'WHO-5',
                            selectedStudent.latestCheckIn!.who5Percent,
                            _medicalTeal,
                          ),
                          _statusMetric(
                            'PHQ-2',
                            selectedStudent.latestCheckIn!.phq2Score,
                            const Color(0xFFB54708),
                          ),
                          _statusMetric(
                            'GAD-2',
                            selectedStudent.latestCheckIn!.gad2Score,
                            const Color(0xFFB42318),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _medicalMint,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          selectedStudent.latestCheckIn!.summary,
                          style: TextStyle(
                            color: Colors.grey[800],
                            fontFamily: 'SF Pro Text',
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _expedienteSectionBlock(
                      title: 'Contacto y datos relevantes',
                      subtitle: 'Identificacion, contacto y marco del caso.',
                      icon: Icons.contact_page_outlined,
                      child: _buildContactAndRelevantSection(selectedStudent),
                    ),
                    const SizedBox(height: 12),
                    _expedienteSectionBlock(
                      title: 'Evolucion de escalas y check-ins',
                      subtitle: 'Registro temporal de WHO-5, PHQ-2 y GAD-2.',
                      icon: Icons.monitor_heart_outlined,
                      child: _buildCheckInEvolution(selectedStudent),
                    ),
                    const SizedBox(height: 12),
                    _expedienteSectionBlock(
                      title: 'Contexto con inputs y evidencia obtenida',
                      subtitle: 'Señales clinicas derivadas de entradas y analisis.',
                      icon: Icons.dataset_outlined,
                      child: _buildInputContextSection(selectedStudent),
                    ),
                    const SizedBox(height: 12),
                    _expedienteSectionBlock(
                      title: 'Adherencia al tratamiento',
                      subtitle: 'Cumplimiento de actividades terapeuticas.',
                      icon: Icons.task_alt_rounded,
                      child: _buildTreatmentAdherence(selectedStudent),
                    ),
                    const SizedBox(height: 12),
                    _expedienteSectionBlock(
                      title: 'Historial de citas',
                      subtitle: 'Seguimiento de asistencia y estado de agenda.',
                      icon: Icons.event_note_outlined,
                      child: _buildAppointmentHistory(selectedStudent),
                    ),
                    const SizedBox(height: 12),
                    _expedienteSectionBlock(
                      title: 'Linea de tiempo clinica',
                      subtitle: 'Eventos relevantes del caso en orden cronologico.',
                      icon: Icons.timeline_outlined,
                      child: _buildClinicalTimeline(selectedStudent),
                    ),
                    const SizedBox(height: 12),
                    _expedienteSectionBlock(
                      title: 'Notas del profesional',
                      subtitle: 'Anotaciones editables de seguimiento.',
                      icon: Icons.edit_note_outlined,
                      child: _buildProfessionalNotesSection(selectedStudent),
                    ),
                    const SizedBox(height: 12),
                    _expedienteSectionBlock(
                      title: 'Bitacora editable del caso',
                      subtitle: 'Registro operativo y clinico del paciente.',
                      icon: Icons.menu_book_outlined,
                      child: _buildBitacoraSection(selectedStudent),
                    ),
                    const SizedBox(height: 12),
                    _expedienteSectionBlock(
                      title: 'Alertas activas recientes',
                      subtitle: 'Incidentes y focos de atencion inmediata.',
                      icon: Icons.notification_important_outlined,
                      child: alerts.isEmpty
                          ? Text(
                              'Sin alertas registradas para este paciente.',
                              style: TextStyle(color: Colors.grey[700]),
                            )
                          : Column(
                              children: alerts.map((alert) {
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF8E8),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(0xFFF7D8A0),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.warning_amber_rounded,
                                        color: Colors.orange[700],
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              alert.title,
                                              style: const TextStyle(
                                                fontFamily: 'SF Pro Text',
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(alert.detail),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                    ),
                  ],
                ),
        );

        final agendaPanel = _surfaceCard(
          title: 'Agenda Profesional',
          subtitle: 'Cronograma consolidado de pacientes.',
          icon: Icons.calendar_month_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Todas'),
                    selected: _agendaStatusFilter == null,
                    onSelected: (_) =>
                        setState(() => _agendaStatusFilter = null),
                  ),
                  ChoiceChip(
                    label: const Text('Pendientes'),
                    selected: _agendaStatusFilter == AppointmentStatus.pending,
                    onSelected: (_) => setState(
                      () => _agendaStatusFilter = AppointmentStatus.pending,
                    ),
                  ),
                  ChoiceChip(
                    label: const Text('Confirmadas'),
                    selected:
                        _agendaStatusFilter == AppointmentStatus.confirmed,
                    onSelected: (_) => setState(
                      () => _agendaStatusFilter = AppointmentStatus.confirmed,
                    ),
                  ),
                  ChoiceChip(
                    label: const Text('Rechazadas'),
                    selected: _agendaStatusFilter == AppointmentStatus.declined,
                    onSelected: (_) => setState(
                      () => _agendaStatusFilter = AppointmentStatus.declined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_filteredAgendaItems.isEmpty)
                Text(
                  'No hay citas para este filtro.',
                  style: TextStyle(color: Colors.grey[700]),
                )
              else
                Column(
                  children: _filteredAgendaItems.map((entry) {
                    final start = entry.appointment.scheduledFor;
                    final end = entry.appointment.endAt;
                    final hhStart =
                        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
                    final hhEnd =
                        '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
                    final latestEvent = entry.appointment.statusHistory.isEmpty
                        ? null
                        : entry.appointment.statusHistory.last;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: _medicalMint,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$hhStart - $hhEnd',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  entry.student.studentName,
                                  style: const TextStyle(
                                    fontFamily: 'SF Pro Text',
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              _appointmentStatusBadge(entry.appointment.status),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            entry.appointment.reason,
                            style: TextStyle(
                              color: Colors.grey[800],
                              fontFamily: 'SF Pro Text',
                            ),
                          ),
                          if (latestEvent != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Ultimo cambio: ${_actorLabel(latestEvent.actor)} · ${_formatDate(latestEvent.changedAt)}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        );

        final schedulerPanel = _surfaceCard(
          title: 'Programar Cita',
          subtitle: 'Validacion automatica para evitar empalmes.',
          icon: Icons.add_circle_outline,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _statusMetric(
                      'Pendientes',
                      _agendaItems
                          .where(
                            (item) =>
                                item.appointment.status ==
                                AppointmentStatus.pending,
                          )
                          .length,
                      const Color(0xFFB54708),
                    ),
                    _statusMetric(
                      'Confirmadas',
                      _agendaItems
                          .where(
                            (item) =>
                                item.appointment.status ==
                                AppointmentStatus.confirmed,
                          )
                          .length,
                      const Color(0xFF067647),
                    ),
                    _statusMetric(
                      'Rechazadas',
                      _agendaItems
                          .where(
                            (item) =>
                                item.appointment.status ==
                                AppointmentStatus.declined,
                          )
                          .length,
                      const Color(0xFFB42318),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _selectedStudentName,
                decoration: const InputDecoration(labelText: 'Paciente'),
                items: widget.students
                    .map(
                      (student) => DropdownMenuItem<String>(
                        value: student.studentName,
                        child: Text(student.studentName),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  _selectStudent(value);
                  _applySuggestedSlot();
                },
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: _pickDateTime,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Fecha y hora',
                    suffixIcon: Icon(Icons.schedule),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(_formatDate(_selectedDateTime))),
                      if (_isUsingAutoSlot)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade100,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            'Auto',
                            style: TextStyle(
                              color: Colors.purple.shade800,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: _selectedDurationMinutes,
                decoration: const InputDecoration(labelText: 'Duracion'),
                items: const [30, 45, 60]
                    .map(
                      (minutes) => DropdownMenuItem<int>(
                        value: minutes,
                        child: Text('$minutes minutos'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedDurationMinutes = value);
                  _applySuggestedSlot();
                },
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _applySuggestedSlot,
                  icon: const Icon(Icons.auto_fix_high_rounded),
                  label: const Text('Sugerir siguiente espacio disponible'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _reasonController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Motivo clinico'),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _scheduling ? null : _scheduleAppointment,
                  icon: _scheduling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.event_available),
                  label: Text(
                    _scheduling ? 'Validando agenda...' : 'Registrar cita',
                  ),
                ),
              ),
            ],
          ),
        );

        final treatmentPanel = _surfaceCard(
          title: 'Tratamiento y Tareas',
          subtitle: 'Asigna acciones concretas para seguimiento diario.',
          icon: Icons.fact_check_outlined,
          child: Column(
            children: [
              TextField(
                controller: _treatmentTitleController,
                decoration: const InputDecoration(labelText: 'Titulo del plan'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _treatmentSummaryController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Resumen'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _treatmentTasksController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Tareas (una por linea)',
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saveTreatmentPlan,
                  icon: const Icon(Icons.playlist_add_check_circle_outlined),
                  label: const Text('Asignar tratamiento'),
                ),
              ),
            ],
          ),
        );

        final notificationsPanel = _surfaceCard(
          title: 'Respuestas de Estudiantes',
          subtitle: 'Confirmaciones y rechazos recientes de citas.',
          icon: Icons.notifications_active_outlined,
          child: widget.notifications.isEmpty
              ? Text(
                  'Aun no hay respuestas de alumnos sobre citas pendientes.',
                  style: TextStyle(color: Colors.grey[700]),
                )
              : Column(
                  children: widget.notifications.take(6).map((note) {
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: _appointmentStatusBadge(note.status),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  note.title,
                                  style: const TextStyle(
                                    fontFamily: 'SF Pro Text',
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(note.detail),
                                const SizedBox(height: 2),
                                Text(
                                  _formatDate(note.createdAt),
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        );

        final desktopGrid = Column(
          children: [
            headerCard,
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: loadPanel),
                const SizedBox(width: 12),
                Expanded(child: heatmapPanel),
                const SizedBox(width: 12),
                Expanded(child: rankingPanel),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 33, child: patientPanel),
                const SizedBox(width: 12),
                Expanded(
                  flex: 34,
                  child: Column(
                    children: [
                      detailPanel,
                      const SizedBox(height: 12),
                      notificationsPanel,
                      const SizedBox(height: 12),
                      treatmentPanel,
                      const SizedBox(height: 12),
                      schedulerPanel,
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(flex: 33, child: agendaPanel),
              ],
            ),
          ],
        );

        final tabletGrid = Column(
          children: [
            headerCard,
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: loadPanel),
                const SizedBox(width: 12),
                Expanded(child: heatmapPanel),
              ],
            ),
            const SizedBox(height: 12),
            rankingPanel,
            const SizedBox(height: 12),
            patientPanel,
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: detailPanel),
                const SizedBox(width: 12),
                Expanded(child: agendaPanel),
              ],
            ),
            const SizedBox(height: 12),
            notificationsPanel,
            const SizedBox(height: 12),
            treatmentPanel,
            const SizedBox(height: 12),
            schedulerPanel,
          ],
        );

        final mobileStack = Column(
          children: [
            headerCard,
            const SizedBox(height: 12),
            loadPanel,
            const SizedBox(height: 12),
            heatmapPanel,
            const SizedBox(height: 12),
            rankingPanel,
            const SizedBox(height: 12),
            patientPanel,
            const SizedBox(height: 12),
            detailPanel,
            const SizedBox(height: 12),
            agendaPanel,
            const SizedBox(height: 12),
            notificationsPanel,
            const SizedBox(height: 12),
            treatmentPanel,
            const SizedBox(height: 12),
            schedulerPanel,
          ],
        );

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [const Color(0xFFF5FBFF), const Color(0xFFF3F9F8)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (isDesktop)
                desktopGrid
              else if (isTablet)
                tabletGrid
              else
                mobileStack,
            ],
          ),
        );
      },
    );
  }

  Widget _surfaceCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _medicalMint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: _medicalBlue, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: _medicalBlue,
                          fontFamily: 'SF Pro Display',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontFamily: 'SF Pro Text',
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _expedienteSectionBlock({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _medicalTeal.withOpacity(0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _medicalMint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: _medicalBlue),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: _medicalBlue,
                          fontFamily: 'SF Pro Display',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildExpedienteSnapshot(StudentCase student) {
    final openedAt = _firstClinicalRecord(student);
    final lastContact = _latestClinicalContact(student);
    final completion = _treatmentCompletionPercent(student);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _expedienteInfoTile(
          label: 'Caso abierto',
          value: openedAt == null ? 'Sin fecha' : _formatDate(openedAt),
          icon: Icons.assignment_ind_outlined,
          color: _medicalBlue,
        ),
        _expedienteInfoTile(
          label: 'Ultimo contacto',
          value: lastContact == null
              ? 'Sin contacto'
              : _formatDate(lastContact),
          icon: Icons.contact_phone_outlined,
          color: _medicalTeal,
        ),
        _expedienteInfoTile(
          label: 'Adherencia global',
          value: '$completion%',
          icon: Icons.task_alt_rounded,
          color: const Color(0xFF067647),
        ),
        _expedienteInfoTile(
          label: 'Alertas acumuladas',
          value: '${student.alerts.length}',
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFB54708),
        ),
      ],
    );
  }

  Widget _buildContactAndRelevantSection(StudentCase student) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          TextField(
            controller: _contactPhoneController,
            decoration: const InputDecoration(
              labelText: 'Telefono del alumno',
              prefixIcon: Icon(Icons.call_outlined),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _contactEmailController,
            decoration: const InputDecoration(
              labelText: 'Correo institucional',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _contactGuardianController,
            decoration: const InputDecoration(
              labelText: 'Tutor o contacto principal',
              prefixIcon: Icon(Icons.family_restroom_outlined),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _contactEmergencyController,
            decoration: const InputDecoration(
              labelText: 'Contacto de emergencia',
              prefixIcon: Icon(Icons.emergency_outlined),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _contactMetaController,
            decoration: const InputDecoration(
              labelText: 'Datos relevantes (grupo, turno, observaciones)',
              prefixIcon: Icon(Icons.info_outline_rounded),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _clinicalContextController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Contexto clinico del caso',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.description_outlined),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: _saveContactAndContext,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Guardar datos del expediente'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputContextSection(StudentCase student) {
    final latestCheckIn = student.latestCheckIn;
    final latestReflection = student.reflections.isEmpty
        ? null
        : student.reflections.last;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _medicalMint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _medicalTeal.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Inputs recientes',
            style: TextStyle(
              color: _medicalBlue,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            latestCheckIn == null
                ? 'No hay check-in reciente.'
                : 'Check-in ${_formatDate(latestCheckIn.date)} · respuestas: ${latestCheckIn.answers.isEmpty ? 'sin detalle' : latestCheckIn.answers.entries.map((e) => 'P${e.key}:${e.value}').join(', ')}',
          ),
          const SizedBox(height: 6),
          Text(
            latestReflection == null
                ? 'Sin reflexion reciente para analisis contextual.'
                : 'Fuente: ${latestReflection.source} · riesgo detectado: ${latestReflection.detectedRisk.name}',
          ),
          if (latestReflection != null) ...[
            const SizedBox(height: 6),
            Text('Hallazgos: ${latestReflection.detectedFindings.join(', ')}'),
            const SizedBox(height: 4),
            Text('Evidencia: ${latestReflection.evidenceTerms.join(', ')}'),
            const SizedBox(height: 4),
            Text('Razonamiento: ${latestReflection.reasoningSummary}'),
          ],
        ],
      ),
    );
  }

  Widget _buildProfessionalNotesSection(StudentCase student) {
    final record = _recordsByStudent[student.studentName];
    if (record == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          TextField(
            controller: _professionalNoteController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: _editingNoteIndex == null
                  ? 'Nueva anotacion profesional'
                  : 'Editar anotacion #${_editingNoteIndex! + 1}',
              alignLabelWithHint: true,
              prefixIcon: const Icon(Icons.note_alt_outlined),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saveProfessionalNote,
                  icon: const Icon(Icons.note_add_outlined),
                  label: Text(
                    _editingNoteIndex == null ? 'Agregar nota' : 'Actualizar nota',
                  ),
                ),
              ),
              if (_editingNoteIndex != null) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _editingNoteIndex = null;
                      _professionalNoteController.clear();
                    });
                  },
                  child: const Text('Cancelar'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (record.notes.isEmpty)
            Text(
              'Sin anotaciones profesionales.',
              style: TextStyle(color: Colors.grey[700]),
            )
          else
            ...record.notes.take(8).toList().asMap().entries.map((entry) {
              final index = entry.key;
              final note = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${note.author} · ${_formatDate(note.createdAt)}',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () => _beginEditNote(index, note.text),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => _deleteNote(index),
                        ),
                      ],
                    ),
                    Text(note.text),
                    if (note.updatedAt != null)
                      Text(
                        'Editada: ${_formatDate(note.updatedAt!)}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 11),
                      ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildBitacoraSection(StudentCase student) {
    final record = _recordsByStudent[student.studentName];
    if (record == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _bitacoraType,
                  decoration: const InputDecoration(labelText: 'Tipo de entrada'),
                  items: const [
                    DropdownMenuItem(value: 'Seguimiento', child: Text('Seguimiento')),
                    DropdownMenuItem(value: 'Sesion', child: Text('Sesion')),
                    DropdownMenuItem(value: 'Contacto', child: Text('Contacto')),
                    DropdownMenuItem(value: 'Incidencia', child: Text('Incidencia')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _bitacoraType = value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _bitacoraController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: _editingBitacoraIndex == null
                  ? 'Entrada de bitacora'
                  : 'Editar entrada #${_editingBitacoraIndex! + 1}',
              alignLabelWithHint: true,
              prefixIcon: const Icon(Icons.edit_calendar_outlined),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saveBitacoraEntry,
                  icon: const Icon(Icons.post_add_outlined),
                  label: Text(
                    _editingBitacoraIndex == null
                        ? 'Agregar a bitacora'
                        : 'Actualizar entrada',
                  ),
                ),
              ),
              if (_editingBitacoraIndex != null) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _editingBitacoraIndex = null;
                      _bitacoraController.clear();
                      _bitacoraType = 'Seguimiento';
                    });
                  },
                  child: const Text('Cancelar'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (record.bitacora.isEmpty)
            Text(
              'Sin eventos registrados en bitacora.',
              style: TextStyle(color: Colors.grey[700]),
            )
          else
            ...record.bitacora
                .take(10)
                .toList()
                .asMap()
                .entries
                .map((entryMap) {
              final index = entryMap.key;
              final entry = entryMap.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '[${entry.type}] ${_formatDate(entry.createdAt)}',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(entry.text),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () => _beginEditBitacora(index, entry),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => _deleteBitacoraEntry(index),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _expedienteInfoTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 230,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckInEvolution(StudentCase student) {
    final history = [...student.checkIns]
      ..sort((a, b) => b.date.compareTo(a.date));

    if (history.isEmpty) {
      return Text(
        'Aun no hay historial de check-ins para evaluar tendencia.',
        style: TextStyle(color: Colors.grey[700]),
      );
    }

    return Column(
      children: history.take(5).map((checkIn) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _formatDate(checkIn.date),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  RiskPill(level: checkIn.riskLevel),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _statusMetric('WHO-5', checkIn.who5Percent, _medicalTeal),
                  _statusMetric(
                    'PHQ-2',
                    checkIn.phq2Score,
                    const Color(0xFFB54708),
                  ),
                  _statusMetric(
                    'GAD-2',
                    checkIn.gad2Score,
                    const Color(0xFFB42318),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTreatmentAdherence(StudentCase student) {
    final plans = student.treatmentPlans;
    if (plans.isEmpty) {
      return Text(
        'Sin planes de tratamiento asignados en el expediente.',
        style: TextStyle(color: Colors.grey[700]),
      );
    }

    return Column(
      children: plans.take(4).map((plan) {
        final total = plan.tasks.length;
        final done = plan.tasks.where((task) => task.completed).length;
        final ratio = total == 0 ? 0.0 : done / total;
        final percent = (ratio * 100).round();

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                plan.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 8,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF067647),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$done/$total tareas completadas ($percent%)',
                style: TextStyle(color: Colors.grey[700], fontSize: 12),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAppointmentHistory(StudentCase student) {
    final appointments = [...student.appointments]
      ..sort((a, b) => b.scheduledFor.compareTo(a.scheduledFor));

    if (appointments.isEmpty) {
      return Text(
        'No hay citas registradas en el expediente.',
        style: TextStyle(color: Colors.grey[700]),
      );
    }

    return Column(
      children: appointments.take(6).map((appointment) {
        final latest = appointment.statusHistory.isEmpty
            ? null
            : appointment.statusHistory.last;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 60,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: _medicalMint,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${appointment.scheduledFor.hour.toString().padLeft(2, '0')}:${appointment.scheduledFor.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatDate(appointment.scheduledFor),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(appointment.reason),
                    if (latest != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Ultimo estado: ${_actorLabel(latest.actor)} · ${latest.note}',
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              _appointmentStatusBadge(appointment.status),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildClinicalTimeline(StudentCase student) {
    final events = _expedienteEvents(student);
    if (events.isEmpty) {
      return Text(
        'No hay eventos clinicos suficientes para generar timeline.',
        style: TextStyle(color: Colors.grey[700]),
      );
    }

    return Column(
      children: events.take(8).map((event) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: event.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(event.icon, size: 16, color: event.color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              event.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            _formatDate(event.date),
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(event.detail),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  List<_ExpedienteEvent> _expedienteEvents(StudentCase student) {
    final events = <_ExpedienteEvent>[];
    final record = _recordsByStudent[student.studentName];

    for (final alert in student.alerts) {
      events.add(
        _ExpedienteEvent(
          date: alert.createdAt,
          title: 'Alerta profesional: ${alert.title}',
          detail: alert.detail,
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFB54708),
        ),
      );
    }

    for (final reflection in student.reflections) {
      events.add(
        _ExpedienteEvent(
          date: reflection.createdAt,
          title: 'Reflexion del alumno (${reflection.source})',
          detail: reflection.interpretation,
          icon: Icons.psychology_alt_outlined,
          color: _medicalTeal,
        ),
      );
    }

    for (final appointment in student.appointments) {
      for (final change in appointment.statusHistory) {
        events.add(
          _ExpedienteEvent(
            date: change.changedAt,
            title: 'Cambio de cita: ${appointment.reason}',
            detail: '${_actorLabel(change.actor)} · ${change.note}',
            icon: Icons.event_note_rounded,
            color: _medicalBlue,
          ),
        );
      }
    }

    if (record != null) {
      for (final note in record.notes) {
        events.add(
          _ExpedienteEvent(
            date: note.updatedAt ?? note.createdAt,
            title: 'Nota profesional',
            detail: note.text,
            icon: Icons.sticky_note_2_outlined,
            color: const Color(0xFF155EEF),
          ),
        );
      }
      for (final entry in record.bitacora) {
        events.add(
          _ExpedienteEvent(
            date: entry.createdAt,
            title: 'Bitacora: ${entry.type}',
            detail: entry.text,
            icon: Icons.menu_book_outlined,
            color: _medicalTeal,
          ),
        );
      }
    }

    events.sort((a, b) => b.date.compareTo(a.date));
    return events;
  }

  int _treatmentCompletionPercent(StudentCase student) {
    final tasks = student.treatmentPlans.expand((plan) => plan.tasks).toList();
    if (tasks.isEmpty) return 0;
    final completed = tasks.where((task) => task.completed).length;
    return ((completed / tasks.length) * 100).round();
  }

  DateTime? _firstClinicalRecord(StudentCase student) {
    final dates = <DateTime>[
      ...student.checkIns.map((item) => item.date),
      ...student.reflections.map((item) => item.createdAt),
      ...student.alerts.map((item) => item.createdAt),
      ...student.appointments.map((item) => item.createdAt),
      ...student.treatmentPlans.map((item) => item.createdAt),
    ];
    if (dates.isEmpty) return null;
    dates.sort();
    return dates.first;
  }

  DateTime? _latestClinicalContact(StudentCase student) {
    final dates = <DateTime>[
      ...student.checkIns.map((item) => item.date),
      ...student.reflections.map((item) => item.createdAt),
      ...student.alerts.map((item) => item.createdAt),
      ...student.appointments.map((item) => item.scheduledFor),
      ...student.appointments.expand(
        (item) => item.statusHistory.map((s) => s.changedAt),
      ),
    ];
    if (dates.isEmpty) return null;
    dates.sort((a, b) => b.compareTo(a));
    return dates.first;
  }

  Widget _appointmentStatusBadge(AppointmentStatus status) {
    switch (status) {
      case AppointmentStatus.pending:
        return _pill(
          'Pendiente',
          const Color(0xFFFFF4E5),
          const Color(0xFFB54708),
        );
      case AppointmentStatus.confirmed:
        return _pill(
          'Confirmada',
          const Color(0xFFE9F9EE),
          const Color(0xFF067647),
        );
      case AppointmentStatus.declined:
        return _pill(
          'Rechazada',
          const Color(0xFFFFE3E3),
          const Color(0xFFB42318),
        );
    }
  }

  String _actorLabel(AppointmentActor actor) {
    switch (actor) {
      case AppointmentActor.professional:
        return 'Profesional';
      case AppointmentActor.student:
        return 'Alumno';
      case AppointmentActor.system:
        return 'Sistema';
    }
  }

  Widget _statusMetric(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: color,
          fontFamily: 'SF Pro Text',
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _pill(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontFamily: 'SF Pro Text',
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _kpiTile({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    Color? accent,
  }) {
    final color = accent ?? _medicalBlue;
    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, color.withOpacity(0.08)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontFamily: 'SF Pro Display',
              fontWeight: FontWeight.w800,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'SF Pro Text',
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.grey[600],
              fontFamily: 'SF Pro Text',
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _medicalHeroCard({
    required int avgWellbeing,
    required int highRisk,
    required int mediumRisk,
    required int pendingCount,
    required int confirmedCount,
    required int declinedCount,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF0B4A6F), Color(0xFF0A7B83)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: _medicalBlue.withOpacity(0.22),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.local_hospital_rounded, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Centro de Monitoreo Clinico',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'SF Pro Display',
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Triage en tiempo real · Bienestar promedio: $avgWellbeing/100',
              style: const TextStyle(color: Color(0xFFD8F4F3), fontSize: 13),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _heroChip(
                  'Riesgo alto: $highRisk',
                  const Color(0xFFFFE3E3),
                  const Color(0xFFB42318),
                ),
                _heroChip(
                  'Riesgo medio: $mediumRisk',
                  const Color(0xFFFFF4E5),
                  const Color(0xFFB54708),
                ),
                _heroChip(
                  'Pendientes: $pendingCount',
                  const Color(0xFFFFF4E5),
                  const Color(0xFFB54708),
                ),
                _heroChip(
                  'Confirmadas: $confirmedCount',
                  const Color(0xFFE9F9EE),
                  const Color(0xFF067647),
                ),
                _heroChip(
                  'Rechazadas: $declinedCount',
                  const Color(0xFFFFE3E3),
                  const Color(0xFFB42318),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _heroChip(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _clinicalGauge({
    required String label,
    required int value,
    required int maxValue,
    required Color color,
    required bool highIsGood,
  }) {
    final ratio = maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);
    final displayRatio = highIsGood ? ratio : (1 - ratio);
    return Row(
      children: [
        SizedBox(
          width: 54,
          child: Text(
            '$label:',
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: displayRatio,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 32,
          child: Text(
            '$value',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  _ClinicalLoadState _clinicalLoadState({
    required int highRisk,
    required int pendingCount,
    required int appointmentsToday,
    required int avgWellbeing,
  }) {
    final pressure = highRisk * 3 + pendingCount * 2 + appointmentsToday;
    if (pressure >= 12 || avgWellbeing < 45) {
      return const _ClinicalLoadState(
        label: 'ALTA',
        detail: 'Se recomienda priorizar triage y redistribuir agenda.',
        color: Color(0xFFB42318),
        icon: Icons.warning_amber_rounded,
      );
    }
    if (pressure >= 7 || avgWellbeing < 60) {
      return const _ClinicalLoadState(
        label: 'MEDIA',
        detail: 'Carga estable con necesidad de monitoreo activo.',
        color: Color(0xFFB54708),
        icon: Icons.timelapse_rounded,
      );
    }
    return const _ClinicalLoadState(
      label: 'CONTROLADA',
      detail: 'Operacion dentro de rango recomendado.',
      color: Color(0xFF067647),
      icon: Icons.check_circle_rounded,
    );
  }

  Map<int, int> _agendaHeatmapData() {
    final now = DateTime.now();
    final limit = now.add(const Duration(days: 7));
    final data = <int, int>{for (final hour in _heatmapHours) hour: 0};

    for (final item in _agendaItems) {
      final startsAt = item.appointment.scheduledFor;
      if (startsAt.isBefore(now) || startsAt.isAfter(limit)) continue;
      if (data.containsKey(startsAt.hour)) {
        data[startsAt.hour] = data[startsAt.hour]! + 1;
      }
    }
    return data;
  }

  List<_CriticalCase> _criticalRanking() {
    final ranking = widget.students.map((student) {
      final checkIn = student.latestCheckIn;
      final riskBase = switch (student.riskLevel) {
        RiskLevel.high => 300,
        RiskLevel.medium => 200,
        RiskLevel.low => 100,
      };
      final wellbeingPenalty = checkIn == null
          ? 40
          : (100 - checkIn.wellbeingScore);
      final symptoms = checkIn == null
          ? 0
          : (checkIn.phq2Score + checkIn.gad2Score) * 8;
      final alerts = student.alerts.length * 4;
      final score = riskBase + wellbeingPenalty + symptoms + alerts;
      return _CriticalCase(student: student, score: score);
    }).toList();

    ranking.sort((a, b) => b.score.compareTo(a.score));
    return ranking;
  }

  Widget _buildLoadCard(_ClinicalLoadState state) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: state.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: state.color.withOpacity(0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: state.color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(state.icon, color: state.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estado: ${state.label}',
                  style: TextStyle(
                    color: state.color,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'SF Pro Display',
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 2),
                Text(state.detail, style: TextStyle(color: Colors.grey[800])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgendaHeatmap(Map<int, int> data) {
    final maxCount = data.values.fold<int>(
      0,
      (prev, value) => value > prev ? value : prev,
    );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _heatmapHours.map((hour) {
        final count = data[hour] ?? 0;
        final intensity = maxCount == 0
            ? 0.0
            : (count / maxCount).clamp(0.0, 1.0);
        final bg =
            Color.lerp(const Color(0xFFEAF4F6), _medicalTeal, intensity) ??
            _medicalMint;
        final fg = intensity > 0.55 ? Colors.white : _medicalBlue;
        return Container(
          width: 78,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _medicalTeal.withOpacity(0.25)),
          ),
          child: Column(
            children: [
              Text(
                '${hour.toString().padLeft(2, '0')}:00',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: fg,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$count cita${count == 1 ? '' : 's'}',
                style: TextStyle(color: fg, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCriticalRanking(List<_CriticalCase> ranking) {
    if (ranking.isEmpty) {
      return Text(
        'Sin pacientes en seguimiento.',
        style: TextStyle(color: Colors.grey[700]),
      );
    }

    return Column(
      children: ranking.take(5).toList().asMap().entries.map((entry) {
        final index = entry.key;
        final critical = entry.value;
        final student = critical.student;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: index == 0 ? const Color(0xFFFFF4E5) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: index == 0
                  ? const Color(0xFFEAAA08)
                  : Colors.grey.shade200,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _medicalMint,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  '#${index + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      student.studentName,
                      style: const TextStyle(
                        fontFamily: 'SF Pro Text',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Puntaje critico: ${critical.score}',
                      style: TextStyle(color: Colors.grey[700], fontSize: 12),
                    ),
                  ],
                ),
              ),
              RiskPill(level: student.riskLevel),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _formatDate(DateTime date) {
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    return '${date.day}/${date.month}/${date.year} $hh:$mm';
  }
}

class _AgendaItem {
  final StudentCase student;
  final ProfessionalAppointment appointment;

  const _AgendaItem({required this.student, required this.appointment});
}

class _ClinicalLoadState {
  final String label;
  final String detail;
  final Color color;
  final IconData icon;

  const _ClinicalLoadState({
    required this.label,
    required this.detail,
    required this.color,
    required this.icon,
  });
}

class _CriticalCase {
  final StudentCase student;
  final int score;

  const _CriticalCase({required this.student, required this.score});
}

class _ProfessionalRecord {
  final _PatientContactInfo contact;
  final String clinicalContext;
  final List<_ProfessionalNote> notes;
  final List<_BitacoraEntry> bitacora;

  const _ProfessionalRecord({
    required this.contact,
    required this.clinicalContext,
    required this.notes,
    required this.bitacora,
  });

  _ProfessionalRecord copyWith({
    _PatientContactInfo? contact,
    String? clinicalContext,
    List<_ProfessionalNote>? notes,
    List<_BitacoraEntry>? bitacora,
  }) {
    return _ProfessionalRecord(
      contact: contact ?? this.contact,
      clinicalContext: clinicalContext ?? this.clinicalContext,
      notes: notes ?? this.notes,
      bitacora: bitacora ?? this.bitacora,
    );
  }
}

class _PatientContactInfo {
  final String phone;
  final String email;
  final String guardianName;
  final String emergencyContact;
  final String relevantMeta;

  const _PatientContactInfo({
    required this.phone,
    required this.email,
    required this.guardianName,
    required this.emergencyContact,
    required this.relevantMeta,
  });

  _PatientContactInfo copyWith({
    String? phone,
    String? email,
    String? guardianName,
    String? emergencyContact,
    String? relevantMeta,
  }) {
    return _PatientContactInfo(
      phone: phone ?? this.phone,
      email: email ?? this.email,
      guardianName: guardianName ?? this.guardianName,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      relevantMeta: relevantMeta ?? this.relevantMeta,
    );
  }
}

class _ProfessionalNote {
  final String id;
  final String text;
  final String author;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const _ProfessionalNote({
    required this.id,
    required this.text,
    required this.author,
    required this.createdAt,
    this.updatedAt,
  });

  _ProfessionalNote copyWith({
    String? id,
    String? text,
    String? author,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return _ProfessionalNote(
      id: id ?? this.id,
      text: text ?? this.text,
      author: author ?? this.author,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class _BitacoraEntry {
  final String id;
  final String type;
  final String text;
  final DateTime createdAt;

  const _BitacoraEntry({
    required this.id,
    required this.type,
    required this.text,
    required this.createdAt,
  });

  _BitacoraEntry copyWith({
    String? id,
    String? type,
    String? text,
    DateTime? createdAt,
  }) {
    return _BitacoraEntry(
      id: id ?? this.id,
      type: type ?? this.type,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class _ExpedienteEvent {
  final DateTime date;
  final String title;
  final String detail;
  final IconData icon;
  final Color color;

  const _ExpedienteEvent({
    required this.date,
    required this.title,
    required this.detail,
    required this.icon,
    required this.color,
  });
}

class RiskPill extends StatelessWidget {
  final RiskLevel level;

  const RiskPill({super.key, required this.level});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String text;

    switch (level) {
      case RiskLevel.high:
        bg = const Color(0xFFFFE3E3);
        fg = const Color(0xFFB42318);
        text = 'Riesgo alto';
        break;
      case RiskLevel.medium:
        bg = const Color(0xFFFFF4E5);
        fg = const Color(0xFFB54708);
        text = 'Riesgo medio';
        break;
      case RiskLevel.low:
        bg = const Color(0xFFE9F9EE);
        fg = const Color(0xFF067647);
        text = 'Riesgo bajo';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontFamily: 'SF Pro Text',
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

enum RiskLevel { low, medium, high }

enum ClinicalScale { who5, phq2, gad2 }

class DailyCheckIn {
  final DateTime date;
  final Map<int, int> answers;
  final int wellbeingScore;
  final RiskLevel riskLevel;
  final String summary;
  final int who5Percent;
  final int phq2Score;
  final int gad2Score;

  DailyCheckIn({
    required this.date,
    required this.answers,
    required this.wellbeingScore,
    required this.riskLevel,
    required this.summary,
    required this.who5Percent,
    required this.phq2Score,
    required this.gad2Score,
  });
}

class StudentReflection {
  final String text;
  final DateTime createdAt;
  final List<String> patterns;
  final String interpretation;
  final List<String> detectedFindings;
  final String rationale;
  final List<String> evidenceTerms;
  final String reasoningSummary;
  final String source;
  final RiskLevel detectedRisk;

  StudentReflection({
    required this.text,
    required this.createdAt,
    required this.patterns,
    required this.interpretation,
    required this.detectedFindings,
    required this.rationale,
    required this.evidenceTerms,
    required this.reasoningSummary,
    required this.source,
    required this.detectedRisk,
  });
}

class ProfessionalAlert {
  final String title;
  final String detail;
  final DateTime createdAt;

  ProfessionalAlert({
    required this.title,
    required this.detail,
    required this.createdAt,
  });
}

class ProfessionalAppointment {
  final String id;
  final DateTime scheduledFor;
  final int durationMinutes;
  final String reason;
  final DateTime createdAt;
  final AppointmentStatus status;
  final List<AppointmentStatusEvent> statusHistory;

  DateTime get endAt => scheduledFor.add(Duration(minutes: durationMinutes));

  ProfessionalAppointment({
    required this.id,
    required this.scheduledFor,
    required this.durationMinutes,
    required this.reason,
    required this.createdAt,
    required this.status,
    required this.statusHistory,
  });

  ProfessionalAppointment copyWith({
    String? id,
    DateTime? scheduledFor,
    int? durationMinutes,
    String? reason,
    DateTime? createdAt,
    AppointmentStatus? status,
    List<AppointmentStatusEvent>? statusHistory,
  }) {
    return ProfessionalAppointment(
      id: id ?? this.id,
      scheduledFor: scheduledFor ?? this.scheduledFor,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      reason: reason ?? this.reason,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      statusHistory: statusHistory ?? this.statusHistory,
    );
  }
}

class TreatmentTask {
  final String id;
  final String title;
  final bool completed;
  final DateTime? completedAt;

  const TreatmentTask({
    required this.id,
    required this.title,
    required this.completed,
    this.completedAt,
  });

  TreatmentTask copyWith({
    String? id,
    String? title,
    bool? completed,
    DateTime? completedAt,
  }) {
    return TreatmentTask(
      id: id ?? this.id,
      title: title ?? this.title,
      completed: completed ?? this.completed,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

class TreatmentPlan {
  final String id;
  final String title;
  final String summary;
  final DateTime createdAt;
  final String assignedBy;
  final List<TreatmentTask> tasks;

  const TreatmentPlan({
    required this.id,
    required this.title,
    required this.summary,
    required this.createdAt,
    required this.assignedBy,
    required this.tasks,
  });

  TreatmentPlan copyWith({
    String? id,
    String? title,
    String? summary,
    DateTime? createdAt,
    String? assignedBy,
    List<TreatmentTask>? tasks,
  }) {
    return TreatmentPlan(
      id: id ?? this.id,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      createdAt: createdAt ?? this.createdAt,
      assignedBy: assignedBy ?? this.assignedBy,
      tasks: tasks ?? this.tasks,
    );
  }
}

class StudentCase {
  final String studentName;
  final String? photoUrl;
  final List<DailyCheckIn> checkIns;
  final List<StudentReflection>? _reflections;
  final List<ProfessionalAlert> alerts;
  final List<ProfessionalAppointment> appointments;
  final List<TreatmentPlan> treatmentPlans;
  final RiskLevel riskLevel;

  List<StudentReflection> get reflections => _reflections ?? const [];

  StudentCase({
    required this.studentName,
    this.photoUrl,
    required this.checkIns,
    List<StudentReflection>? reflections,
    required this.alerts,
    required this.appointments,
    required this.treatmentPlans,
    required this.riskLevel,
  }) : _reflections = reflections;

  factory StudentCase.empty() {
    return StudentCase(
      studentName: 'Alumno actual',
      photoUrl: 'https://i.pravatar.cc/240?img=33',
      checkIns: const [],
      reflections: const [],
      alerts: const [],
      appointments: const [],
      treatmentPlans: const [],
      riskLevel: RiskLevel.low,
    );
  }

  factory StudentCase.demo({
    required String studentName,
    String? photoUrl,
    required DailyCheckIn latestCheckIn,
  }) {
    return StudentCase(
      studentName: studentName,
      photoUrl: photoUrl,
      checkIns: [latestCheckIn],
      reflections: const [],
      alerts: const [],
      appointments: const [],
      treatmentPlans: const [],
      riskLevel: latestCheckIn.riskLevel,
    );
  }

  DailyCheckIn? get latestCheckIn => checkIns.isEmpty ? null : checkIns.last;

  StudentCase copyWith({
    String? studentName,
    String? photoUrl,
    List<DailyCheckIn>? checkIns,
    List<StudentReflection>? reflections,
    List<ProfessionalAlert>? alerts,
    List<ProfessionalAppointment>? appointments,
    List<TreatmentPlan>? treatmentPlans,
    RiskLevel? riskLevel,
  }) {
    return StudentCase(
      studentName: studentName ?? this.studentName,
      photoUrl: photoUrl ?? this.photoUrl,
      checkIns: checkIns ?? this.checkIns,
      reflections: reflections ?? this.reflections,
      alerts: alerts ?? this.alerts,
      appointments: appointments ?? this.appointments,
      treatmentPlans: treatmentPlans ?? this.treatmentPlans,
      riskLevel: riskLevel ?? this.riskLevel,
    );
  }
}

class ReflectionAnalysis {
  final StudentReflection reflection;
  final List<ProfessionalAlert> newAlerts;
  final RiskLevel detectedRisk;
  final RiskLevel caseRisk;

  ReflectionAnalysis({
    required this.reflection,
    required this.newAlerts,
    required this.detectedRisk,
    required this.caseRisk,
  });
}

class AiAnalysisException implements Exception {
  final String message;

  const AiAnalysisException(this.message);
}

class SchoolAiEngine {
  static const Duration _analysisTimeout = Duration(seconds: 20);
  static const _highRiskWords = [
    'no puedo más',
    'quiero desaparecer',
    'no vale la pena',
    'me quiero hacer daño',
    'me quiero matar',
    'quiero matarme',
    'me queria matar',
    'queria matarme',
    'pensamientos suicidas',
    'suicida',
    'suicidio',
    'me quiero morir',
    'quiero morirme',
    'quitarme la vida',
    'terminar con mi vida',
    'autolesion',
    'autolesionarme',
    'nadie me entiende',
  ];

  static const _highRiskContextPhrases = [
    'ya no quiero seguir',
    'seria mejor no estar aqui',
    'quisiera no despertar',
    'me despedi de todos',
    'soy una carga para todos',
    'no aguanto vivir asi',
    'quisiera matarme',
    'me voy a matar',
  ];

  static const _mediumRiskContextPhrases = [
    'no puedo con esto',
    'me siento un estorbo',
    'todo me sobrepasa',
    'no le veo sentido',
    'quiero aislarme de todos',
    'me derrumbe',
  ];

  static const _criticalSignalStems = [
    'suicid',
    'autolesion',
    'quitarme la vida',
    'terminar con mi vida',
    'matarme',
    'quiero matar',
    'me quiero matar',
    'me queria matar',
    'quiero morir',
    'morirme',
    'hacerme dano',
  ];

  static const _mediumRiskWords = [
    'ansiedad',
    'me siento solo',
    'estrés',
    'no duermo',
    'lloré',
    'agotado',
  ];

  static const _stressWords = [
    'estres',
    'estresado',
    'agotado',
    'presion',
    'saturado',
  ];
  static const _anxietyWords = [
    'ansiedad',
    'ansioso',
    'panico',
    'preocupacion',
    'nervioso',
  ];

  static Future<ReflectionAnalysis> analyzeReflection({
    required String reflectionText,
    required RiskLevel currentRisk,
    required DailyCheckIn? latestCheckIn,
    required List<StudentReflection> recentReflections,
    required String backendUrl,
    required SensorContext sensorContext,
  }) async {
    try {
      final reflectionUri = Uri.parse(
        '${backendUrl.trim()}/ai/wellbeing-reflection',
      );
      final reflectionPayload = {
        'reflection': reflectionText,
        'currentRisk': _riskToWire(currentRisk),
        'latestCheckIn': latestCheckIn == null
            ? null
            : {
                'summary': latestCheckIn.summary,
                'wellbeingScore': latestCheckIn.wellbeingScore,
                'who5Percent': latestCheckIn.who5Percent,
                'phq2Score': latestCheckIn.phq2Score,
                'gad2Score': latestCheckIn.gad2Score,
              },
        'recentReflections': recentReflections
            .take(8)
            .map(
              (r) => {
                'text': r.text,
                'patterns': r.patterns,
                'risk': _riskToWire(r.detectedRisk),
              },
            )
            .toList(),
        'sensorContext': sensorContext.toJson(),
      };

      http.Response response = await _postJsonWithRetry(
        reflectionUri,
        reflectionPayload,
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final chatUri = Uri.parse('${backendUrl.trim()}/ai/wellbeing-chat');
        final prompt =
            'Analiza este comentario de bienestar de un estudiante para un profesional escolar. '
            'Debes detectar estres, ansiedad, malestar emocional o riesgo critico si existe. '
            'Responde de forma calida, clara y detallada, mencionando que detectaste y por que. '
            'Comentario: "$reflectionText".';
        final chatPayload = {
          'message': prompt,
          'currentRisk': _riskToWire(currentRisk),
          'latestCheckIn': latestCheckIn == null
              ? null
              : {
                  'summary': latestCheckIn.summary,
                  'wellbeingScore': latestCheckIn.wellbeingScore,
                  'who5Percent': latestCheckIn.who5Percent,
                  'phq2Score': latestCheckIn.phq2Score,
                  'gad2Score': latestCheckIn.gad2Score,
                },
          'recentMessages': recentReflections
              .take(8)
              .map((r) => {'sender': 'user', 'text': r.text})
              .toList(),
          'sensorContext': sensorContext.toJson(),
        };

        response = await _postJsonWithRetry(chatUri, chatPayload);
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiAnalysisException(
          'El backend IA remoto no pudo analizar el comentario en este momento.',
        );
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = (body['data'] as Map<String, dynamic>?) ?? {};
      final now = DateTime.now();
      final alertsRaw = (data['alerts'] as List<dynamic>?) ?? const [];
      final backendRisk = _riskFromWire(
        (data['detectedRisk'] as String?) ?? 'low',
      );
      final analysisSource =
          (data['source'] as String?)?.trim().isNotEmpty == true
          ? (data['source'] as String).trim()
          : 'backend-wellbeing-reflection';
      final patternsRaw = (data['patterns'] as List<dynamic>?) ?? const [];
      final patterns = patternsRaw
          .map((item) => item.toString().trim())
          .where((v) => v.isNotEmpty)
          .toList();
      final findingsRaw =
          (data['detectedFindings'] as List<dynamic>?) ?? const [];
      final findings = findingsRaw
          .map((item) => item.toString().trim())
          .where((v) => v.isNotEmpty)
          .toList();
      final evidenceRaw = (data['evidenceTerms'] as List<dynamic>?) ?? const [];
      final backendEvidenceTerms = evidenceRaw
          .map((item) => item.toString().trim())
          .where((v) => v.isNotEmpty)
          .toList();

      final computedEvidence = backendEvidenceTerms.isEmpty
          ? _matchEvidenceTerms(reflectionText)
          : backendEvidenceTerms;
      final computedFindings = findings.isEmpty
          ? _buildDetectedFindings(
              risk: backendRisk,
              patterns: patterns,
              evidenceTerms: computedEvidence,
            )
          : findings;

      final baseInterpretation =
          (data['interpretation'] as String?)?.trim().isNotEmpty == true
          ? (data['interpretation'] as String).trim()
          : _buildInterpretation(
              reflectionText,
              backendRisk,
              patterns,
              latestCheckIn,
            );
      final interpretation = _ensureDetailedInterpretation(
        baseInterpretation: baseInterpretation,
        text: reflectionText,
        risk: backendRisk,
        patterns: patterns,
        latestCheckIn: latestCheckIn,
      );

      final baseRationale =
          (data['rationale'] as String?)?.trim().isNotEmpty == true
          ? (data['rationale'] as String).trim()
          : _buildRationale(
              risk: backendRisk,
              findings: computedFindings,
              evidenceTerms: computedEvidence,
              latestCheckIn: latestCheckIn,
            );

      final rationale = _ensureDetailedRationale(
        baseRationale: baseRationale,
        text: reflectionText,
        risk: backendRisk,
        findings: computedFindings,
        evidenceTerms: computedEvidence,
        latestCheckIn: latestCheckIn,
      );

      final criticalLanguage = _containsCriticalLanguage(
        reflectionText,
        computedEvidence,
      );
      final detectedRisk = criticalLanguage
          ? RiskLevel.high
          : computedEvidence.isNotEmpty || computedFindings.isNotEmpty
          ? (backendRisk.index > currentRisk.index ? backendRisk : currentRisk)
          : backendRisk;

      final reasoningSummary = _buildReasoningSummary(
        risk: detectedRisk,
        findings: computedFindings,
        evidenceTerms: computedEvidence,
        source: analysisSource,
        latestCheckIn: latestCheckIn,
      );

      final alerts = alertsRaw
          .whereType<Map<String, dynamic>>()
          .map(
            (e) => ProfessionalAlert(
              title: (e['title'] as String?)?.trim().isNotEmpty == true
                  ? (e['title'] as String).trim()
                  : 'Alerta preventiva',
              detail: (e['detail'] as String?)?.trim().isNotEmpty == true
                  ? (e['detail'] as String).trim()
                  : 'Se recomienda seguimiento clínico.',
              createdAt: now,
            ),
          )
          .toList();

      if (criticalLanguage) {
        final alreadyCritical = alerts.any(
          (a) => _containsCriticalLanguage('${a.title} ${a.detail}'),
        );
        if (!alreadyCritical) {
          alerts.add(
            ProfessionalAlert(
              title: 'Alerta alta detectada por comentario',
              detail:
                  'El alumno expreso posibles ideas de autolesion o suicidio. Se recomienda intervencion hoy y activar protocolo de crisis.',
              createdAt: now,
            ),
          );
        }
      }

      final reflectionPatterns = List<String>.from(patterns);
      if (criticalLanguage && !reflectionPatterns.contains('riesgo critico')) {
        reflectionPatterns.add('riesgo critico');
      }

      return ReflectionAnalysis(
        reflection: StudentReflection(
          text: reflectionText,
          createdAt: now,
          patterns: reflectionPatterns.isEmpty
              ? const ['seguimiento general']
              : reflectionPatterns,
          interpretation: interpretation,
          detectedFindings: computedFindings,
          rationale: rationale,
          evidenceTerms: computedEvidence,
          reasoningSummary: reasoningSummary,
          source: analysisSource,
          detectedRisk: detectedRisk,
        ),
        newAlerts: alerts,
        detectedRisk: detectedRisk,
        caseRisk: detectedRisk.index > currentRisk.index
            ? detectedRisk
            : currentRisk,
      );
    } on AiAnalysisException {
      rethrow;
    } catch (_) {
      throw const AiAnalysisException(
        'No hubo respuesta valida del backend IA remoto.',
      );
    }
  }

  static Future<http.Response> _postJsonWithRetry(
    Uri uri,
    Map<String, dynamic> payload,
  ) async {
    Object? lastError;

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(_analysisTimeout);
      } catch (error) {
        lastError = error;
      }
    }

    throw AiAnalysisException(
      lastError is TimeoutException
          ? 'El backend IA remoto tardo demasiado en responder.'
          : 'No hubo respuesta valida del backend IA remoto.',
    );
  }

  static ReflectionAnalysis analyzeReflectionLocal({
    required String reflectionText,
    required RiskLevel currentRisk,
  }) {
    final normalized = _normalizeTextForMatch(reflectionText);
    final now = DateTime.now();

    RiskLevel risk = RiskLevel.low;
    final alerts = <ProfessionalAlert>[];
    final patterns = <String>[];
    final evidenceTerms = _matchEvidenceTerms(reflectionText);

    if (_containsAnyTerms(normalized, _stressWords)) {
      patterns.add('estres');
      risk = RiskLevel.medium;
    }
    if (_containsAnyTerms(normalized, _anxietyWords)) {
      patterns.add('ansiedad');
      risk = RiskLevel.medium;
    }

    final semanticRisk = _inferSemanticRisk(normalized);
    if (semanticRisk.index > risk.index) {
      risk = semanticRisk;
      if (semanticRisk == RiskLevel.high &&
          !patterns.contains('riesgo critico')) {
        patterns.add('riesgo critico');
      }
      if (semanticRisk == RiskLevel.medium &&
          !patterns.contains('malestar emocional')) {
        patterns.add('malestar emocional');
      }
    }

    if (_containsCriticalLanguage(reflectionText, evidenceTerms)) {
      risk = RiskLevel.high;
      patterns.add('riesgo critico');
      alerts.add(
        ProfessionalAlert(
          title: 'Alerta alta detectada por comentario',
          detail:
              'El alumno expreso senales criticas en su input natural. Se recomienda intervencion hoy.',
          createdAt: now,
        ),
      );
    } else if (_containsAnyTerms(normalized, _mediumRiskWords) ||
        patterns.isNotEmpty) {
      risk = RiskLevel.medium;
      if (_containsAnyTerms(normalized, _mediumRiskWords) &&
          !patterns.contains('malestar emocional')) {
        patterns.add('malestar emocional');
      }
      alerts.add(
        ProfessionalAlert(
          title: 'Alerta preventiva',
          detail:
              'Se detectaron indicadores de malestar emocional en comentario libre. Sugerido seguimiento en 24-48h.',
          createdAt: now,
        ),
      );
    }

    final interpretation = _buildInterpretation(
      reflectionText,
      risk,
      patterns.isEmpty ? const ['seguimiento general'] : patterns,
      null,
    );

    final findings = _buildDetectedFindings(
      risk: risk,
      patterns: patterns,
      evidenceTerms: evidenceTerms,
    );

    final baseRationale = _buildRationale(
      risk: risk,
      findings: findings,
      evidenceTerms: evidenceTerms,
      latestCheckIn: null,
    );

    final rationale = _ensureDetailedRationale(
      baseRationale: baseRationale,
      text: reflectionText,
      risk: risk,
      findings: findings,
      evidenceTerms: evidenceTerms,
      latestCheckIn: null,
    );

    final reasoningSummary = _buildReasoningSummary(
      risk: risk,
      findings: findings,
      evidenceTerms: evidenceTerms,
      source: 'local-rule-based',
      latestCheckIn: null,
    );

    return ReflectionAnalysis(
      reflection: StudentReflection(
        text: reflectionText,
        createdAt: now,
        patterns: patterns.isEmpty ? const ['seguimiento general'] : patterns,
        interpretation: interpretation,
        detectedFindings: findings,
        rationale: rationale,
        evidenceTerms: evidenceTerms,
        reasoningSummary: reasoningSummary,
        source: 'local-rule-based',
        detectedRisk: risk,
      ),
      newAlerts: alerts,
      detectedRisk: risk,
      caseRisk: risk.index > currentRisk.index ? risk : currentRisk,
    );
  }

  static List<String> _matchEvidenceTerms(String text) {
    final normalized = _normalizeTextForMatch(text);
    final candidates = <String>{};

    for (final token in _highRiskWords) {
      if (normalized.contains(_normalizeTextForMatch(token))) {
        candidates.add(token);
      }
    }
    for (final token in _mediumRiskWords) {
      if (normalized.contains(_normalizeTextForMatch(token))) {
        candidates.add(token);
      }
    }
    for (final token in _stressWords) {
      if (normalized.contains(_normalizeTextForMatch(token))) {
        candidates.add(token);
      }
    }
    for (final token in _anxietyWords) {
      if (normalized.contains(_normalizeTextForMatch(token))) {
        candidates.add(token);
      }
    }

    for (final token in _highRiskContextPhrases) {
      if (normalized.contains(_normalizeTextForMatch(token))) {
        candidates.add(token);
      }
    }
    for (final token in _mediumRiskContextPhrases) {
      if (normalized.contains(_normalizeTextForMatch(token))) {
        candidates.add(token);
      }
    }

    return candidates.take(6).toList();
  }

  static RiskLevel _inferSemanticRisk(String normalizedText) {
    if (_containsAnyTerms(normalizedText, _highRiskContextPhrases)) {
      return RiskLevel.high;
    }

    if (_containsAnyTerms(normalizedText, _mediumRiskContextPhrases)) {
      return RiskLevel.medium;
    }

    final hopelessnessSignals = [
      'sin sentido',
      'sin salida',
      'no tengo salida',
      'no puedo mas',
      'no valgo',
      'todo esta mal',
    ];
    int hopelessnessCount = 0;
    for (final signal in hopelessnessSignals) {
      if (normalizedText.contains(signal)) {
        hopelessnessCount++;
      }
    }

    if (hopelessnessCount >= 2) {
      return RiskLevel.medium;
    }

    return RiskLevel.low;
  }

  static bool _containsCriticalLanguage(
    String text, [
    List<String> evidenceTerms = const [],
  ]) {
    final normalizedText = _normalizeTextForMatch(text);
    if (_containsAnyTerms(normalizedText, _highRiskWords)) {
      return true;
    }
    if (_containsAnyTerms(normalizedText, _criticalSignalStems)) {
      return true;
    }

    for (final evidence in evidenceTerms) {
      final normalizedEvidence = _normalizeTextForMatch(evidence);
      if (_containsAnyTerms(normalizedEvidence, _criticalSignalStems)) {
        return true;
      }
    }

    return false;
  }

  static bool _containsAnyTerms(String normalizedText, List<String> terms) {
    for (final term in terms) {
      if (normalizedText.contains(_normalizeTextForMatch(term))) {
        return true;
      }
    }
    return false;
  }

  static String _normalizeTextForMatch(String value) {
    final lower = value.toLowerCase();
    final withoutAccents = lower
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n');
    return withoutAccents.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static List<String> _buildDetectedFindings({
    required RiskLevel risk,
    required List<String> patterns,
    required List<String> evidenceTerms,
  }) {
    final findings = <String>[];
    if (patterns.any((p) => p.toLowerCase().contains('ansiedad')) ||
        evidenceTerms.any((e) => e.contains('ansiedad'))) {
      findings.add('senales de ansiedad');
    }
    if (patterns.any((p) => p.toLowerCase().contains('estres')) ||
        evidenceTerms.any((e) => e.contains('estres'))) {
      findings.add('senales de estres');
    }
    if (patterns.any((p) => p.toLowerCase().contains('malestar'))) {
      findings.add('malestar emocional sostenido');
    }
    if (risk == RiskLevel.high) {
      findings.add('indicadores de riesgo critico');
    }
    if (findings.isEmpty && risk == RiskLevel.low) {
      findings.add('sin indicadores criticos en este comentario');
    }
    return findings;
  }

  static String _buildRationale({
    required RiskLevel risk,
    required List<String> findings,
    required List<String> evidenceTerms,
    required DailyCheckIn? latestCheckIn,
  }) {
    final evidence = evidenceTerms.isEmpty
        ? 'no se identificaron palabras gatillo directas'
        : 'se encontraron terminos como ${evidenceTerms.join(', ')}';
    final findingsText = findings.join(', ');

    final checkInContext = latestCheckIn == null
        ? 'No hay check-in reciente para contrastar esta lectura.'
        : 'Se contrasta con WHO-5 ${latestCheckIn.who5Percent}/100, PHQ-2 ${latestCheckIn.phq2Score}/6 y GAD-2 ${latestCheckIn.gad2Score}/6.';

    if (risk == RiskLevel.high) {
      return 'La IA clasifica riesgo alto porque $evidence, lo que se asocia con $findingsText. $checkInContext';
    }
    if (risk == RiskLevel.medium) {
      return 'La IA clasifica riesgo moderado porque $evidence y se observan $findingsText sin evidencia de crisis inmediata. $checkInContext';
    }
    return 'La IA mantiene riesgo bajo porque $evidence y el lenguaje no muestra patrones de urgencia; $findingsText. $checkInContext';
  }

  static String _buildReasoningSummary({
    required RiskLevel risk,
    required List<String> findings,
    required List<String> evidenceTerms,
    required String source,
    required DailyCheckIn? latestCheckIn,
  }) {
    final findingsText = findings.isEmpty
        ? 'sin hallazgos relevantes'
        : findings.join(', ');
    final evidenceText = evidenceTerms.isEmpty
        ? 'sin terminos gatillo'
        : evidenceTerms.join(', ');
    final checkInText = latestCheckIn == null
        ? 'sin check-in previo'
        : 'WHO-5 ${latestCheckIn.who5Percent}/100, PHQ-2 ${latestCheckIn.phq2Score}/6, GAD-2 ${latestCheckIn.gad2Score}/6';

    return 'Fuente $source. La IA concluye ${_riskLabel(risk)} porque identifica $findingsText, usa evidencia $evidenceText y contrasta con $checkInText.';
  }

  static String _ensureDetailedRationale({
    required String baseRationale,
    required String text,
    required RiskLevel risk,
    required List<String> findings,
    required List<String> evidenceTerms,
    required DailyCheckIn? latestCheckIn,
  }) {
    final matchedPhrases = _extractMatchedPhrases(text, evidenceTerms);
    final phraseBlock = matchedPhrases.isEmpty
        ? 'Frase observada: "${_extractEvidence(text)}".'
        : matchedPhrases.map((phrase) => '"$phrase"').join(' | ');

    final connotationBlock = _buildConnotationBlock(evidenceTerms);
    final checkInBlock = latestCheckIn == null
        ? 'No hay check-in previo para contraste en esta lectura.'
        : 'Contraste con check-in: WHO-5 ${latestCheckIn.who5Percent}/100, PHQ-2 ${latestCheckIn.phq2Score}/6, GAD-2 ${latestCheckIn.gad2Score}/6.';
    final findingsBlock = findings.isEmpty
        ? 'sin hallazgos criticos directos'
        : findings.join(', ');

    return '$baseRationale Lectura linguistica concreta: detecto estas frases -> $phraseBlock. '
        '$connotationBlock '
        'Cuando el lenguaje aparece asi, suele asociarse con $findingsBlock y por eso se sostiene ${_riskLabel(risk)}. '
        '$checkInBlock';
  }

  static List<String> _extractMatchedPhrases(
    String text,
    List<String> evidenceTerms,
  ) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return const [];

    final rawSentences = clean
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final sentences = rawSentences.isEmpty ? [clean] : rawSentences;
    final phrases = <String>[];

    for (final term in evidenceTerms) {
      final normalizedTerm = term.toLowerCase();
      for (final sentence in sentences) {
        if (sentence.toLowerCase().contains(normalizedTerm)) {
          if (!phrases.contains(sentence)) {
            phrases.add(
              sentence.length <= 130
                  ? sentence
                  : '${sentence.substring(0, 130)}...',
            );
          }
          break;
        }
      }
      if (phrases.length >= 3) break;
    }

    if (phrases.isEmpty) {
      phrases.add(
        clean.length <= 130 ? clean : '${clean.substring(0, 130)}...',
      );
    }

    return phrases;
  }

  static String _buildConnotationBlock(List<String> evidenceTerms) {
    if (evidenceTerms.isEmpty) {
      return 'No se detectaron palabras gatillo literales, asi que la lectura se apoya en tono general, contexto y check-in.';
    }

    final notes = <String>[];
    for (final term in evidenceTerms.take(4)) {
      notes.add('${term.toLowerCase()} -> ${_connotationForTerm(term)}');
    }

    return 'Connotaciones detectadas: ${notes.join('; ')}.';
  }

  static String _connotationForTerm(String term) {
    final t = term.toLowerCase();
    if (t.contains('ansiedad') ||
        t.contains('ansioso') ||
        t.contains('nervioso') ||
        t.contains('preocup')) {
      return 'hiperactivacion y anticipacion de amenaza';
    }
    if (t.contains('estres') ||
        t.contains('presion') ||
        t.contains('saturado') ||
        t.contains('agotado')) {
      return 'sobrecarga sostenida y fatiga emocional';
    }
    if (t.contains('no duermo')) {
      return 'desregulacion del descanso, asociada a mayor vulnerabilidad emocional';
    }
    if (t.contains('solo')) {
      return 'aislamiento percibido y menor soporte social';
    }
    if (t.contains('llor') || t.contains('triste')) {
      return 'disforia o tristeza clinicamente relevante';
    }
    if (t.contains('me quiero') ||
        t.contains('desaparecer') ||
        t.contains('suicid') ||
        t.contains('hacerme daño')) {
      return 'indicador critico que requiere atencion prioritaria';
    }
    return 'senal emocional relevante en el contexto actual';
  }

  static String _buildInterpretation(
    String text,
    RiskLevel risk,
    List<String> patterns,
    DailyCheckIn? latestCheckIn,
  ) {
    final normalizedPatterns = patterns.isEmpty
        ? const ['seguimiento general']
        : patterns;
    final evidence = _extractEvidence(text);
    final riskReason = _riskReason(risk, normalizedPatterns, latestCheckIn);
    final recommendation = _professionalRecommendation(risk);

    return 'La IA detecta ${_riskLabel(risk)} en este comentario. '
        'Identifico patrones de ${normalizedPatterns.join(', ')} y me baso en expresiones como "$evidence". '
        '$riskReason '
        'Por ello, $recommendation';
  }

  static String _ensureDetailedInterpretation({
    required String baseInterpretation,
    required String text,
    required RiskLevel risk,
    required List<String> patterns,
    required DailyCheckIn? latestCheckIn,
  }) {
    if (baseInterpretation.length >= 170 &&
        baseInterpretation.contains('porque')) {
      return baseInterpretation;
    }

    final normalizedPatterns = patterns.isEmpty
        ? const ['seguimiento general']
        : patterns;
    final evidence = _extractEvidence(text);
    final reason = _riskReason(risk, normalizedPatterns, latestCheckIn);
    final recommendation = _professionalRecommendation(risk);

    return '$baseInterpretation Detalle clinico: se identifican ${normalizedPatterns.join(', ')} y evidencia textual "$evidence". '
        'La clasificacion se sostiene porque $reason '
        'Recomendacion para profesional: $recommendation';
  }

  static String _riskLabel(RiskLevel risk) {
    switch (risk) {
      case RiskLevel.high:
        return 'riesgo alto';
      case RiskLevel.medium:
        return 'riesgo moderado';
      case RiskLevel.low:
        return 'riesgo bajo';
    }
  }

  static String _extractEvidence(String text) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return 'comentario breve sin detalle adicional';
    if (clean.length <= 90) return clean;
    return '${clean.substring(0, 90)}...';
  }

  static String _riskReason(
    RiskLevel risk,
    List<String> patterns,
    DailyCheckIn? latestCheckIn,
  ) {
    final fromCheckIn = latestCheckIn == null
        ? ''
        : 'ademas, el ultimo check-in fue WHO-5 ${latestCheckIn.who5Percent}/100, PHQ-2 ${latestCheckIn.phq2Score}/6 y GAD-2 ${latestCheckIn.gad2Score}/6.';

    if (risk == RiskLevel.high) {
      return 'el contenido sugiere malestar intenso y posible desregulacion emocional; ${patterns.join(', ')} aparecen junto con frases de alta carga. $fromCheckIn';
    }
    if (risk == RiskLevel.medium) {
      return 'aparecen indicadores consistentes de carga emocional sostenida (${patterns.join(', ')}) sin evidencia directa de crisis aguda. $fromCheckIn';
    }
    return 'no se observan senales criticas en el lenguaje, aunque conviene mantener monitoreo preventivo. $fromCheckIn';
  }

  static String _professionalRecommendation(RiskLevel risk) {
    if (risk == RiskLevel.high) {
      return 'se sugiere contacto profesional prioritario hoy, validacion de red de apoyo y seguimiento cercano.';
    }
    if (risk == RiskLevel.medium) {
      return 'se recomienda entrevista breve en 24-72h, psicoeducacion y monitoreo de cambios en los proximos dias.';
    }
    return 'se recomienda reforzar habitos protectores y repetir check-in diario para detectar variaciones tempranas.';
  }

  static String _riskToWire(RiskLevel risk) {
    switch (risk) {
      case RiskLevel.low:
        return 'low';
      case RiskLevel.medium:
        return 'medium';
      case RiskLevel.high:
        return 'high';
    }
  }

  static RiskLevel _riskFromWire(String value) {
    switch (value.toLowerCase()) {
      case 'high':
        return RiskLevel.high;
      case 'medium':
        return RiskLevel.medium;
      default:
        return RiskLevel.low;
    }
  }
}

class _CheckInItem {
  final String id;
  final ClinicalScale scale;
  final String question;

  const _CheckInItem({
    required this.id,
    required this.scale,
    required this.question,
  });
}

class _ScaleOption {
  final int value;
  final String label;

  const _ScaleOption(this.value, this.label);
}

class SensorContext {
  final double sleepHours;
  final int screenMinutes;
  final int steps;
  final int restingHeartRate;

  SensorContext({
    required this.sleepHours,
    required this.screenMinutes,
    required this.steps,
    required this.restingHeartRate,
  });

  SensorContext copyWith({
    double? sleepHours,
    int? screenMinutes,
    int? steps,
    int? restingHeartRate,
  }) {
    return SensorContext(
      sleepHours: sleepHours ?? this.sleepHours,
      screenMinutes: screenMinutes ?? this.screenMinutes,
      steps: steps ?? this.steps,
      restingHeartRate: restingHeartRate ?? this.restingHeartRate,
    );
  }

  Map<String, dynamic> toJson() => {
    'sleepHours': sleepHours,
    'screenMinutes': screenMinutes,
    'steps': steps,
    'restingHeartRate': restingHeartRate,
  };
}
