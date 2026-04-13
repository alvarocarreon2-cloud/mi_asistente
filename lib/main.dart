import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'home_page.dart';
import 'focus_timer_page.dart';
import 'stress_meter_page.dart';
import 'focus_screen.dart';
import 'dart:async';
import 'dart:ui';

import 'models.dart';
import 'school_mental_health_flow.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mi App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: Colors.purple[300],
        scaffoldBackgroundColor: Colors.grey[50],
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.purple[500]),
          titleTextStyle: TextStyle(color: Colors.purple[800], fontSize: 20, fontWeight: FontWeight.w500),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purple[100],
            foregroundColor: Colors.purple[800],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Colors.purple[600],
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.purple[200]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.purple[400]!),
          ),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
      home: const SchoolMentalHealthFlow(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final String nombreUsuario;

  const HomeScreen({super.key, required this.nombreUsuario});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<Pendiente> _pendientes = [];
  Timer? _timer;
  Pendiente? _currentFocus;
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final GlobalKey _navBarTrackKey = GlobalKey();
  bool _isDraggingFromActiveItem = false;
  int _dragHoverPage = 0;

  @override
  void initState() {
    super.initState();
    _dragHoverPage = _currentPage;
    _startTimer();
    _pageController.addListener(() {
      setState(() {
        _currentPage = _pageController.page!.round();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(Duration(seconds: 30), (timer) {
      DateTime now = DateTime.now();
      for (var p in _pendientes) {
        if (p.horaAsignada != null && !p.completado && !p.focoActivado) {
          if (!now.isBefore(p.horaAsignada!)) {
            setState(() {
              p.focoActivado = true;
              _currentFocus = p;
            });
            break;
          }
        }
      }
    });
  }

  void _addPendiente(
    String descripcion,
    String titulo,
    List<String> escaleta,
    DateTime horaAsignada,
    int tiempoEstimado,
    int dificultad,
    int prioridad,
    String schedulingReason,
  ) {
    setState(() {
      _pendientes.add(Pendiente(
        descripcion: descripcion,
        titulo: titulo,
        escaleta: escaleta,
        tiempoEstimado: tiempoEstimado,
        dificultad: dificultad,
        prioridad: prioridad,
        horaAsignada: horaAsignada,
        schedulingReason: schedulingReason,
      ));
      _sortPendientes();
    });
  }

  void _removePendiente(int index) {
    setState(() {
      _pendientes.removeAt(index);
    });
  }

  void _sortPendientes() {
    _pendientes.sort((a, b) {
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

  void _completePendiente(Pendiente p) {
    setState(() {
      p.completado = true;
      _currentFocus = null;
      _sortPendientes();
    });
  }

  void _startFocusNow(Pendiente p) {
    setState(() {
      p.focoActivado = true;
      _currentFocus = p;
    });
  }

  void _goToPage(int pageIndex, {bool instant = false}) {
    if (!_pageController.hasClients || pageIndex == _currentPage) return;
    if (instant) {
      _pageController.jumpToPage(pageIndex);
      return;
    }
    _pageController.animateToPage(
      pageIndex,
      duration: Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _startNavItemDrag(bool isActive) {
    if (!isActive) return;
    _isDraggingFromActiveItem = true;
    _dragHoverPage = _currentPage;
    HapticFeedback.heavyImpact();
  }

  void _updateNavItemDrag(Offset globalPosition, int itemCount) {
    if (!_isDraggingFromActiveItem) return;
    final context = _navBarTrackKey.currentContext;
    if (context == null || itemCount == 0) return;

    final box = context.findRenderObject() as RenderBox;
    final localPosition = box.globalToLocal(globalPosition);
    final double width = box.size.width;
    if (width <= 0) return;

    final double clampedDx = localPosition.dx.clamp(0.0, width - 1);
    final int targetIndex =
        (clampedDx / (width / itemCount)).floor().clamp(0, itemCount - 1);

    if (targetIndex != _dragHoverPage) {
      _dragHoverPage = targetIndex;
      HapticFeedback.selectionClick();
      _goToPage(targetIndex, instant: true);
    }
  }

  void _endNavItemDrag() {
    if (!_isDraggingFromActiveItem) return;
    _isDraggingFromActiveItem = false;
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentFocus != null) {
      return FocusScreen(
        pendiente: _currentFocus!,
        onComplete: _completePendiente,
      );
    }
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentPage = index;
                  _dragHoverPage = index;
                });
              },
              children: [
                StressMeterPage(pendientes: _pendientes.where((p) => !p.completado).toList()),
                HomePage(
                  pendientes: _pendientes,
                  addPendiente: _addPendiente,
                  removePendiente: _removePendiente,
                  startFocusNow: _startFocusNow,
                ),
                FocusTimerPage(),
              ],
            ),
          ),
          _buildBottomNavigationBar(),
        ],
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    final List<Map<String, dynamic>> navItems = [
      {
        'icon': Icons.show_chart_rounded,
        'label': 'Estrés',
        'index': 0,
      },
      {
        'icon': Icons.home_rounded,
        'label': 'Inicio',
        'index': 1,
      },
      {
        'icon': Icons.timer_rounded,
        'label': 'Temporizador',
        'index': 2,
      },
    ];

    return Container(
      height: 100,
      padding: EdgeInsets.only(bottom: 16, left: 12, right: 12, top: 12),
      color: Colors.grey[50],
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 35, sigmaY: 35),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.45),
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withOpacity(0.8),
                  width: 1.5,
                ),
              ),
            ),
            child: Container(
              key: _navBarTrackKey,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(
                  navItems.length,
                  (index) {
                    final item = navItems[index];
                    final bool isActive = _currentPage == item['index'];
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        _goToPage(item['index']);
                      },
                      onLongPressStart: (_) {
                        _startNavItemDrag(isActive);
                      },
                      onLongPressMoveUpdate: (details) {
                        _updateNavItemDrag(details.globalPosition, navItems.length);
                      },
                      onLongPressEnd: (_) {
                        _endNavItemDrag();
                      },
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: AnimatedContainer(
                          duration: Duration(milliseconds: 300),
                          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: isActive
                                ? Colors.white.withOpacity(0.5)
                                : Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isActive
                                  ? Colors.white.withOpacity(0.9)
                                  : Colors.white.withOpacity(0.2),
                              width: isActive ? 1.5 : 1.3,
                            ),
                            boxShadow: isActive
                                ? [
                                    BoxShadow(
                                      color: Colors.white.withOpacity(0.4),
                                      blurRadius: 20,
                                      offset: Offset(0, 2),
                                      spreadRadius: 2,
                                    ),
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.12),
                                      blurRadius: 16,
                                      offset: Offset(0, 6),
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : [],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedScale(
                                scale: isActive ? 1.15 : 1.0,
                                duration: Duration(milliseconds: 300),
                                child: Icon(
                                  item['icon'],
                                  size: 24,
                                  color: isActive
                                      ? Colors.purple[600]
                                      : Colors.grey[700],
                                ),
                              ),
                              SizedBox(height: 3),
                              AnimatedOpacity(
                                opacity: isActive ? 1.0 : 0.65,
                                duration: Duration(milliseconds: 300),
                                child: Text(
                                  item['label'],
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: isActive
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isActive
                                        ? Colors.purple[600]
                                        : Colors.grey[700],
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

