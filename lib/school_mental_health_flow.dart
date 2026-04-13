import 'package:flutter/material.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SchoolMentalHealthFlow extends StatefulWidget {
  const SchoolMentalHealthFlow({super.key});

  @override
  State<SchoolMentalHealthFlow> createState() => _SchoolMentalHealthFlowState();
}

class _SchoolMentalHealthFlowState extends State<SchoolMentalHealthFlow> {
  int _selectedTab = 0;
  StudentCase _studentCase = StudentCase.empty();

  bool get _checkInCompletedToday {
    final checkIn = _studentCase.latestCheckIn;
    if (checkIn == null) return false;
    final now = DateTime.now();
    return checkIn.date.year == now.year && checkIn.date.month == now.month && checkIn.date.day == now.day;
  }

  void _onCheckInCompleted(DailyCheckIn checkIn) {
    setState(() {
      _studentCase = _studentCase.copyWith(
        checkIns: [..._studentCase.checkIns, checkIn],
        riskLevel: _mergeRisk(_studentCase.riskLevel, checkIn.riskLevel),
      );
    });
  }

  void _onAiInteraction(AiExchange exchange) {
    setState(() {
      _studentCase = _studentCase.copyWith(
        messages: [..._studentCase.messages, exchange.userMessage, exchange.aiMessage],
        alerts: [..._studentCase.alerts, ...exchange.newAlerts],
        riskLevel: _mergeRisk(_studentCase.riskLevel, exchange.detectedRisk),
      );
    });
  }

  void _scheduleAppointment(String reason) {
    final appointment = ProfessionalAppointment(
      scheduledFor: DateTime.now().add(const Duration(days: 1, hours: 10)),
      reason: reason,
      createdAt: DateTime.now(),
    );

    setState(() {
      _studentCase = _studentCase.copyWith(
        appointments: [..._studentCase.appointments, appointment],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final body = _selectedTab == 0
        ? (!_checkInCompletedToday
            ? DailyCheckInScreen(onCompleted: _onCheckInCompleted)
            : StudentAiHome(
                studentCase: _studentCase,
                onAiInteraction: _onAiInteraction,
              ))
        : ProfessionalDashboard(
            studentCase: _studentCase,
            onScheduleAppointment: _scheduleAppointment,
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedTab == 0 ? 'Seguimiento del Alumno' : 'Dashboard Profesional'),
      ),
      body: body,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedTab,
        selectedItemColor: Colors.purple[700],
        unselectedItemColor: Colors.grey[500],
        onTap: (value) => setState(() => _selectedTab = value),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.psychology_outlined),
            label: 'Alumno',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.monitor_heart_outlined),
            label: 'Profesional',
          ),
        ],
      ),
    );
  }

  RiskLevel _mergeRisk(RiskLevel current, RiskLevel incoming) {
    if (incoming.index > current.index) return incoming;
    return current;
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
      question: 'En los últimos 14 días: sentirse decaído, triste o sin esperanza.',
    ),
    _CheckInItem(
      id: 'gad2_1',
      scale: ClinicalScale.gad2,
      question: 'En los últimos 14 días: sentirse nervioso, ansioso o al límite.',
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

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Check-in clínico breve',
            style: TextStyle(
              color: Colors.purple[800],
              fontFamily: 'SF Pro Display',
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Instrumentos validados: WHO-5, PHQ-2 y GAD-2. No reemplaza una evaluación profesional.',
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pregunta ${_index + 1} de ${_questions.length}',
                    style: TextStyle(
                      color: Colors.purple[500],
                      fontFamily: 'SF Pro Text',
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: options.map((option) {
                      final score = option.value;
                      final selected = _answers[_index] == score;
                      return ChoiceChip(
                        label: Text(option.label),
                        selected: selected,
                        onSelected: (_) => setState(() => _answers[_index] = score),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
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
                  child: Text(_index == _questions.length - 1 ? 'Finalizar' : 'Siguiente'),
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

    final who5Raw = who5Indexes.fold<int>(0, (sum, i) => sum + (_answers[i] ?? 0));
    final phq2Raw = phq2Indexes.fold<int>(0, (sum, i) => sum + (_answers[i] ?? 0));
    final gad2Raw = gad2Indexes.fold<int>(0, (sum, i) => sum + (_answers[i] ?? 0));

    final who5Percent = (who5Raw * 4).clamp(0, 100);
    final combinedDistress = ((phq2Raw + gad2Raw) / 12 * 100).round();
    final healthScore = (who5Percent * 0.65 + (100 - combinedDistress) * 0.35).round().clamp(0, 100);

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
    if (phq2 >= 5 || gad2 >= 5 || who5Percent <= 28) {
      return RiskLevel.high;
    }
    if (phq2 >= 3 || gad2 >= 3 || who5Percent <= 50) {
      return RiskLevel.medium;
    }
    return RiskLevel.low;
  }

  String _buildClinicalSummary(RiskLevel risk, int who5Percent, int phq2, int gad2) {
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
  final ValueChanged<AiExchange> onAiInteraction;

  const StudentAiHome({
    super.key,
    required this.studentCase,
    required this.onAiInteraction,
  });

  @override
  State<StudentAiHome> createState() => _StudentAiHomeState();
}

class _StudentAiHomeState extends State<StudentAiHome> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _backendController = TextEditingController();
  bool _isSending = false;
  String _backendUrl = const String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://localhost:8787',
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
      _backendController.text = _backendUrl;
      _sensorContext = SensorContext(
        sleepHours: prefs.getDouble('sensor_sleep_hours') ?? _sensorContext.sleepHours,
        screenMinutes: prefs.getInt('sensor_screen_minutes') ?? _sensorContext.screenMinutes,
        steps: prefs.getInt('sensor_steps') ?? _sensorContext.steps,
        restingHeartRate: prefs.getInt('sensor_rest_hr') ?? _sensorContext.restingHeartRate,
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

    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.purple.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Resumen de hoy',
                style: TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: 18,
                  color: Colors.purple[800],
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                latest == null
                    ? 'Aún sin check-in registrado.'
                    : '${latest.summary} Puntaje bienestar: ${latest.wellbeingScore}/100.',
                style: const TextStyle(fontFamily: 'SF Pro Text'),
              ),
              const SizedBox(height: 6),
              RiskPill(level: widget.studentCase.riskLevel),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _miniTag('Sueno ${_sensorContext.sleepHours.toStringAsFixed(1)}h'),
                  _miniTag('Pantalla ${_sensorContext.screenMinutes}m'),
                  _miniTag('Pasos ${_sensorContext.steps}'),
                  _miniTag('FC ${_sensorContext.restingHeartRate}'),
                ],
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _openChatSettings,
                icon: const Icon(Icons.tune),
                label: const Text('Configurar conexion y datos del dia'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: widget.studentCase.messages.length,
            itemBuilder: (context, index) {
              final msg = widget.studentCase.messages[index];
              final isAi = msg.sender == MessageSender.ai;
              return Align(
                alignment: isAi ? Alignment.centerLeft : Alignment.centerRight,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  constraints: const BoxConstraints(maxWidth: 320),
                  decoration: BoxDecoration(
                    color: isAi ? Colors.white : Colors.purple[100],
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.purple.shade100),
                  ),
                  child: Text(
                    msg.text,
                    style: const TextStyle(fontFamily: 'SF Pro Text'),
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Cuéntame cómo te estás sintiendo...',
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
                        icon: const Icon(Icons.send),
                      ),
              ],
            ),
          ),
        )
      ],
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;
    _controller.clear();

    setState(() => _isSending = true);

    final exchange = await SchoolAiEngine.processMessageSmart(
      text: text,
      currentRisk: widget.studentCase.riskLevel,
      latestCheckIn: widget.studentCase.latestCheckIn,
      recentMessages: widget.studentCase.messages,
      backendUrl: _backendUrl,
      sensorContext: _sensorContext,
    );

    if (!mounted) return;
    setState(() => _isSending = false);

    widget.onAiInteraction(exchange);
  }

  Widget _miniTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(text, style: const TextStyle(fontFamily: 'SF Pro Text', fontSize: 12)),
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
                  const Text('Conexion chat IA', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _backendController,
                    decoration: const InputDecoration(
                      hintText: 'http://TU_IP_LOCAL:8787',
                      labelText: 'Backend URL',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Sueno: ${_sensorContext.sleepHours.toStringAsFixed(1)} h'),
                  Slider(
                    value: _sensorContext.sleepHours,
                    min: 3,
                    max: 10,
                    divisions: 14,
                    onChanged: (v) => setModalState(() => _sensorContext = _sensorContext.copyWith(sleepHours: v)),
                  ),
                  Text('Pantalla: ${_sensorContext.screenMinutes} min'),
                  Slider(
                    value: _sensorContext.screenMinutes.toDouble(),
                    min: 30,
                    max: 720,
                    divisions: 23,
                    onChanged: (v) => setModalState(() => _sensorContext = _sensorContext.copyWith(screenMinutes: v.round())),
                  ),
                  Text('Pasos: ${_sensorContext.steps}'),
                  Slider(
                    value: _sensorContext.steps.toDouble(),
                    min: 0,
                    max: 15000,
                    divisions: 30,
                    onChanged: (v) => setModalState(() => _sensorContext = _sensorContext.copyWith(steps: v.round())),
                  ),
                  Text('FC reposo: ${_sensorContext.restingHeartRate} bpm'),
                  Slider(
                    value: _sensorContext.restingHeartRate.toDouble(),
                    min: 45,
                    max: 130,
                    divisions: 17,
                    onChanged: (v) => setModalState(() => _sensorContext = _sensorContext.copyWith(restingHeartRate: v.round())),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final navigator = Navigator.of(context);
                        final typed = _backendController.text.trim();
                        if (typed.isNotEmpty) {
                          setState(() => _backendUrl = typed);
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
}

class ProfessionalDashboard extends StatelessWidget {
  final StudentCase studentCase;
  final ValueChanged<String> onScheduleAppointment;

  const ProfessionalDashboard({
    super.key,
    required this.studentCase,
    required this.onScheduleAppointment,
  });

  @override
  Widget build(BuildContext context) {
    final alerts = studentCase.alerts.reversed.take(5).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Priorización de Riesgo',
                  style: TextStyle(
                    color: Colors.purple[800],
                    fontFamily: 'SF Pro Display',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                RiskPill(level: studentCase.riskLevel),
                const SizedBox(height: 10),
                Text(
                  'Check-ins registrados: ${studentCase.checkIns.length}\nMensajes IA analizados: ${studentCase.messages.where((m) => m.sender == MessageSender.user).length}',
                  style: const TextStyle(fontFamily: 'SF Pro Text'),
                ),
                if (studentCase.latestCheckIn != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'WHO-5: ${studentCase.latestCheckIn!.who5Percent}/100 | PHQ-2: ${studentCase.latestCheckIn!.phq2Score}/6 | GAD-2: ${studentCase.latestCheckIn!.gad2Score}/6',
                    style: const TextStyle(fontFamily: 'SF Pro Text'),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Alertas Preventivas',
                  style: TextStyle(
                    color: Colors.purple[800],
                    fontFamily: 'SF Pro Display',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                if (alerts.isEmpty)
                  Text(
                    'Sin alertas recientes. Seguimiento estable.',
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontFamily: 'SF Pro Text',
                    ),
                  )
                else
                  ...alerts.map((alert) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.warning_amber_rounded, color: Colors.orange[700]),
                        title: Text(alert.title, style: const TextStyle(fontFamily: 'SF Pro Text')),
                        subtitle: Text(alert.detail, style: TextStyle(color: Colors.grey[700])),
                      )),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gestión de Citas',
                  style: TextStyle(
                    color: Colors.purple[800],
                    fontFamily: 'SF Pro Display',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () => onScheduleAppointment('Seguimiento preventivo por señales detectadas en IA.'),
                  icon: const Icon(Icons.event_available),
                  label: const Text('Programar cita sugerida'),
                ),
                const SizedBox(height: 10),
                if (studentCase.appointments.isEmpty)
                  Text(
                    'No hay citas programadas.',
                    style: TextStyle(color: Colors.grey[700], fontFamily: 'SF Pro Text'),
                  )
                else
                  ...studentCase.appointments.reversed.map((appt) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.calendar_today, color: Colors.purple[400]),
                        title: Text(
                          'Cita: ${_formatDate(appt.scheduledFor)}',
                          style: const TextStyle(fontFamily: 'SF Pro Text'),
                        ),
                        subtitle: Text(appt.reason),
                      )),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    return '${date.day}/${date.month}/${date.year} $hh:$mm';
  }
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

enum MessageSender { user, ai }

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

class ChatMessage {
  final MessageSender sender;
  final String text;
  final DateTime createdAt;

  ChatMessage({
    required this.sender,
    required this.text,
    required this.createdAt,
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
  final DateTime scheduledFor;
  final String reason;
  final DateTime createdAt;

  ProfessionalAppointment({
    required this.scheduledFor,
    required this.reason,
    required this.createdAt,
  });
}

class StudentCase {
  final List<DailyCheckIn> checkIns;
  final List<ChatMessage> messages;
  final List<ProfessionalAlert> alerts;
  final List<ProfessionalAppointment> appointments;
  final RiskLevel riskLevel;

  StudentCase({
    required this.checkIns,
    required this.messages,
    required this.alerts,
    required this.appointments,
    required this.riskLevel,
  });

  factory StudentCase.empty() {
    return StudentCase(
      checkIns: const [],
      messages: [
        ChatMessage(
          sender: MessageSender.ai,
          text: 'Hola. Soy tu asistente de bienestar escolar. Puedes contarme cómo te has sentido hoy.',
          createdAt: DateTime(2026),
        ),
      ],
      alerts: const [],
      appointments: const [],
      riskLevel: RiskLevel.low,
    );
  }

  DailyCheckIn? get latestCheckIn => checkIns.isEmpty ? null : checkIns.last;

  StudentCase copyWith({
    List<DailyCheckIn>? checkIns,
    List<ChatMessage>? messages,
    List<ProfessionalAlert>? alerts,
    List<ProfessionalAppointment>? appointments,
    RiskLevel? riskLevel,
  }) {
    return StudentCase(
      checkIns: checkIns ?? this.checkIns,
      messages: messages ?? this.messages,
      alerts: alerts ?? this.alerts,
      appointments: appointments ?? this.appointments,
      riskLevel: riskLevel ?? this.riskLevel,
    );
  }
}

class AiExchange {
  final ChatMessage userMessage;
  final ChatMessage aiMessage;
  final List<ProfessionalAlert> newAlerts;
  final RiskLevel detectedRisk;

  AiExchange({
    required this.userMessage,
    required this.aiMessage,
    required this.newAlerts,
    required this.detectedRisk,
  });
}

class SchoolAiEngine {
  static const _highRiskWords = [
    'no puedo más',
    'quiero desaparecer',
    'no vale la pena',
    'me quiero hacer daño',
    'nadie me entiende',
  ];

  static const _mediumRiskWords = [
    'ansiedad',
    'me siento solo',
    'estrés',
    'no duermo',
    'lloré',
    'agotado',
  ];

  static Future<AiExchange> processMessageSmart({
    required String text,
    required RiskLevel currentRisk,
    required DailyCheckIn? latestCheckIn,
    required List<ChatMessage> recentMessages,
    required String backendUrl,
    required SensorContext sensorContext,
  }) async {
    try {
      final uri = Uri.parse('${backendUrl.trim()}/ai/wellbeing-chat');
      final payload = {
        'message': text,
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
        'recentMessages': recentMessages
            .take(8)
            .map((m) => {
                  'sender': m.sender == MessageSender.ai ? 'ai' : 'user',
                  'text': m.text,
                })
            .toList(),
              'sensorContext': sensorContext.toJson(),
      };

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return processMessage(text: text, currentRisk: currentRisk);
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = (body['data'] as Map<String, dynamic>?) ?? {};
      final now = DateTime.now();
      final alertsRaw = (data['alerts'] as List<dynamic>?) ?? const [];
      final detectedRisk = _riskFromWire((data['detectedRisk'] as String?) ?? 'low');

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

      final aiText = (data['replyText'] as String?)?.trim().isNotEmpty == true
          ? (data['replyText'] as String).trim()
          : _buildResponse(text, detectedRisk);

      return AiExchange(
        userMessage: ChatMessage(sender: MessageSender.user, text: text, createdAt: now),
        aiMessage: ChatMessage(sender: MessageSender.ai, text: aiText, createdAt: now),
        newAlerts: alerts,
        detectedRisk: detectedRisk.index > currentRisk.index ? detectedRisk : currentRisk,
      );
    } catch (_) {
      return processMessage(text: text, currentRisk: currentRisk);
    }
  }

  static AiExchange processMessage({
    required String text,
    required RiskLevel currentRisk,
  }) {
    final normalized = text.toLowerCase();
    final now = DateTime.now();

    RiskLevel risk = RiskLevel.low;
    final alerts = <ProfessionalAlert>[];

    if (_highRiskWords.any(normalized.contains)) {
      risk = RiskLevel.high;
      alerts.add(
        ProfessionalAlert(
          title: 'Alerta alta detectada por IA',
          detail: 'El alumno expresó señales críticas en conversación. Se recomienda intervención hoy.',
          createdAt: now,
        ),
      );
    } else if (_mediumRiskWords.any(normalized.contains) || currentRisk == RiskLevel.medium) {
      risk = RiskLevel.medium;
      alerts.add(
        ProfessionalAlert(
          title: 'Alerta preventiva',
          detail: 'Se detectaron indicadores de malestar emocional. Sugerido seguimiento en 24-48h.',
          createdAt: now,
        ),
      );
    }

    final aiText = _buildResponse(text, risk);

    return AiExchange(
      userMessage: ChatMessage(sender: MessageSender.user, text: text, createdAt: now),
      aiMessage: ChatMessage(sender: MessageSender.ai, text: aiText, createdAt: now),
      newAlerts: alerts,
      detectedRisk: risk,
    );
  }

  static String _buildResponse(String text, RiskLevel risk) {
    if (risk == RiskLevel.high) {
      return 'Gracias por confiar en mí. Lo que compartes es importante y no estás solo. Voy a sugerir contacto con el profesional de tu institución hoy. ¿Quieres que te ayude a identificar a una persona de apoyo inmediata?';
    }
    if (risk == RiskLevel.medium) {
      return 'Te agradezco que me cuentes esto. Detecto señales de carga emocional. ¿Qué fue lo más difícil del día y qué te ayudaría a sentir un poco más de calma hoy?';
    }
    return 'Gracias por compartirlo. Para seguir cuidando tu bienestar: ¿qué situación te hizo sentir mejor hoy y cuál fue la más retadora?';
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
