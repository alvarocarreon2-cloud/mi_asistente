import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:async';

class FocusTimerPage extends StatefulWidget {
  const FocusTimerPage({super.key});

  @override
  _FocusTimerPageState createState() => _FocusTimerPageState();
}

class _FocusTimerPageState extends State<FocusTimerPage> with TickerProviderStateMixin {
  Timer? _timer;
  int _remainingSeconds = 25 * 60; // 25 minutes
  bool _isRunning = false;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(duration: Duration(milliseconds: 800), vsync: this);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
    _fadeController.forward();
  }

  void _toggleTimer() {
    if (_timer != null) {
      _timer!.cancel();
      _timer = null;
      setState(() {
        _isRunning = false;
      });
    } else {
      _timer = Timer.periodic(Duration(seconds: 1), (timer) {
        setState(() {
          if (_remainingSeconds > 0) {
            _remainingSeconds--;
          } else {
            _timer!.cancel();
            _isRunning = false;
            // Maybe show a notification or something
          }
        });
      });
      setState(() {
        _isRunning = true;
      });
    }
  }

  void _resetTimer() {
    if (_timer != null) {
      _timer!.cancel();
    }
    setState(() {
      _remainingSeconds = 25 * 60;
      _isRunning = false;
    });
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    if (_timer != null) {
      _timer!.cancel();
    }
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
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
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 40, vertical: 30),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(220),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withAlpha(150), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.purple[100]!.withAlpha(100),
                        blurRadius: 25,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Text(
                    _formatTime(_remainingSeconds),
                    style: TextStyle(
                      fontSize: 72,
                      fontWeight: FontWeight.w200,
                      color: Colors.lightBlue[800],
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ),
                SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: _isRunning ? Colors.red[50] : Colors.white.withAlpha(220),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withAlpha(100), width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey[200]!.withAlpha(80),
                            blurRadius: 10,
                            offset: Offset(0, 5),
                          ),
                        ],
                      ),
                      child: CupertinoButton(
                        padding: EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                        onPressed: _toggleTimer,
                        child: Text(
                          _isRunning ? 'Pausar' : 'Iniciar',
                          style: TextStyle(
                            color: _isRunning ? Colors.red[600] : Colors.purple[600],
                            fontFamily: 'SF Pro Text',
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 20),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(220),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withAlpha(100), width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey[200]!.withAlpha(80),
                            blurRadius: 10,
                            offset: Offset(0, 5),
                          ),
                        ],
                      ),
                      child: CupertinoButton(
                        padding: EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                        onPressed: _resetTimer,
                        child: Text(
                          'Reiniciar',
                          style: TextStyle(
                            color: Colors.lightBlue[600],
                            fontFamily: 'SF Pro Text',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}