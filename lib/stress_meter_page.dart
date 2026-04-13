import 'package:flutter/material.dart';
import 'models.dart'; // Para Pendiente

class StressMeterPage extends StatefulWidget {
  final List<Pendiente> pendientes;

  const StressMeterPage({super.key, required this.pendientes});

  @override
  _StressMeterPageState createState() => _StressMeterPageState();
}

class _StressMeterPageState extends State<StressMeterPage> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.98, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double promedioDificultad = widget.pendientes.isEmpty ? 0 : widget.pendientes.map((p) => p.dificultad).reduce((a, b) => a + b) / widget.pendientes.length;
    double stressLevel = promedioDificultad / 10.0;
    if (stressLevel > 1.0) stressLevel = 1.0;

    Color indicatorColor = stressLevel < 0.33 ? Colors.green[400]! : stressLevel < 0.66 ? Colors.orange[400]! : Colors.red[400]!;
    Color bgColor1 = stressLevel < 0.33 ? Colors.white.withOpacity(0.8) : stressLevel < 0.66 ? Colors.orange[50]!.withOpacity(0.8) : Colors.red[50]!.withOpacity(0.8);
    Color bgColor2 = stressLevel < 0.33 ? Colors.purple[100]!.withOpacity(0.5) : stressLevel < 0.66 ? Colors.orange[100]!.withOpacity(0.5) : Colors.red[100]!.withOpacity(0.5);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.purple[50]!, Colors.grey[50]!],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Medidor de Estrés',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w300,
                  color: Colors.purple[700],
                  fontFamily: 'SF Pro Display',
                ),
              ),
              SizedBox(height: 40),
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withAlpha(220),
                        border: Border.all(color: Colors.white.withAlpha(150), width: 1.5),
                        gradient: RadialGradient(
                          colors: [
                            Colors.white.withAlpha(230),
                            bgColor1.withAlpha(200),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: indicatorColor.withAlpha(100),
                            blurRadius: 25,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: CircularProgressIndicator(
                        value: stressLevel,
                        strokeWidth: 12,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(indicatorColor),
                      ),
                    ),
                  );
                },
              ),
              SizedBox(height: 20),
              Text(
                'Nivel de Estrés: ${(stressLevel * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 24,
                  color: Colors.lightBlue[600],
                  fontFamily: 'SF Pro Text',
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Promedio dificultad: ${promedioDificultad.toStringAsFixed(1)}/10',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                  fontFamily: 'SF Pro Text',
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Basado en ${widget.pendientes.length} pendientes',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                  fontFamily: 'SF Pro Text',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}