import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Constantes de color compartidas con la app principal
// ─────────────────────────────────────────────────────────────────────────────
const _kPurpleDark  = Color(0xFF3B1B8F);
const _kPurpleMid   = Color(0xFF6D28D9);
const _kVioletLight = Color(0xFF7C3AED);
const _kPurpleGlow  = Color(0xFFAB6EFF);

// ─────────────────────────────────────────────────────────────────────────────
//  Modelos mínimos recibidos desde school_mental_health_flow.dart
// ─────────────────────────────────────────────────────────────────────────────
class CheckInSummary {
  final DateTime date;
  final double wellbeingScore; // 0–100
  final double who5Percent;
  final int phq2Score;
  final int gad2Score;
  final String riskLevel; // 'low' | 'medium' | 'high'

  const CheckInSummary({
    required this.date,
    required this.wellbeingScore,
    required this.who5Percent,
    required this.phq2Score,
    required this.gad2Score,
    required this.riskLevel,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  LOGIN SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class KaiaLoginScreen extends StatefulWidget {
  final VoidCallback onLoginAsStudent;
  final VoidCallback onLoginAsProfessional;

  const KaiaLoginScreen({
    super.key,
    required this.onLoginAsStudent,
    required this.onLoginAsProfessional,
  });

  @override
  State<KaiaLoginScreen> createState() => _KaiaLoginScreenState();
}

class _KaiaLoginScreenState extends State<KaiaLoginScreen> {
  AppEntryRole _selectedRole = AppEntryRole.student;
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa tu correo electrónico.')),
      );
      return;
    }
    setState(() => _loading = true);
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _loading = false);
    // Routing sencillo por rol seleccionado (sin auth compleja)
    if (_selectedRole == AppEntryRole.professional) {
      widget.onLoginAsProfessional();
    } else {
      widget.onLoginAsStudent();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_kPurpleDark, _kVioletLight, Color(0xFF2563EB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 8),
                  // Card del formulario
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.18),
                          blurRadius: 32,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Inicia sesión',
                          style: TextStyle(
                            fontFamily: 'SF Pro Display',
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1E1B4B),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          '¿Cómo quieres entrar hoy?',
                          style: TextStyle(
                            fontFamily: 'SF Pro Text',
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF4338CA),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: ChoiceChip(
                                label: const Text('Alumno'),
                                selected:
                                    _selectedRole == AppEntryRole.student,
                                onSelected: (_) {
                                  setState(
                                    () => _selectedRole = AppEntryRole.student,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ChoiceChip(
                                label: const Text('Profesional'),
                                selected:
                                    _selectedRole == AppEntryRole.professional,
                                onSelected: (_) {
                                  setState(
                                    () =>
                                        _selectedRole =
                                            AppEntryRole.professional,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: _inputDeco(
                            label: 'Correo electrónico',
                            icon: Icons.email_outlined,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _passwordCtrl,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _login(),
                          decoration: _inputDeco(
                            label: 'Contraseña',
                            icon: Icons.lock_outline,
                          ).copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: Colors.purple[400],
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kVioletLight,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                            child: _loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Text(
                                    'Entrar',
                                    style: TextStyle(
                                      fontFamily: 'SF Pro Display',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Registro disponible próximamente.',
                          ),
                        ),
                      );
                    },
                    child: const Text(
                      'Primera vez aquí, regístrate',
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'SF Pro Text',
                        fontSize: 14,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white,
                      ),
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

  InputDecoration _inputDeco({required String label, required IconData icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.purple[400]),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.purple[200]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _kVioletLight, width: 2),
      ),
      filled: true,
      fillColor: Colors.purple.shade50,
    );
  }
}

enum AppEntryRole { student, professional }

// ─────────────────────────────────────────────────────────────────────────────
//  MI PROGRESO — body sin Scaffold (para uso dentro de BottomNav)
// ─────────────────────────────────────────────────────────────────────────────
class MiProgresoBody extends StatelessWidget {
  final List<CheckInSummary> checkIns;

  const MiProgresoBody({super.key, required this.checkIns});

  @override
  Widget build(BuildContext context) {
    final sorted = [...checkIns]
      ..sort((a, b) => a.date.compareTo(b.date));
    final last7 = sorted.length > 7 ? sorted.sublist(sorted.length - 7) : sorted;
    final last5 = sorted.length > 5 ? sorted.sublist(sorted.length - 5) : sorted;
    final last5Reversed = last5.reversed.toList();

    final average = last7.isEmpty
        ? 0.0
        : last7.map((c) => c.wellbeingScore).reduce((a, b) => a + b) /
            last7.length;

    return Container(
      color: const Color(0xFFF5F3FF),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _AverageCard(average: average),
          const SizedBox(height: 16),
          _WellbeingChart(last7: last7),
          const SizedBox(height: 16),
          _Last5CheckIns(checkIns: last5Reversed),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _AverageCard extends StatelessWidget {
  final double average;
  const _AverageCard({required this.average});

  @override
  Widget build(BuildContext context) {
    final (color, message) = _motivational(average);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kPurpleDark, _kVioletLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _kPurpleMid.withOpacity(0.30),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Promedio semanal',
                  style: TextStyle(
                    color: Colors.white70,
                    fontFamily: 'SF Pro Text',
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${average.toStringAsFixed(0)} / 100',
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'SF Pro Display',
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: color.withOpacity(0.5)),
                  ),
                  child: Text(
                    message,
                    style: TextStyle(
                      color: color,
                      fontFamily: 'SF Pro Text',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            _icon(average),
            color: Colors.white.withOpacity(0.85),
            size: 52,
          ),
        ],
      ),
    );
  }

  (Color, String) _motivational(double avg) {
    if (avg >= 70) return (Colors.greenAccent, '¡Vas muy bien, sigue así! 🌟');
    if (avg >= 40) return (Colors.amber, 'Vas avanzando, paso a paso 💛');
    return (const Color(0xFFFF7C7C), 'Recuerda que no estás solo 💜');
  }

  IconData _icon(double avg) {
    if (avg >= 70) return Icons.sentiment_very_satisfied_rounded;
    if (avg >= 40) return Icons.sentiment_neutral_rounded;
    return Icons.sentiment_dissatisfied_rounded;
  }
}

class _WellbeingChart extends StatelessWidget {
  final List<CheckInSummary> last7;
  const _WellbeingChart({required this.last7});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 20, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bienestar últimos 7 días',
            style: TextStyle(
              fontFamily: 'SF Pro Display',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _kPurpleDark,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: last7.isEmpty
                ? const Center(
                    child: Text(
                      'Completa al menos un check-in para ver tu progreso.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      minY: 0,
                      maxY: 100,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (v) => FlLine(
                          color: Colors.purple.withOpacity(0.07),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            interval: 25,
                            getTitlesWidget: (v, _) => Text(
                              '${v.toInt()}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 24,
                            getTitlesWidget: (value, _) {
                              final idx = value.toInt();
                              if (idx < 0 || idx >= last7.length) {
                                return const SizedBox.shrink();
                              }
                              final day = last7[idx].date;
                              return Text(
                                _dayLabel(day.weekday),
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 10,
                                ),
                              );
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: [
                            for (int i = 0; i < last7.length; i++)
                              FlSpot(
                                i.toDouble(),
                                last7[i].wellbeingScore.clamp(0, 100),
                              ),
                          ],
                          isCurved: true,
                          curveSmoothness: 0.35,
                          color: _kVioletLight,
                          barWidth: 3,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, _, __, ___) =>
                                FlDotCirclePainter(
                              radius: 5,
                              color: Colors.white,
                              strokeWidth: 2.5,
                              strokeColor: _kVioletLight,
                            ),
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              colors: [
                                _kPurpleGlow.withOpacity(0.25),
                                _kPurpleGlow.withOpacity(0.0),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _dayLabel(int weekday) {
    const labels = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    return labels[(weekday - 1).clamp(0, 6)];
  }
}

class _Last5CheckIns extends StatelessWidget {
  final List<CheckInSummary> checkIns;
  const _Last5CheckIns({required this.checkIns});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'Últimos check-ins',
            style: TextStyle(
              fontFamily: 'SF Pro Display',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _kPurpleDark,
            ),
          ),
        ),
        if (checkIns.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Todavía no tienes check-ins registrados.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        ...checkIns.map((c) => _CheckInTile(checkIn: c)),
      ],
    );
  }
}

class _CheckInTile extends StatelessWidget {
  final CheckInSummary checkIn;
  const _CheckInTile({required this.checkIn});

  @override
  Widget build(BuildContext context) {
    final (badgeColor, riskLabel) = _riskInfo(checkIn.riskLevel);
    final day  = checkIn.date.day.toString().padLeft(2, '0');
    final mon  = checkIn.date.month.toString().padLeft(2, '0');
    final year = checkIn.date.year;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFF3EEFF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                '${checkIn.wellbeingScore.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: _kVioletLight,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$day/$mon/$year',
                  style: const TextStyle(
                    fontFamily: 'SF Pro Text',
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'WHO-5 ${checkIn.who5Percent.toStringAsFixed(0)}%  ·  PHQ-2 ${checkIn.phq2Score}  ·  GAD-2 ${checkIn.gad2Score}',
                  style: const TextStyle(
                    fontFamily: 'SF Pro Text',
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: badgeColor.withOpacity(0.4)),
            ),
            child: Text(
              riskLabel,
              style: TextStyle(
                color: badgeColor,
                fontFamily: 'SF Pro Text',
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  (Color, String) _riskInfo(String riskLevel) {
    switch (riskLevel.toLowerCase()) {
      case 'high':
        return (Colors.red, 'Alto');
      case 'medium':
        return (Colors.orange, 'Medio');
      default:
        return (Colors.green, 'Bajo');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  APOYO — body sin Scaffold (para uso dentro de BottomNav)
// ─────────────────────────────────────────────────────────────────────────────
class ApoyoBody extends StatelessWidget {
  const ApoyoBody({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F3FF),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _ApoyoSection(
            icon: Icons.air_rounded,
            title: 'Técnicas de respiración',
            color: Color(0xFF6D28D9),
            items: [
              _ApoyoItem(
                title: '4-7-8 Calmante',
                description:
                    'Inhala por la nariz 4 segundos → Sostén 7 segundos → '
                    'Exhala lentamente por la boca 8 segundos. '
                    'Repite 4 veces. Activa el sistema nervioso parasimpático.',
              ),
              _ApoyoItem(
                title: 'Respiración cuadrada',
                description:
                    'Inhala 4 s → Sostén 4 s → Exhala 4 s → Pausa 4 s. '
                    'Ideal antes de un examen o situación estresante.',
              ),
              _ApoyoItem(
                title: 'Respiración diafragmática',
                description:
                    'Coloca una mano en el pecho y otra en el abdomen. '
                    'Inhala profundo y siente que solo el abdomen sube. '
                    'Exhala despacio. Hazlo 10 veces.',
              ),
            ],
          ),
          SizedBox(height: 16),
          _ApoyoSection(
            icon: Icons.wb_sunny_rounded,
            title: 'Tips de bienestar',
            color: Color(0xFFF59E0B),
            items: [
              _ApoyoItem(
                title: 'Muévete 20 minutos',
                description:
                    'Caminar, bailar o estirarte activa endorfinas y reduce '
                    'el cortisol. No necesitas ir al gimnasio.',
              ),
              _ApoyoItem(
                title: 'Escribe 3 cosas positivas',
                description:
                    'Cada noche anota tres momentos buenos del día, por '
                    'pequeños que sean. Entrena la gratitud.',
              ),
              _ApoyoItem(
                title: 'Desconéctate 1 hora antes de dormir',
                description:
                    'La luz azul de pantallas retrasa el sueño. Cambia el '
                    'celular por un libro o música tranquila.',
              ),
              _ApoyoItem(
                title: 'Conecta con alguien',
                description:
                    'Una conversación genuina de 10 minutos con un amigo o '
                    'familiar reduce el estrés más que 30 min en redes sociales.',
              ),
            ],
          ),
          SizedBox(height: 16),
          _EmergencySection(),
        ],
      ),
    );
  }
}

class _ApoyoSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final List<_ApoyoItem> items;

  const _ApoyoSection({
    required this.icon,
    required this.title,
    required this.color,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...items.map((item) => _card(item)),
      ],
    );
  }

  Widget _card(_ApoyoItem item) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.07),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title,
            style: TextStyle(
              fontFamily: 'SF Pro Display',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.description,
            style: const TextStyle(
              fontFamily: 'SF Pro Text',
              fontSize: 13,
              height: 1.5,
              color: Color(0xFF374151),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApoyoItem {
  final String title;
  final String description;
  const _ApoyoItem({required this.title, required this.description});
}

class _EmergencySection extends StatelessWidget {
  const _EmergencySection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.favorite_rounded,
                color: Colors.red.shade600,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Contactos de emergencia',
              style: TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.red.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _contactCard(
          context,
          icon: Icons.person_outlined,
          color: _kVioletLight,
          title: 'Tu psicóloga',
          subtitle: 'Agenda cita desde la pantalla principal',
          detail: 'Disponible en días hábiles',
        ),
        const SizedBox(height: 8),
        _contactCard(
          context,
          icon: Icons.phone_rounded,
          color: Colors.red.shade600,
          title: 'Línea de la Vida',
          subtitle: '800-911-2000',
          detail: '24 h · 7 días · Gratuito · Confidencial',
          isEmergency: true,
        ),
      ],
    );
  }

  Widget _contactCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String detail,
    bool isEmergency = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isEmergency ? Colors.red.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEmergency
              ? Colors.red.shade200
              : Colors.purple.shade100,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'SF Pro Display',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'SF Pro Text',
                    fontSize: 14,
                    fontWeight: isEmergency
                        ? FontWeight.w700
                        : FontWeight.w400,
                    color: isEmergency
                        ? Colors.red.shade800
                        : const Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(
                    fontFamily: 'SF Pro Text',
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
