import 'dart:convert';

import 'package:http/http.dart' as http;
import 'models.dart';

class TaskAnalysis {
  final String generatedTitle;
  final List<String> planSteps;
  final int estimatedMinutes;
  final int difficulty;
  final int priority;
  final bool needsDeadlineClarification;
  final String clarificationQuestion;
  final DateTime? suggestedDueDate;
  final String source;
  final double confidence;
  final String suggestionReasoning;

  TaskAnalysis({
    required this.generatedTitle,
    required this.planSteps,
    required this.estimatedMinutes,
    required this.difficulty,
    required this.priority,
    required this.needsDeadlineClarification,
    required this.clarificationQuestion,
    required this.suggestedDueDate,
    this.source = 'local',
    this.confidence = 0.65,
    this.suggestionReasoning = '',
  });
}

class TaskAiEstimator {
  static Future<TaskAnalysis> analyzeSmart(
    String input, {
    String? extraDetails,
    DateTime? now,
    List<Pendiente> pendingTasks = const [],
  }) async {
    final local = analyze(
      input,
      extraDetails: extraDetails,
      now: now,
      pendingTasks: pendingTasks,
    );
    final remote = await _analyzeWithRemoteAi(
      input,
      extraDetails: extraDetails,
      now: now,
      pendingTasks: pendingTasks,
    );
    return remote ?? local;
  }

  static TaskAnalysis analyze(
    String input, {
    String? extraDetails,
    DateTime? now,
    List<Pendiente> pendingTasks = const [],
  }) {
    final DateTime referenceNow = now ?? DateTime.now();
    final String full = '${input.trim()} ${extraDetails?.trim() ?? ''}'.toLowerCase();
    final String generatedTitle = _generateTitle(input);

    int minutes = _estimateMinutesLocal(full);
    int difficulty = _estimateDifficultyLocal(full);

    DateTime? dueDate = _extractDueDate(full, referenceNow);
    dueDate ??= _suggestBestDueDate(input, minutes, difficulty, pendingTasks, referenceNow);
    final bool needsClarification = dueDate == null;

    minutes = minutes.clamp(15, 360);
    difficulty = difficulty.clamp(1, 10);

    final int urgency = _urgencyScore(dueDate, referenceNow);
    final int priority = (urgency * 2 + difficulty + _shortTaskBonus(minutes)).clamp(1, 10);
    final List<String> planSteps = _buildSpecificPlan(
      description: input,
      title: generatedTitle,
      estimatedMinutes: minutes,
      pendingTasks: pendingTasks,
    );

    final String reasoning = _generateReasoningText(dueDate, minutes, difficulty, pendingTasks, referenceNow);

    return TaskAnalysis(
      generatedTitle: generatedTitle,
      planSteps: planSteps,
      estimatedMinutes: minutes,
      difficulty: difficulty,
      priority: priority,
      needsDeadlineClarification: needsClarification,
      clarificationQuestion: '¿Para cuándo lo necesitas? (ej. hoy 18:00, mañana, en 2 días)',
      suggestedDueDate: dueDate,
      source: 'local',
      confidence: 0.65,
      suggestionReasoning: reasoning,
    );
  }

  static Future<TaskAnalysis?> _analyzeWithRemoteAi(
    String input, {
    String? extraDetails,
    DateTime? now,
    List<Pendiente> pendingTasks = const [],
  }) async {
    const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
    if (geminiApiKey.isEmpty) return null;

    final DateTime referenceNow = now ?? DateTime.now();
    final String combined = '${input.trim()} ${extraDetails?.trim() ?? ''}'.trim();
    
    // Construir resumen de carga de trabajo semanal
    final String weeklyWorkload = _buildWeeklyWorkloadSummary(pendingTasks, referenceNow);
    
    // Calcular carga de HOY
    final String todayKey = _getDayKey(referenceNow);
    int todayMinutes = 0;
    for (final task in pendingTasks.where((p) => !p.completado)) {
      if (_getDayKey(task.horaAsignada ?? referenceNow) == todayKey) {
        todayMinutes += task.tiempoEstimado;
      }
    }
    final String todayLoadWarning = todayMinutes > 240 
        ? '⚠️ HOY YA ESTÁ MUY CARGADO ($todayMinutes min). NO sugieras hoy a menos que sea urgente.'
        : todayMinutes > 120
        ? '⚠️ Hoy está moderadamente cargado ($todayMinutes min). Distribuye a otros días si es posible.'
        : '';

    final String prompt =
        'ERES UN PLANIFICADOR INTELIGENTE QUE DISTRIBUYE CARGA DE TRABAJO.\n'
        'Responde SOLO JSON válido:\n'
        '{"generated_title": "...", "plan_steps": [...], "estimated_minutes": 45, "difficulty": 5, '
        '"priority": 5, "needs_deadline_clarification": false, "clarification_question": "", '
        '"due_text": "...", "suggestion_reason": "Razón corta en español", "confidence": 0.9}\n\n'
        'CALENDARIO Y CARGA DE TRABAJO:\n'
        '$weeklyWorkload\n'
        '${todayLoadWarning.isEmpty ? '' : '$todayLoadWarning\n'}'
        'Hoy es ${_getDayNameSpanish(referenceNow)} (${referenceNow.day}/${referenceNow.month}).\n\n'
        'NUEVA TAREA:\n$combined\n\n'
        '⚡ INSTRUCCIONES CRÍTICAS (OBLIGATORIAS):\n'
        '1️⃣ NUNCA sugieras el mismo día si ya tiene >3 horas de tareas\n'
        '2️⃣ PREFERENCIA: Busca el día más VACÍO en los próximos 7 días\n'
        '3️⃣ SOLO sugiere hoy si:\n'
        '   - Es urgente (mencionó "hoy", "urgente", "asap")\n'
        '   - Y hoy tiene <2 horas de tareas\n'
        '4️⃣ Tareas complejas (difficulty >7) → días completamente libres\n'
        '5️⃣ due_text DEBE ser específico: "lunes 14:00", "miércoles 10:00", etc.\n'
        '6️⃣ suggestion_reason DEBE explicar BREVEMENTE por qué elegiste ese día (máx 140 caracteres). Ejemplos:\n'
        '   - "Miércoles está vacío, perfecto para una tarea complicada"\n'
        '   - "Hoy tiene poco trabajo y es urgente"\n'
        '   - "Distribuye la carga hacia el jueves que es más disponible"\n'
        '7️⃣ confidence=0.9+ si la fecha hace sentido con la carga\n\n'
        'ESTIMACIÓN:\n'
        '- Tiempo: 15-360 minutos, realista por descomposición\n'
        '- Dificultad y prioridad: 1-10\n'
        'RESPONDE SOLO JSON, sin explicaciones extra.';

    final Map<String, dynamic> geminiPayload = {
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.2,
        'responseMimeType': 'application/json'
      }
    };

    try {
      const String geminiModel = String.fromEnvironment('GEMINI_MODEL', defaultValue: 'gemini-1.5-flash');
      final String url =
          'https://generativelanguage.googleapis.com/v1/models/$geminiModel:generateContent?key=$geminiApiKey';

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(geminiPayload),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final Map<String, dynamic> decoded = jsonDecode(response.body);
      final List<dynamic>? candidates = decoded['candidates'];
      if (candidates == null || candidates.isEmpty) return null;

      final Map<String, dynamic>? content = candidates[0]['content'];
      final List<dynamic>? parts = content?['parts'];
      if (parts == null || parts.isEmpty) return null;

      final String? text = parts[0]['text'];
      if (text == null || text.trim().isEmpty) return null;

      final Map<String, dynamic> ai = jsonDecode(text);

      final String generatedTitle =
          ((ai['generated_title'] as String?) ?? '').trim().isEmpty
              ? _generateTitle(input)
              : (ai['generated_title'] as String).trim();
      final List<String> planSteps = _readPlanSteps(ai['plan_steps']);

      final int minutes = _normalizeMinutes((ai['estimated_minutes'] as num?)?.toInt() ?? 45);
      final int difficulty = (ai['difficulty'] as num?)?.toInt().clamp(1, 10) ?? 5;
      final int priority = (ai['priority'] as num?)?.toInt().clamp(1, 10) ?? 5;
      final bool needsClarification = ai['needs_deadline_clarification'] == true;
      final String clarificationQuestion =
          (ai['clarification_question'] as String?)?.trim().isNotEmpty == true
              ? (ai['clarification_question'] as String).trim()
              : '¿Para cuándo lo necesitas?';
      final String dueText = ((ai['due_text'] as String?) ?? '').toLowerCase().trim();
      DateTime? dueDate = dueText.isEmpty ? null : _extractDueDate(dueText, referenceNow);
      final double confidence =
          ((ai['confidence'] as num?)?.toDouble() ?? 0.8).clamp(0.0, 1.0);
      final String suggestionReason =
          ((ai['suggestion_reason'] as String?) ?? '').trim().isNotEmpty
              ? (ai['suggestion_reason'] as String).trim()
              : _generateReasoningText(dueDate, minutes, difficulty, pendingTasks, referenceNow);

      // FALLBACK: Si Gemini sugiere hoy pero hoy está lleno, força un día mejor
      if (dueDate != null && _getDayKey(dueDate) == todayKey && todayMinutes > 180) {
        dueDate = _suggestBestDueDate(input, minutes, difficulty, pendingTasks, referenceNow);
      }

      return TaskAnalysis(
        generatedTitle: generatedTitle,
        planSteps: planSteps.isNotEmpty
            ? planSteps
            : _buildSpecificPlan(
                description: input,
                title: generatedTitle,
                estimatedMinutes: minutes,
                pendingTasks: pendingTasks,
              ),
        estimatedMinutes: minutes,
        difficulty: difficulty,
        priority: priority,
        needsDeadlineClarification: needsClarification && dueDate == null,
        clarificationQuestion: clarificationQuestion,
        suggestedDueDate: dueDate,
        source: 'gemini',
        confidence: confidence,
        suggestionReasoning: suggestionReason,
      );
    } catch (_) {
      return null;
    }
  }

  static List<String> _readPlanSteps(dynamic value) {
    if (value is! List) return [];
    return value
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .take(6)
        .toList();
  }

  static String _generateTitle(String description) {
    final String clean = description.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return 'Nuevo pendiente';

    final String lower = clean.toLowerCase();
    if (lower.contains('maqueta') && lower.contains('sistema solar')) {
      return 'Maqueta del sistema solar';
    }

    final stopWords = {
      'que', 'para', 'con', 'por', 'del', 'las', 'los', 'una', 'unos', 'unas',
      'hacer', 'crear', 'armar', 'tengo', 'necesito', 'de', 'la', 'el', 'y', 'en',
    };

    final words = clean
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w.replaceAll(RegExp(r'[^a-zA-ZáéíóúÁÉÍÓÚñÑ0-9]'), ''))
        .where((w) => w.isNotEmpty)
        .toList();

    final picked = words
        .where((w) => !stopWords.contains(w.toLowerCase()))
        .take(5)
        .toList();

    final titleWords = picked.isEmpty ? words.take(5).toList() : picked;
    final title = titleWords.join(' ').trim();
    if (title.isEmpty) return 'Nuevo pendiente';
    return title[0].toUpperCase() + title.substring(1);
  }

  static List<String> _buildSpecificPlan({
    required String description,
    required String title,
    required int estimatedMinutes,
    List<Pendiente> pendingTasks = const [],
  }) {
    final String text = description.toLowerCase();
    final int total = estimatedMinutes.clamp(20, 240);
    final int setup = 5;
    final int close = 5;
    final int core = ((total - setup - close) * 0.6).round().clamp(10, 150);
    final int build = (total - setup - close - core).clamp(8, 120);

    String coreStep = 'Desarrolla el bloque principal del entregable.';
    String buildStep = 'Completa contenido y deja versión presentable.';

    if (text.contains('maqueta') || text.contains('diseñ')) {
      coreStep = 'Define estructura, materiales y proporciones de la maqueta.';
      buildStep = 'Arma piezas principales y termina acabados clave.';
    } else if (text.contains('investig') || text.contains('reporte')) {
      coreStep = 'Recolecta evidencia clave y separa ideas por secciones.';
      buildStep = 'Redacta el reporte final con conclusiones accionables.';
    } else if (text.contains('program') || text.contains('api') || text.contains('código')) {
      coreStep = 'Implementa el flujo funcional principal de la tarea.';
      buildStep = 'Prueba, corrige errores y prepara entrega técnica.';
    } else if (text.contains('presentación') || text.contains('exposición')) {
      coreStep = 'Estructura mensaje central y narrativa por diapositiva.';
      buildStep = 'Diseña diapositivas finales y ensaya tiempos de exposición.';
    }

    final String contextStep = pendingTasks.isNotEmpty
        ? 'Ordena este trabajo frente a tus pendientes (elige 1 tarea antes y 1 después para no perder foco).'
        : 'Define el bloque de entrada y salida para mantener continuidad del día.';

    return [
      contextStep,
      'Define objetivo y resultado esperado para "$title" ($setup min).',
      '$coreStep ($core min).',
      '$buildStep ($build min).',
      'Revisión final contra requisitos y próximos pasos ($close min).',
    ].take(6).toList();
  }

  static int _normalizeMinutes(int minutes) {
    final int clamped = minutes.clamp(15, 360);
    final int rounded = ((clamped / 5).round() * 5).clamp(15, 360);
    return rounded;
  }

  static int _estimateMinutesLocal(String full) {
    int minutes = 35;

    final Map<String, int> minuteBoost = {
      'maqueta': 95,
      'presentación': 65,
      'investigación': 70,
      'reporte': 55,
      'documentar': 40,
      'exposición': 55,
      'programar': 75,
      'api': 55,
      'diseñar': 60,
      'estudiar': 50,
      'debug': 45,
      'corregir': 35,
      'sistema solar': 55,
    };

    for (final entry in minuteBoost.entries) {
      if (full.contains(entry.key)) minutes += entry.value;
    }

    final RegExp explicitMinutes = RegExp(r'(\d{1,3})\s*(min|mins|minutos)');
    final RegExp explicitHours = RegExp(r'(\d{1,2}(?:[\.,]\d)?)\s*(h|hr|hrs|hora|horas)');
    final Match? mm = explicitMinutes.firstMatch(full);
    if (mm != null) {
      final int explicit = int.tryParse(mm.group(1) ?? '') ?? minutes;
      return _normalizeMinutes(explicit);
    }
    final Match? hh = explicitHours.firstMatch(full);
    if (hh != null) {
      final String raw = (hh.group(1) ?? '').replaceAll(',', '.');
      final double explicit = double.tryParse(raw) ?? 1.0;
      return _normalizeMinutes((explicit * 60).round());
    }

    if (full.contains('rápido') || full.contains('rapido') || full.contains('fácil') || full.contains('facil')) {
      minutes -= 15;
    }

    if (full.contains('completo') || full.contains('detallado') || full.contains('profesional')) {
      minutes += 30;
    }

    final int words = full.split(RegExp(r'\s+')).where((w) => w.trim().isNotEmpty).length;
    if (words > 16) minutes += 15;
    if (words > 28) minutes += 15;

    return _normalizeMinutes(minutes);
  }

  static int _estimateDifficultyLocal(String full) {
    int difficulty = 4;
    final Map<String, int> difficultyBoost = {
      'maqueta': 2,
      'investigación': 2,
      'programar': 3,
      'api': 2,
      'arquitectura': 3,
      'examen': 3,
      'presentación': 2,
      'debug': 2,
      'integrar': 2,
      'sistema solar': 1,
    };

    for (final entry in difficultyBoost.entries) {
      if (full.contains(entry.key)) difficulty += entry.value;
    }

    if (full.contains('fácil') || full.contains('facil') || full.contains('simple')) {
      difficulty -= 1;
    }
    if (full.contains('complejo') || full.contains('difícil') || full.contains('dificil')) {
      difficulty += 2;
    }

    return difficulty.clamp(1, 10);
  }

  static int _shortTaskBonus(int minutes) {
    if (minutes <= 30) return 2;
    if (minutes <= 60) return 1;
    return 0;
  }

  static int _urgencyScore(DateTime? dueDate, DateTime now) {
    if (dueDate == null) return 2;
    final Duration delta = dueDate.difference(now);
    if (delta.inHours <= 6) return 5;
    if (delta.inHours <= 24) return 4;
    if (delta.inDays <= 3) return 3;
    if (delta.inDays <= 7) return 2;
    return 1;
  }

  static DateTime? _extractDueDate(String text, DateTime now) {
    final RegExp hoursMinutes = RegExp(r'(\d{1,2}):(\d{2})');
    final RegExp hourOnly = RegExp(r'\b(\d{1,2})\s?(am|pm)\b');
    final RegExp hour24Only = RegExp(r'\ba\s+las\s+(\d{1,2})\b');
    int hour = 18;
    int minute = 0;

    final Match? hm = hoursMinutes.firstMatch(text);
    if (hm != null) {
      hour = int.tryParse(hm.group(1) ?? '') ?? 18;
      minute = int.tryParse(hm.group(2) ?? '') ?? 0;
    } else {
      final Match? ho = hourOnly.firstMatch(text);
      if (ho != null) {
        hour = int.tryParse(ho.group(1) ?? '') ?? 18;
        final String meridian = (ho.group(2) ?? '').toLowerCase();
        if (meridian == 'pm' && hour < 12) hour += 12;
        if (meridian == 'am' && hour == 12) hour = 0;
      } else {
        final Match? h24 = hour24Only.firstMatch(text);
        if (h24 != null) {
          hour = int.tryParse(h24.group(1) ?? '') ?? 18;
          if (text.contains('tarde') && hour < 12) hour += 12;
          if (text.contains('noche') && hour < 12) hour += 12;
        }
      }
    }

    if ((text.contains('en la mañana') || text.contains('manana temprano')) && hm == null) {
      hour = 9;
      minute = 0;
    } else if ((text.contains('en la tarde') || text.contains('por la tarde')) && hm == null) {
      hour = 17;
      minute = 0;
    } else if ((text.contains('en la noche') || text.contains('por la noche')) && hm == null) {
      hour = 20;
      minute = 0;
    }

    if (text.contains('hoy') || text.contains('para hoy')) {
      return DateTime(now.year, now.month, now.day, hour, minute);
    }

    if (text.contains('mañana') || text.contains('manana')) {
      final DateTime d = now.add(Duration(days: 1));
      return DateTime(d.year, d.month, d.day, hour, minute);
    }

    final weekdayMap = <String, int>{
      'lunes': DateTime.monday,
      'martes': DateTime.tuesday,
      'miércoles': DateTime.wednesday,
      'miercoles': DateTime.wednesday,
      'jueves': DateTime.thursday,
      'viernes': DateTime.friday,
      'sábado': DateTime.saturday,
      'sabado': DateTime.saturday,
      'domingo': DateTime.sunday,
    };

    for (final entry in weekdayMap.entries) {
      if (text.contains(entry.key)) {
        int days = (entry.value - now.weekday) % 7;
        if (days == 0) days = 7;
        if (text.contains('próximo') || text.contains('proximo')) {
          days += 7;
        }
        final DateTime d = now.add(Duration(days: days));
        return DateTime(d.year, d.month, d.day, hour, minute);
      }
    }

    final RegExp inDays = RegExp(r'en\s+(\d+)\s+d[ií]as');
    final Match? dMatch = inDays.firstMatch(text);
    if (dMatch != null) {
      final int days = int.tryParse(dMatch.group(1) ?? '') ?? 1;
      final DateTime d = now.add(Duration(days: days));
      return DateTime(d.year, d.month, d.day, hour, minute);
    }

    final RegExp inHours = RegExp(r'en\s+(\d+)\s+horas?');
    final Match? hMatch = inHours.firstMatch(text);
    if (hMatch != null) {
      final int h = int.tryParse(hMatch.group(1) ?? '') ?? 2;
      final DateTime d = now.add(Duration(hours: h));
      return DateTime(d.year, d.month, d.day, d.hour, d.minute);
    }

    final RegExp explicitDate = RegExp(r'\b(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?\b');
    final Match? dateMatch = explicitDate.firstMatch(text);
    if (dateMatch != null) {
      final int day = int.tryParse(dateMatch.group(1) ?? '') ?? now.day;
      final int month = int.tryParse(dateMatch.group(2) ?? '') ?? now.month;
      int year = now.year;
      final String? yRaw = dateMatch.group(3);
      if (yRaw != null) {
        year = int.tryParse(yRaw) ?? now.year;
        if (year < 100) year += 2000;
      }
      return DateTime(year, month, day, hour, minute);
    }

    if (text.contains('esta semana')) {
      final int daysUntilFriday = (5 - now.weekday).clamp(0, 6);
      final DateTime d = now.add(Duration(days: daysUntilFriday));
      return DateTime(d.year, d.month, d.day, hour, minute);
    }

    return null;
  }

  static String _buildWeeklyWorkloadSummary(List<Pendiente> pendingTasks, DateTime referenceNow) {
    if (pendingTasks.isEmpty) {
      return '📅 No hay tareas pendientes. Puedes agendar flexiblemente.';
    }

    final Map<String, List<Pendiente>> tasksByDay = {};
    final Map<String, int> minutesByDay = {};

    // Agrupar tareas por día
    for (final task in pendingTasks.where((p) => !p.completado)) {
      final String dayKey = _getDayKey(task.horaAsignada ?? referenceNow);
      tasksByDay.putIfAbsent(dayKey, () => []).add(task);
      minutesByDay[dayKey] = (minutesByDay[dayKey] ?? 0) + task.tiempoEstimado;
    }

    // Construir resumen para los próximos 7 días
    final StringBuffer summary = StringBuffer();
    for (int i = 0; i < 7; i++) {
      final DateTime day = referenceNow.add(Duration(days: i));
      final String dayKey = _getDayKey(day);
      final String dayName = _getDayNameSpanish(day);
      final List<Pendiente> tasks = tasksByDay[dayKey] ?? [];
      final int minutesTotal = minutesByDay[dayKey] ?? 0;
      final int hoursTotal = (minutesTotal / 60).round();

      if (tasks.isEmpty) {
        summary.writeln('• $dayName: Libre (0 horas)');
      } else {
        final String taskNames = tasks.map((t) => t.titulo).join(', ');
        final String loadLevel = hoursTotal < 2 ? '🟢 Ligera' : hoursTotal < 4 ? '🟡 Moderada' : '🔴 Pesada';
        summary.writeln('• $dayName: $loadLevel ($hoursTotal horas) - $taskNames');
      }
    }

    return summary.toString();
  }

  static DateTime? _suggestBestDueDate(
    String taskDescription,
    int estimatedMinutes,
    int difficulty,
    List<Pendiente> pendingTasks,
    DateTime referenceNow,
  ) {
    if (pendingTasks.isEmpty) {
      return referenceNow.add(Duration(days: 1)); // Mañana si no hay pendientes
    }

    // Calcular carga por día
    final Map<String, int> minutesByDay = {};
    for (final task in pendingTasks.where((p) => !p.completado)) {
      final String dayKey = _getDayKey(task.horaAsignada ?? referenceNow);
      minutesByDay[dayKey] = (minutesByDay[dayKey] ?? 0) + task.tiempoEstimado;
    }

    // Encontrar el día menos cargado en los próximos 7 días
    DateTime bestDay = referenceNow;
    int lowestLoad = estimatedMinutes;

    for (int i = 1; i <= 7; i++) {
      final DateTime dayCandidate = referenceNow.add(Duration(days: i));
      final String dayKey = _getDayKey(dayCandidate);
      final int currentLoad = minutesByDay[dayKey] ?? 0;

      // Preferir días sin pendientes, pero distribuir tareas complejas en días más libres
      if (currentLoad < lowestLoad) {
        lowestLoad = currentLoad;
        bestDay = dayCandidate;

        // Si encontramos un día con pocísima carga, úsalo especialmente para tareas complejas
        if (difficulty > 7 && currentLoad < 120) {
          break;
        }
      }
    }

    return DateTime(bestDay.year, bestDay.month, bestDay.day, 10, 0);
  }

  static String _getDayKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  static String _getDayNameSpanish(DateTime date) {
    const days = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
    return days[date.weekday - 1];
  }

  static String _generateReasoningText(
    DateTime? suggestedDate,
    int estimatedMinutes,
    int difficulty,
    List<Pendiente> pendingTasks,
    DateTime referenceNow,
  ) {
    if (suggestedDate == null) {
      return 'Por aclarar fecha específica';
    }

    final String suggestedDayName = _getDayNameSpanish(suggestedDate);
    final Duration timeDiff = suggestedDate.difference(referenceNow);
    final int daysAhead = timeDiff.inDays;

    // Calcular carga en el día sugerido
    final String suggestedDayKey = _getDayKey(suggestedDate);
    int loadOnThatDay = 0;
    for (final task in pendingTasks.where((p) => !p.completado)) {
      if (_getDayKey(task.horaAsignada ?? referenceNow) == suggestedDayKey) {
        loadOnThatDay += task.tiempoEstimado;
      }
    }

    if (daysAhead == 0) {
      if (loadOnThatDay < 120) {
        return 'Hoy tiene tiempo disponible';
      } else if (loadOnThatDay < 240) {
        return 'Ajustable para hoy con gestión de tiempo';
      } else {
        return 'Urgente, a pesar de la carga de hoy';
      }
    } else if (daysAhead == 1) {
      return 'Mañana tienes ${loadOnThatDay == 0 ? 'la agenda libre' : 'menos carga'}';
    } else {
      if (difficulty > 7) {
        return '$suggestedDayName está libre, ideal para tareas complejas';
      } else {
        return 'Distribuye carga hacia $suggestedDayName ($daysAhead días)';
      }
    }
  }
}
