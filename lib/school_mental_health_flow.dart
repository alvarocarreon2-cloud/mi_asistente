import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

  const RealtimePollResult({
    required this.events,
    required this.latestEventId,
  });
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

    await _post(
      '/events/publish',
      {
        'role': 'student',
        'userId': userId,
        'title': 'Nueva cita pendiente',
        'detail': 'Tienes cita a las $hh:$mm. Motivo: $reason',
        'type': 'appointment_created',
        'payload': {
          'appointmentId': appointmentId,
          'startsAtIso': startsAt.toIso8601String(),
        },
      },
    );
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

    await _post(
      '/events/publish',
      {
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
      },
    );
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
        return RealtimePollResult(events: const [], latestEventId: afterEventId);
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return RealtimePollResult(events: const [], latestEventId: afterEventId);
      }

      final rawEvents = decoded['events'];
      final events = rawEvents is List
          ? rawEvents
              .whereType<Map<String, dynamic>>()
              .map((raw) => RealtimeEventItem(
                    id: (raw['id'] is num) ? (raw['id'] as num).toInt() : 0,
              title: (raw['title'] ?? '').toString().trim(),
              detail: (raw['detail'] ?? '').toString().trim(),
                  ))
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
    await _post(
      '/appointments/sync-student',
      {
        'studentName': studentName,
        'appointments': appointments,
      },
    );
  }

  Future<List<Map<String, dynamic>>> fetchAppointmentsByStudent({
    required String studentName,
  }) async {
    final uri = _uriFor('/appointments/by-student').replace(
      queryParameters: {'studentName': studentName},
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) return const [];
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
      if (response.statusCode < 200 || response.statusCode >= 300) return const {};
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
        result[name] = rawAppointments.whereType<Map<String, dynamic>>().toList();
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
    await _post(
      '/treatments/sync-student',
      {
        'studentName': studentName,
        'plans': plans,
      },
    );
  }

  Future<List<Map<String, dynamic>>> fetchTreatmentPlansByStudent({
    required String studentName,
  }) async {
    final uri = _uriFor('/treatments/by-student').replace(
      queryParameters: {'studentName': studentName},
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) return const [];
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const [];
      final raw = decoded['plans'];
      if (raw is! List) return const [];
      return raw.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>> fetchAllTreatmentPlans() async {
    final uri = _uriFor('/treatments/all');
    try {
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) return const {};
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

  Uri _uriFor(String path) {
    final base = _defaultPublicBackendUrl.endsWith('/')
        ? _defaultPublicBackendUrl.substring(0, _defaultPublicBackendUrl.length - 1)
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
    _appointmentsByStudent[_studentCase.studentName] = _studentCase.appointments;
    _treatmentsByStudent[_studentCase.studentName] = _studentCase.treatmentPlans;
    for (final demo in _demoStudents) {
      _appointmentsByStudent[demo.studentName] = demo.appointments;
      _treatmentsByStudent[demo.studentName] = demo.treatmentPlans;
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
    final students = [
      _studentCase,
      ..._demoStudents,
    ];

    final withAppointments = students.map((student) {
      final appointments = _appointmentsByStudent[student.studentName] ??
          student.appointments;
      final treatmentPlans = _treatmentsByStudent[student.studentName] ??
          student.treatmentPlans;
      return student.copyWith(
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
    setState(() {
      _studentCase = _studentCase.copyWith(
        checkIns: [..._studentCase.checkIns, checkIn],
        riskLevel: _mergeRisk(_studentCase.riskLevel, checkIn.riskLevel),
      );
      _appointmentsByStudent[_studentCase.studentName] = _studentCase.appointments;
      _treatmentsByStudent[_studentCase.studentName] = _studentCase.treatmentPlans;
    });
  }

  void _onReflectionSubmitted(ReflectionAnalysis analysis) {
    setState(() {
      _studentCase = _studentCase.copyWith(
        reflections: [..._studentCase.reflections, analysis.reflection],
        alerts: [..._studentCase.alerts, ...analysis.newAlerts],
        riskLevel: _mergeRisk(_studentCase.riskLevel, analysis.caseRisk),
      );
      _appointmentsByStudent[_studentCase.studentName] = _studentCase.appointments;
      _treatmentsByStudent[_studentCase.studentName] = _studentCase.treatmentPlans;
    });
  }

  Future<void> _assignTreatmentPlan(TreatmentPlan plan, String studentName) async {
    final current = _treatmentsByStudent[studentName] ?? const <TreatmentPlan>[];
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

    await _syncTreatmentPlansToBackend(studentName: studentName, plans: updated);
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
    final current = _treatmentsByStudent[studentName] ?? const <TreatmentPlan>[];
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

    await _syncTreatmentPlansToBackend(studentName: studentName, plans: updated);
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
    final current = _appointmentsByStudent[currentStudentName] ??
        _studentCase.appointments;

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
    }).toList()
      ..sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));

    final didChangeStatus = previous != null && previous!.status != response.status;

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
      return RoleAccessScreen(onRoleSelected: _setRole);
    }

    final isStudent = _activeRole == AppRole.student;

    final body = isStudent
        ? (!_checkInCompletedToday
              ? DailyCheckInScreen(onCompleted: _onCheckInCompleted)
              : StudentAiHome(
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
                ))
        : ProfessionalDashboard(
            students: _professionalStudents,
            onScheduleAppointment: _scheduleAppointment,
            notifications: _professionalNotifications,
            onAssignTreatmentPlan: _assignTreatmentPlan,
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isStudent
              ? 'Seguimiento del Alumno'
              : 'Dashboard Profesional',
        ),
        actions: [
          IconButton(
            tooltip: widget.isDarkMode ? 'Modo claro' : 'Modo oscuro',
            onPressed: widget.onToggleThemeMode,
            icon: Icon(
              widget.isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            ),
          ),
          IconButton(
            tooltip: 'Cambiar perfil',
            onPressed: _logoutRole,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: body,
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
    _realtimePollTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) {
        unawaited(_pollRealtimeEventsOnce());
        unawaited(_syncAppointmentsFromBackendOnce());
      },
    );
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

  Future<void> _publishTreatmentEvent({
    required String role,
    required String userId,
    required String title,
    required String detail,
  }) async {
    await _pushBridgeService._post(
      '/events/publish',
      {
        'role': role,
        'userId': userId,
        'title': title,
        'detail': detail,
        'type': 'treatment_update',
      },
    );
  }

  Future<void> _syncAppointmentsFromBackendOnce() async {
    if (_activeRole == AppRole.student) {
      final rawList = await _pushBridgeService.fetchAppointmentsByStudent(
        studentName: _studentCase.studentName,
      );
      final rawPlans = await _pushBridgeService.fetchTreatmentPlansByStudent(
        studentName: _studentCase.studentName,
      );
      final parsed = rawList.map(_appointmentFromJson).whereType<ProfessionalAppointment>().toList()
        ..sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));
      final parsedPlans = rawPlans.map(_treatmentPlanFromJson).whereType<TreatmentPlan>().toList();

      if (!mounted) return;
      setState(() {
        _appointmentsByStudent[_studentCase.studentName] = parsed;
        _treatmentsByStudent[_studentCase.studentName] = parsedPlans;
        _studentCase = _studentCase.copyWith(
          appointments: parsed,
          treatmentPlans: parsedPlans,
        );
      });
      return;
    }

    if (_activeRole == AppRole.professional) {
      final all = await _pushBridgeService.fetchAllAppointments();
      final allPlans = await _pushBridgeService.fetchAllTreatmentPlans();
      if (!mounted) return;
      setState(() {
        all.forEach((studentName, rawAppointments) {
          final parsed = rawAppointments
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
        ? rawHistory
            .whereType<Map<String, dynamic>>()
            .map((eventRaw) {
              final changedAt = DateTime.tryParse((eventRaw['changedAt'] ?? '').toString()) ??
                  DateTime.now();
              return AppointmentStatusEvent(
                status: _statusFromString((eventRaw['status'] ?? '').toString()),
                actor: _actorFromString((eventRaw['actor'] ?? '').toString()),
                changedAt: changedAt,
                note: (eventRaw['note'] ?? '').toString(),
              );
            })
            .toList()
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
    final createdAt = DateTime.tryParse((raw['createdAt'] ?? '').toString()) ?? DateTime.now();
    final rawTasks = raw['tasks'];
    final tasks = rawTasks is List
        ? rawTasks.whereType<Map<String, dynamic>>().map((taskRaw) {
            return TreatmentTask(
              id: (taskRaw['id'] ?? '').toString(),
              title: (taskRaw['title'] ?? '').toString(),
              completed: taskRaw['completed'] == true,
              completedAt: taskRaw['completedAt'] == null
                  ? null
                  : DateTime.tryParse(taskRaw['completedAt'].toString()),
            );
          }).where((task) => task.id.isNotEmpty && task.title.isNotEmpty).toList()
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

class RoleAccessScreen extends StatelessWidget {
  final ValueChanged<AppRole> onRoleSelected;

  const RoleAccessScreen({
    super.key,
    required this.onRoleSelected,
  });

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
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontSize: 15,
                    ),
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

  const StudentAiHome({
    super.key,
    required this.studentCase,
    required this.onReflectionSubmitted,
    required this.onAppointmentResponse,
    required this.onToggleTreatmentTask,
  });

  @override
  State<StudentAiHome> createState() => _StudentAiHomeState();
}

class _StudentAiHomeState extends State<StudentAiHome> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _backendController = TextEditingController();
  bool _isSending = false;
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final latest = widget.studentCase.latestCheckIn;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final pendingAppointments = widget.studentCase.appointments
        .where((appointment) => appointment.status == AppointmentStatus.pending)
        .toList()
      ..sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));
    final confirmedAppointments = widget.studentCase.appointments
        .where((appointment) => appointment.status == AppointmentStatus.confirmed)
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
              padding: EdgeInsets.fromLTRB(16, 16, 16, 120 + keyboardInset),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Mi espacio',
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'SF Pro Display',
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        latest == null
                            ? 'Todavia no registras tu check-in de hoy.'
                            : 'Tu check-in de hoy ya quedo registrado. Seguimos acompanando tu proceso paso a paso.',
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'SF Pro Text',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _infoChip(
                            icon: Icons.calendar_today_outlined,
                            label: confirmedAppointments.isEmpty
                                ? 'Sin citas confirmadas'
                                : '${confirmedAppointments.length} cita(s) confirmada(s)',
                          ),
                          _infoChip(
                            icon: Icons.task_alt_outlined,
                            label: treatmentPlans.isEmpty
                                ? 'Sin tareas asignadas'
                                : '${treatmentPlans.expand((plan) => plan.tasks).where((task) => task.completed).length}/${treatmentPlans.expand((plan) => plan.tasks).length} tareas listas',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _openChatSettings,
                          icon: const Icon(Icons.tune, color: Colors.white),
                          label: const Text(
                            'Ajustes de conexion',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _studentSection(
                  title: 'Citas',
                  icon: Icons.event_available_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (pendingAppointments.isEmpty && confirmedAppointments.isEmpty)
                        Text(
                          'No tienes citas registradas por ahora.',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      if (pendingAppointments.isNotEmpty) ...[
                        Text(
                          'Pendientes de confirmar',
                          style: TextStyle(
                            color: Colors.orange[800],
                            fontFamily: 'SF Pro Display',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...pendingAppointments.map((appointment) {
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
                                              content: Text('Avisaste que no puedes asistir en ese horario.'),
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
                                              content: Text('Confirmaste tu disponibilidad para la cita.'),
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
                      if (confirmedAppointments.isNotEmpty) ...[
                        Text(
                          'Proximas',
                          style: TextStyle(
                            color: Colors.green[800],
                            fontFamily: 'SF Pro Display',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...confirmedAppointments.take(3).map((appointment) {
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
                  ),
                ),
                const SizedBox(height: 12),
                _studentSection(
                  title: 'Tratamiento',
                  icon: Icons.favorite_outline,
                  child: treatmentPlans.isEmpty
                      ? Text(
                          'Tu profesional aun no te ha compartido tareas o seguimiento.',
                          style: TextStyle(color: Colors.grey[700]),
                        )
                      : Column(
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
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                    );
                                  }),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                ),
                const SizedBox(height: 12),
                _studentSection(
                  title: 'Registro personal',
                  icon: Icons.edit_note_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                            border: Border.all(color: Colors.purple.shade100),
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
              ],
            ),
          ),
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
            'Gracias por tu confianza y por tomarte este tiempo. Tu mensaje quedo guardado.',
          ),
        ),
      );
    } on AiAnalysisException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
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
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.16)),
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

  const AppointmentScheduleResult({
    required this.ok,
    required this.message,
  });
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

  String? _selectedStudentName;
  final TextEditingController _reasonController = TextEditingController(
    text: 'Seguimiento clinico preventivo por riesgo detectado.',
  );
  final TextEditingController _treatmentTitleController = TextEditingController(
    text: 'Plan semanal de autocuidado',
  );
  final TextEditingController _treatmentSummaryController = TextEditingController(
    text: 'Pequenas acciones diarias para sostener rutina, descanso y regulacion emocional.',
  );
  final TextEditingController _treatmentTasksController = TextEditingController(
    text: 'Dormir antes de las 11 pm\nCaminar 15 minutos\nRegistrar una emocion del dia',
  );
  DateTime _selectedDateTime = DateTime.now().add(const Duration(days: 1));
  int _selectedDurationMinutes = 45;
  bool _scheduling = false;
  bool _isUsingAutoSlot = true;
  AppointmentStatus? _agendaStatusFilter;

  @override
  void initState() {
    super.initState();
    if (widget.students.isNotEmpty) {
      _selectedStudentName = widget.students.first.studentName;
    }
    _applySuggestedSlot();
  }

  @override
  void didUpdateWidget(covariant ProfessionalDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final names = widget.students.map((s) => s.studentName).toSet();
    if (_selectedStudentName == null && widget.students.isNotEmpty) {
      _selectedStudentName = widget.students.first.studentName;
    } else if (_selectedStudentName != null && !names.contains(_selectedStudentName)) {
      _selectedStudentName = widget.students.isEmpty
          ? null
          : widget.students.first.studentName;
    }

    if (_isUsingAutoSlot) {
      _applySuggestedSlot();
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _treatmentTitleController.dispose();
    _treatmentSummaryController.dispose();
    _treatmentTasksController.dispose();
    super.dispose();
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
      (a, b) => a.appointment.scheduledFor.compareTo(b.appointment.scheduledFor),
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
          slot.add(Duration(minutes: durationMinutes)).isAtSameMomentAs(dayEnd)) {
        if (!_hasOverlap(slot, durationMinutes)) {
          return slot;
        }
        slot = slot.add(const Duration(minutes: _slotStepMinutes));
      }
    }

    return _roundUpToStep(
      from.add(const Duration(days: 1)),
      _slotStepMinutes,
    );
  }

  DateTime _roundUpToStep(DateTime dateTime, int stepMinutes) {
    final remainder = dateTime.minute % stepMinutes;
    final needsRound = remainder != 0 || dateTime.second != 0 || dateTime.millisecond != 0;
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
      final overlaps = candidateStart.isBefore(end) && candidateEnd.isAfter(start);
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
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
    final alerts = selectedStudent?.alerts.reversed.take(5).toList() ??
        const <ProfessionalAlert>[];
    final treatmentPlans = selectedStudent?.treatmentPlans ?? const <TreatmentPlan>[];
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
            ),
            _kpiTile(
              title: 'Riesgo Alto',
              value: '$highRisk',
              subtitle: 'Atencion prioritaria',
              icon: Icons.priority_high_rounded,
              accent: const Color(0xFFB42318),
            ),
            _kpiTile(
              title: 'Riesgo Medio',
              value: '$mediumRisk',
              subtitle: 'Monitoreo cercano',
              icon: Icons.monitor_heart_outlined,
              accent: const Color(0xFFB54708),
            ),
            _kpiTile(
              title: 'Citas Hoy',
              value: '$appointmentsToday',
              subtitle: 'Agenda del dia',
              icon: Icons.today_outlined,
            ),
          ],
        );

        final headerCard = _surfaceCard(
          title: 'Panel Clinico Profesional',
          subtitle:
              'Vista operativa para triage, seguimiento y programacion de citas sin empalmes.',
          icon: Icons.grid_view_rounded,
          child: kpiRow,
        );

        final patientPanel = _surfaceCard(
          title: 'Pacientes Priorizados',
          subtitle: 'Ordenados por riesgo y recencia clinica.',
          icon: Icons.people_alt_outlined,
          child: Column(
            children: widget.students.map((student) {
              final latest = student.latestCheckIn;
              final selected = student.studentName == _selectedStudentName;
              final score = latest == null ? '--' : '${latest.wellbeingScore}/100';

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: selected ? Colors.purple.shade50 : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? Colors.purple.shade400 : Colors.grey.shade200,
                    width: selected ? 1.4 : 1,
                  ),
                ),
                child: ListTile(
                  dense: true,
                  onTap: () => setState(() => _selectedStudentName = student.studentName),
                  leading: CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.purple.shade100,
                    backgroundImage: student.photoUrl == null
                        ? null
                        : NetworkImage(student.photoUrl!),
                    child: student.photoUrl == null
                        ? Text(
                            student.studentName.characters.first,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          )
                        : null,
                  ),
                  title: Text(
                    student.studentName,
                    style: const TextStyle(
                      fontFamily: 'SF Pro Text',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'Score $score · Citas ${student.appointments.length}',
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontFamily: 'SF Pro Text',
                    ),
                  ),
                  trailing: RiskPill(level: student.riskLevel),
                ),
              );
            }).toList(),
          ),
        );

        final detailPanel = _surfaceCard(
          title: selectedStudent == null
              ? 'Resumen del Paciente'
              : 'Resumen de ${selectedStudent.studentName}',
          subtitle: 'Estado actual, alertas y hallazgos recientes.',
          icon: Icons.badge_outlined,
          child: selectedStudent == null
              ? Text(
                  'Selecciona un paciente para ver su detalle clinico.',
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
                    if (selectedStudent.latestCheckIn != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
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
                    Text(
                      'Tratamiento Activo',
                      style: TextStyle(
                        color: Colors.purple[800],
                        fontFamily: 'SF Pro Display',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (treatmentPlans.isEmpty)
                      Text(
                        'Sin plan asignado todavia.',
                        style: TextStyle(color: Colors.grey[700]),
                      )
                    else
                      ...treatmentPlans.take(2).map((plan) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                plan.title,
                                style: const TextStyle(
                                  fontFamily: 'SF Pro Text',
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (plan.summary.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(plan.summary),
                              ],
                              const SizedBox(height: 8),
                              ...plan.tasks.map((task) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    children: [
                                      Icon(
                                        task.completed
                                            ? Icons.check_circle_rounded
                                            : Icons.radio_button_unchecked,
                                        size: 18,
                                        color: task.completed
                                            ? Colors.green.shade700
                                            : Colors.grey.shade500,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(task.title)),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        );
                      }),
                    const SizedBox(height: 12),
                    Text(
                      'Alertas Recientes',
                      style: TextStyle(
                        color: Colors.purple[800],
                        fontFamily: 'SF Pro Display',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (alerts.isEmpty)
                      Text(
                        'Sin alertas registradas para este paciente.',
                        style: TextStyle(color: Colors.grey[700]),
                      )
                    else
                      ...alerts.map((alert) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E8),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFF7D8A0)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.orange[700],
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                      }),
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
                    onSelected: (_) => setState(() => _agendaStatusFilter = null),
                  ),
                  ChoiceChip(
                    label: const Text('Pendientes'),
                    selected: _agendaStatusFilter == AppointmentStatus.pending,
                    onSelected: (_) =>
                        setState(() => _agendaStatusFilter = AppointmentStatus.pending),
                  ),
                  ChoiceChip(
                    label: const Text('Confirmadas'),
                    selected: _agendaStatusFilter == AppointmentStatus.confirmed,
                    onSelected: (_) => setState(
                      () => _agendaStatusFilter = AppointmentStatus.confirmed,
                    ),
                  ),
                  ChoiceChip(
                    label: const Text('Rechazadas'),
                    selected: _agendaStatusFilter == AppointmentStatus.declined,
                    onSelected: (_) =>
                        setState(() => _agendaStatusFilter = AppointmentStatus.declined),
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
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Paciente')),
                      DataColumn(label: Text('Inicio')),
                      DataColumn(label: Text('Fin')),
                      DataColumn(label: Text('Estado')),
                      DataColumn(label: Text('Auditoria')),
                      DataColumn(label: Text('Motivo')),
                    ],
                    rows: _filteredAgendaItems.map((entry) {
                      final start = entry.appointment.scheduledFor;
                      final end = entry.appointment.endAt;
                      final startLabel = _formatDate(start);
                      final endLabel =
                          '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
                      final latestEvent = entry.appointment.statusHistory.isEmpty
                          ? null
                          : entry.appointment.statusHistory.last;
                      final auditLabel = latestEvent == null
                          ? '-'
                          : '${_actorLabel(latestEvent.actor)} · ${_formatDate(latestEvent.changedAt)}';

                      return DataRow(
                        cells: [
                          DataCell(Text(entry.student.studentName)),
                          DataCell(Text(startLabel)),
                          DataCell(Text(endLabel)),
                          DataCell(
                            _appointmentStatusBadge(entry.appointment.status),
                          ),
                          DataCell(
                            SizedBox(
                              width: 220,
                              child: Text(
                                auditLabel,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 280,
                              child: Text(
                                entry.appointment.reason,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
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
                          .where((item) =>
                              item.appointment.status ==
                              AppointmentStatus.pending)
                          .length,
                      const Color(0xFFB54708),
                    ),
                    _statusMetric(
                      'Confirmadas',
                      _agendaItems
                          .where((item) =>
                              item.appointment.status ==
                              AppointmentStatus.confirmed)
                          .length,
                      const Color(0xFF067647),
                    ),
                    _statusMetric(
                      'Rechazadas',
                      _agendaItems
                          .where((item) =>
                              item.appointment.status ==
                              AppointmentStatus.declined)
                          .length,
                      const Color(0xFFB42318),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _selectedStudentName,
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
                  setState(() => _selectedStudentName = value);
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
                value: _selectedDurationMinutes,
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
              colors: [Colors.grey.shade100, Colors.purple.shade50],
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
                    color: Colors.purple.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: Colors.purple.shade700, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: Colors.purple[800],
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

  Widget _appointmentStatusBadge(AppointmentStatus status) {
    switch (status) {
      case AppointmentStatus.pending:
        return _pill('Pendiente', const Color(0xFFFFF4E5), const Color(0xFFB54708));
      case AppointmentStatus.confirmed:
        return _pill('Confirmada', const Color(0xFFE9F9EE), const Color(0xFF067647));
      case AppointmentStatus.declined:
        return _pill('Rechazada', const Color(0xFFFFE3E3), const Color(0xFFB42318));
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withOpacity(0.35)),
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
    final color = accent ?? Colors.purple.shade700;
    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
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
