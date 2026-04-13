import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'models.dart';
import 'task_ai_estimator.dart';
import 'weekly_planner_service.dart';
import 'calendar_sync_service.dart';

class HomePage extends StatefulWidget {
  final List<Pendiente> pendientes;
  final Function(String, String, List<String>, DateTime, int, int, int, String)
  addPendiente;
  final Function(int) removePendiente;
  final Function(Pendiente) startFocusNow;

  const HomePage({
    super.key,
    required this.pendientes,
    required this.addPendiente,
    required this.removePendiente,
    required this.startFocusNow,
  });

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final CalendarSyncService _calendarSyncService = CalendarSyncService();
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _focusNowController;
  late Animation<double> _focusNowScale;
  bool _isEditMode = false;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _speechInitialized = false;
  bool _isProcessingPendiente = false;
  late AnimationController _micController;
  late Animation<double> _micScale;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initializeSpeech();
    _fadeController = AnimationController(duration: Duration(milliseconds: 800), vsync: this);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
    _fadeController.forward();
    _focusNowController = AnimationController(duration: Duration(milliseconds: 110), vsync: this);
    _focusNowScale = Tween<double>(begin: 1.0, end: 0.97).animate(_focusNowController);
    _micController = AnimationController(duration: Duration(milliseconds: 200), vsync: this);
    _micScale = Tween<double>(begin: 1.0, end: 0.93).animate(
      CurvedAnimation(parent: _micController, curve: Curves.easeInOut),
    );
    _pulseController = AnimationController(
      duration: Duration(milliseconds: 1200),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _shakeController = AnimationController(duration: Duration(milliseconds: 500), vsync: this);
    _shakeAnimation = Tween<double>(begin: -2.0, end: 2.0).animate(_shakeController);
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _focusNowController.dispose();
    _micController.dispose();
    _pulseController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  void _safePop<T>(BuildContext context, [T? result]) {
    final navigator = Navigator.of(context);
    if (!navigator.canPop()) return;
    navigator.pop(result);
  }

  Future<void> _initializeSpeech() async {
    _speechInitialized = await _speech.initialize(
      onStatus: (status) async {
        // Solo actualizar estado de escucha, no procesar automáticamente
        if (status == 'done' || status == 'notListening') {
          if (_isListening) {
            setState(() => _isListening = false);
            _micController.reverse();
            _pulseController.stop();
            _pulseController.value = 0.0;
          }
        }
      },
      onError: (error) {
        if (_isListening) {
          setState(() => _isListening = false);
          _micController.reverse();
          _pulseController.stop();
          _pulseController.value = 0.0;
        }
      },
    );
  }

  void _startListening() async {
    if (_isProcessingPendiente || _isListening) return;
    
    if (!_speechInitialized) {
      await _initializeSpeech();
    }
    
    if (_speechInitialized) {
      HapticFeedback.mediumImpact();
      setState(() => _isListening = true);
      _micController.forward();
      _pulseController.repeat(reverse: true);
      
      await _speech.listen(
        onResult: (result) {
          setState(() {
            _controller.text = result.recognizedWords;
          });
        },
        localeId: 'es_ES',
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.confirmation,
          partialResults: true,
          cancelOnError: true,
        ),
        listenFor: Duration(seconds: 60),
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo inicializar el reconocimiento de voz')),
        );
      }
    }
  }

  void _stopListening() async {
    if (!_isListening) return;
    
    HapticFeedback.lightImpact();
    await _speech.stop();
    setState(() => _isListening = false);
    _micController.reverse();
    _pulseController.stop();
    _pulseController.value = 0.0;
    
    // Procesar inmediatamente al soltar
    if (_controller.text.trim().isNotEmpty && !_isProcessingPendiente) {
      await Future.delayed(Duration(milliseconds: 100));
      if (mounted && _controller.text.trim().isNotEmpty) {
        _addNewPendiente();
      }
    }
  }

  Future<void> _openManualInput() async {
    final TextEditingController manualController = TextEditingController(
      text: _controller.text,
    );

    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) {
        return CupertinoPopupSurface(
          child: SafeArea(
            top: false,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Escribir tarea',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.purple[800],
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () => _safePop(sheetContext),
                        child: Text('Cerrar'),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  CupertinoTextField(
                    controller: manualController,
                    placeholder: 'Describe tu tarea',
                    maxLines: 3,
                    autofocus: true,
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton(
                      color: Colors.lightBlue[100],
                      borderRadius: BorderRadius.circular(12),
                      onPressed: () {
                        final value = manualController.text.trim();
                        if (value.isEmpty) return;
                        _controller.text = value;
                        _safePop(sheetContext);
                        _addNewPendiente();
                      },
                      child: Text(
                        'Crear pendiente',
                        style: TextStyle(color: Colors.purple[800]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _addNewPendiente() async {
    if (_controller.text.isNotEmpty && !_isProcessingPendiente) {
      setState(() => _isProcessingPendiente = true);
      
      // Cerrar teclado antes de mostrar el picker
      FocusScope.of(context).unfocus();
      await Future.delayed(Duration(milliseconds: 100));

      final pendingTasks = widget.pendientes
          .where((p) => !p.completado)
          .take(8)
          .toList();

      TaskAnalysis analysis = await TaskAiEstimator.analyzeSmart(
        _controller.text,
        pendingTasks: pendingTasks,
      );

      if (analysis.suggestedDueDate == null && analysis.needsDeadlineClarification) {
        final String? detail = await _askForDeadlineDetail(analysis.clarificationQuestion);
        if (detail == null || detail.trim().isEmpty) {
          return;
        }
        analysis = await TaskAiEstimator.analyzeSmart(
          _controller.text,
          extraDetails: detail,
          pendingTasks: pendingTasks,
        );
      }

      DateTime? selectedTime = analysis.suggestedDueDate;
      selectedTime ??= DateTime.now().add(const Duration(hours: 4));

      widget.addPendiente(
        _controller.text,
        analysis.generatedTitle,
        analysis.planSteps,
        selectedTime,
        analysis.estimatedMinutes,
        analysis.difficulty,
        analysis.priority,
        analysis.suggestionReasoning,
      );
      _controller.clear();
      setState(() => _isProcessingPendiente = false);
    }
  }

  Future<String?> _askForDeadlineDetail(String question) async {
    final TextEditingController detailController = TextEditingController();
    return showCupertinoDialog<String>(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: Text('Detalle rápido'),
          content: Column(
            children: [
              SizedBox(height: 8),
              Text(question),
              SizedBox(height: 10),
              CupertinoTextField(
                controller: detailController,
                placeholder: 'Ej. mañana 19:00',
              ),
            ],
          ),
          actions: [
            CupertinoDialogAction(
              child: Text('Cancelar'),
              onPressed: () => _safePop(context),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              child: Text('Listo'),
              onPressed: () => _safePop(context, detailController.text),
            ),
          ],
        );
      },
    );
  }

  String _formatShortDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Pendiente? _highestPriorityPending() {
    final pending = widget.pendientes.where((p) => !p.completado).toList();
    if (pending.isEmpty) return null;
    pending.sort((a, b) {
      final priority = b.prioridad.compareTo(a.prioridad);
      if (priority != 0) return priority;
      if (a.horaAsignada == null && b.horaAsignada == null) return 0;
      if (a.horaAsignada == null) return 1;
      if (b.horaAsignada == null) return -1;
      return a.horaAsignada!.compareTo(b.horaAsignada!);
    });
    return pending.first;
  }

  List<String> _buildMiniEscaleta(Pendiente p) {
    final List<Pendiente> pending = widget.pendientes
        .where((item) => !item.completado)
        .toList();

    pending.sort((a, b) {
      final int priority = b.prioridad.compareTo(a.prioridad);
      if (priority != 0) return priority;
      return a.tiempoEstimado.compareTo(b.tiempoEstimado);
    });

    final int index = pending.indexOf(p);
    final Pendiente? before = index > 0 ? pending[index - 1] : null;
    final Pendiente? after = index >= 0 && index < pending.length - 1
        ? pending[index + 1]
        : null;

    final List<String> steps = [];
    if (before != null) {
      steps.add('Cierra rápido "$before.titulo" (5-10 min) para liberar foco.');
    }

    final List<String> baseSteps = p.escaleta.isNotEmpty
        ? p.escaleta.take(3).toList()
        : [
            'Define objetivo y entregable final.',
            'Haz el bloque más crítico de la tarea.',
            'Completa y revisa calidad final.',
          ];

    steps.addAll(baseSteps);

    if (after != null) {
      steps.add('Deja avance o nota de traspaso para "$after.titulo" (5 min).');
    } else {
      steps.add('Cierra con siguientes pasos y orden de prioridad.');
    }

    return steps.take(6).toList();
  }

  Future<void> _showPreFocusMiniEscaleta(Pendiente p) async {
    final steps = _buildMiniEscaleta(p);
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mini escaleta para empezar',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.purple[800],
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  p.titulo,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                    fontFamily: 'SF Pro Text',
                  ),
                ),
                SizedBox(height: 12),
                ...List.generate(steps.length, (index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${index + 1}.',
                          style: TextStyle(
                            color: Colors.purple[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            steps[index],
                            style: TextStyle(
                              color: Colors.purple[800],
                              fontFamily: 'SF Pro Text',
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        color: Colors.grey[200],
                        child: Text('Cancelar', style: TextStyle(color: Colors.grey[700])),
                        onPressed: () => _safePop(ctx),
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: CupertinoButton(
                        color: Colors.purple[200],
                        child: Text('Entrar a Focus', style: TextStyle(color: Colors.purple[800])),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          _safePop(ctx);
                          widget.startFocusNow(p);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _startFocusNowFromTopPriority() async {
    HapticFeedback.lightImpact();
    await _focusNowController.forward();
    await _focusNowController.reverse();

    final top = _highestPriorityPending();
    if (top == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No hay pendientes activos para iniciar Focus.')),
      );
      return;
    }
    _showPreFocusMiniEscaleta(top);
  }

  Future<void> _showWeeklyPlan() async {
    final plan = WeeklyPlannerService.buildWeeklyPlan(widget.pendientes);
    if (plan.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No hay pendientes por planear esta semana.')),
      );
      return;
    }

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Plan semanal sugerido',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.purple[800],
                  ),
                ),
                SizedBox(height: 10),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: plan.length,
                    itemBuilder: (context, index) {
                      final session = plan[index];
                      return ListTile(
                        dense: true,
                        title: Text(
                          session.pendiente.titulo,
                          style: TextStyle(color: Colors.purple[800]),
                        ),
                        subtitle: Text(
                          '${_formatShortDate(session.start)} - ${session.end.hour.toString().padLeft(2, '0')}:${session.end.minute.toString().padLeft(2, '0')} · P${session.pendiente.prioridad}',
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(height: 12),
                CupertinoButton.filled(
                  child: Text('Sincronizar con calendario iPhone'),
                  onPressed: () async {
                    _safePop(ctx);
                    final result = await _calendarSyncService.syncPlanToCalendar(plan);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(result ?? 'Sincronización finalizada.')),
                    );
                  },
                ),
                SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  void _sortPendientesLocal() {
    widget.pendientes.sort((a, b) {
      if (a.completado != b.completado) {
        return a.completado ? 1 : -1;
      }

      final int priorityCompare = b.prioridad.compareTo(a.prioridad);
      if (priorityCompare != 0) return priorityCompare;

      if (a.horaAsignada == null && b.horaAsignada == null) return 0;
      if (a.horaAsignada == null) return 1;
      if (b.horaAsignada == null) return -1;

      return a.horaAsignada!.compareTo(b.horaAsignada!);
    });
  }

  void _setCompletionState(Pendiente p, bool completed) {
    HapticFeedback.lightImpact();
    setState(() {
      p.completado = completed;
      if (!completed) {
        p.focoActivado = false;
      }
      _sortPendientesLocal();
    });
  }

  @override
  Widget build(BuildContext context) {
    final PlannedSession? nextSuggestion = WeeklyPlannerService.suggestNextSession(widget.pendientes);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.purple[50]!, Colors.grey[50]!],
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    SizedBox(height: 50),
                    Text(
                      'Pendientes',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w300,
                        color: Colors.purple[800],
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                    SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: _openManualInput,
                          child: Text(
                            'Escribir tarea',
                            style: TextStyle(
                              color: Colors.purple[600],
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    if (nextSuggestion != null)
                      Container(
                        width: double.infinity,
                        margin: EdgeInsets.only(bottom: 14),
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(220),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withAlpha(100), width: 1),
                        ),
                        child: Row(
                          children: [
                            Icon(CupertinoIcons.sparkles, color: Colors.purple[700], size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Sugerencia IA: ${nextSuggestion.pendiente.titulo} · ${_formatShortDate(nextSuggestion.start)}',
                                style: TextStyle(
                                  color: Colors.purple[800],
                                  fontSize: 13,
                                  fontFamily: 'SF Pro Text',
                                ),
                              ),
                            ),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: _showWeeklyPlan,
                              child: Text('Ver semana', style: TextStyle(color: Colors.lightBlue[700])),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        padding: EdgeInsets.only(bottom: 180),
                        itemCount: widget.pendientes.length,
                    itemBuilder: (context, index) {
                      Pendiente p = widget.pendientes[index];
                      return Dismissible(
                        key: Key(p.titulo + index.toString()),
                        direction: DismissDirection.down,
                        background: Container(
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Icon(CupertinoIcons.delete, color: Colors.red[400]),
                        ),
                        secondaryBackground: Container(
                          decoration: BoxDecoration(
                            color: Colors.purple[50],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.centerRight,
                          child: Icon(
                            CupertinoIcons.check_mark_circled_solid,
                            color: Colors.purple[400],
                          ),
                        ),
                        dismissThresholds: const {
                          DismissDirection.down: 0.22,
                        },
                        confirmDismiss: (direction) async {
                          if (direction == DismissDirection.down) {
                            return true;
                          }

                          return false;
                        },
                        movementDuration: Duration(milliseconds: 180),
                        resizeDuration: Duration(milliseconds: 140),
                        onDismissed: (direction) {
                          if (direction != DismissDirection.down) return;
                          widget.removePendiente(index);
                          if (_isEditMode) {
                            setState(() => _isEditMode = false);
                            _shakeController.stop();
                            _shakeController.value = 0.0;
                          }
                        },
                        child: AnimatedScale(
                          duration: Duration(milliseconds: 180),
                          scale: p.completado ? 0.98 : 1.0,
                          child: AnimatedOpacity(
                            duration: Duration(milliseconds: 180),
                            opacity: p.completado ? 0.72 : 1.0,
                            child: AnimatedBuilder(
                              animation: _isEditMode ? _shakeAnimation : AlwaysStoppedAnimation(0.0),
                              builder: (context, child) {
                                return Transform.translate(
                                  offset: Offset(_isEditMode ? _shakeAnimation.value : 0.0, 0),
                                  child: child,
                                );
                              },
                              child: GestureDetector(
                                onHorizontalDragEnd: (details) {
                                  if (!_isEditMode) return;
                                  final v = details.primaryVelocity ?? 0;
                                  if (v < -180) {
                                    _setCompletionState(p, true);
                                  } else if (v > 180) {
                                    _setCompletionState(p, false);
                                  }
                                },
                                child: Container(
                                  margin: EdgeInsets.symmetric(vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withAlpha(220),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white.withAlpha(100), width: 1),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.grey[200]!.withAlpha(100),
                                        blurRadius: 8,
                                        offset: Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: ListTile(
                                  leading: AnimatedSwitcher(
                                    duration: Duration(milliseconds: 180),
                                    child: p.completado
                                        ? Icon(
                                            CupertinoIcons.checkmark_circle_fill,
                                            key: ValueKey('done-${p.titulo}-$index'),
                                            color: Colors.green[400],
                                          )
                                        : Icon(
                                            CupertinoIcons.circle,
                                            key: ValueKey('todo-${p.titulo}-$index'),
                                            color: Colors.purple[200],
                                          ),
                                  ),
                                  title: Text(
                                    p.titulo,
                                    style: TextStyle(
                                      color: Colors.purple[800],
                                      fontFamily: 'SF Pro Text',
                                      decoration: p.completado
                                          ? TextDecoration.lineThrough
                                          : TextDecoration.none,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${p.tiempoEstimado} min · Dificultad ${p.dificultad}/10 · Prioridad ${p.prioridad}/10',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12,
                                          fontFamily: 'SF Pro Text',
                                        ),
                                      ),
                                      if (p.schedulingReason.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4.0),
                                          child: Text(
                                            '💡 ${p.schedulingReason}',
                                            style: TextStyle(
                                              color: Colors.blue[600],
                                              fontSize: 11,
                                              fontFamily: 'SF Pro Text',
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  onLongPress: () {
                                    setState(() => _isEditMode = !_isEditMode);
                                    if (_isEditMode) {
                                      _shakeController.repeat(reverse: true);
                                    } else {
                                      _shakeController.stop();
                                      _shakeController.value = 0.0;
                                    }
                                  },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // Botón push-to-talk centrado abajo
          Positioned(
            left: 0,
            right: 0,
            bottom: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: ScaleTransition(
                    scale: _focusNowScale,
                    child: CupertinoButton(
                      padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      color: Colors.white.withAlpha(200),
                      borderRadius: BorderRadius.circular(18),
                      onPressed: _startFocusNowFromTopPriority,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.play_fill,
                            size: 14,
                            color: Colors.purple[700],
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Empezar focus',
                            style: TextStyle(
                              color: Colors.purple[800],
                              fontSize: 13,
                              fontFamily: 'SF Pro Text',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 12),
                Center(
                  child: IgnorePointer(
                    ignoring: _isProcessingPendiente,
                    child: GestureDetector(
                      onLongPressStart: (_) => _startListening(),
                      onLongPressEnd: (_) => _stopListening(),
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_micScale, _pulseAnimation]),
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _micScale.value,
                            child: AnimatedContainer(
                              duration: Duration(milliseconds: 200),
                              curve: Curves.easeInOut,
                              padding: EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: _isListening 
                                    ? Colors.red[400] 
                                    : _isProcessingPendiente
                                        ? Colors.orange[300]
                                        : Colors.purple[400],
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: _isListening
                                        ? Colors.red.withAlpha((255 * 0.4 * _pulseAnimation.value).round())
                                        : Colors.purple.withAlpha(80),
                                    blurRadius: _isListening ? 20 * _pulseAnimation.value : 15,
                                    spreadRadius: _isListening ? 2 * _pulseAnimation.value : 1,
                                  ),
                                ],
                              ),
                              child: _isProcessingPendiente
                                  ? SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : AnimatedScale(
                                      scale: _isListening ? _pulseAnimation.value : 1.0,
                                      duration: Duration(milliseconds: 200),
                                      child: Icon(
                                        _isListening ? CupertinoIcons.waveform : CupertinoIcons.mic_fill,
                                        color: Colors.white,
                                        size: 32,
                                      ),
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  _isProcessingPendiente
                      ? 'Creando pendiente...'
                      : _isListening 
                          ? 'Suelta para finalizar' 
                          : 'Mantén presionado',
                  style: TextStyle(
                    color: Colors.purple[700],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
);
}
}