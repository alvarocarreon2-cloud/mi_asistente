import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'models.dart';
import 'dart:async';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';

class FocusScreen extends StatefulWidget {
  final Pendiente pendiente;
  final Function(Pendiente) onComplete;

  const FocusScreen({
    super.key,
    required this.pendiente,
    required this.onComplete,
  });

  @override
  _FocusScreenState createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _pulseController;
  Timer? _workTimer;
  Timer? _checkTimer;
  int _workedSeconds = 0;
  late AudioPlayer audioPlayer;
  bool _isMusicPlaying = false;
  bool _showTimer = false;
  bool _musicStarted = false;
  bool _showNotification = false;

  // emoji bouncing state
  final List<String> _emojis = ['🎯', '💡', '🧠', '📘', '🔔'];
  final List<Offset> _emojiPos = [];
  final List<Offset> _emojiVel = [];
  late Timer _emojiTimer;

  @override
  void initState() {
    super.initState();
    audioPlayer = AudioPlayer();

    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _initEmojis();
    _startWorkTimer();
    _startCheckTimer();
    _playRelaxingMusic();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pulseController.dispose();
    _workTimer?.cancel();
    _checkTimer?.cancel();
    _emojiTimer.cancel();
    audioPlayer.stop();
    audioPlayer.dispose();
    super.dispose();
  }

  final String _musicUrl =
      'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3';

  void _playRelaxingMusic() async {
    try {
      await audioPlayer.stop();
      await audioPlayer.play(UrlSource(_musicUrl));
      audioPlayer.setVolume(0.3);
      audioPlayer.setReleaseMode(ReleaseMode.loop);
      setState(() => _isMusicPlaying = true);
      _musicStarted = true;
    } catch (e) {
      print('Error playing music: $e');
    }
  }

  void _toggleMusic() async {
    if (_isMusicPlaying) {
      await audioPlayer.pause();
    } else {
      if (_musicStarted) {
        await audioPlayer.resume();
      } else {
        await audioPlayer.play(UrlSource(_musicUrl));
        audioPlayer.setReleaseMode(ReleaseMode.loop);
        _musicStarted = true;
      }
    }
    setState(() => _isMusicPlaying = !_isMusicPlaying);
  }

  void _startWorkTimer() {
    _workTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _workedSeconds++;
      });
    });
  }

  void _startCheckTimer() {
    _checkTimer = Timer.periodic(Duration(minutes: 5), (_) => _askContinue());
  }

  void _askContinue() {
    setState(() => _showNotification = true);
    Timer(Duration(minutes: 5), () {
      if (mounted && _showNotification) {
        _stopWorking();
      }
    });
  }

  void _continueWorking() {
    _checkTimer?.cancel();
    _startCheckTimer();
    setState(() => _showNotification = false);
  }

  void _stopWorking() {
    setState(() => _showNotification = false);
    _completeFocus();
  }

  String _formatTime(int seconds) {
    int hours = seconds ~/ 3600;
    int minutes = (seconds % 3600) ~/ 60;
    int secs = seconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _completeFocus() {
    widget.pendiente.completado = true;
    widget.onComplete(widget.pendiente);
    audioPlayer.stop();
  }

  void _initEmojis() {
    final random = Random();
    for (int i = 0; i < _emojis.length; i++) {
      _emojiPos.add(
        Offset(random.nextDouble() * 300, random.nextDouble() * 500),
      );
      _emojiVel.add(
        Offset(
          (random.nextDouble() - 0.5) * 4,
          (random.nextDouble() - 0.5) * 4,
        ),
      );
    }
    _emojiTimer = Timer.periodic(Duration(milliseconds: 20), (t) {
      setState(() {
        for (int i = 0; i < _emojis.length; i++) {
          Offset pos = _emojiPos[i];
          Offset vel = _emojiVel[i];
          double nx = pos.dx + vel.dx;
          double ny = pos.dy + vel.dy;
          if (nx < 0 || nx > MediaQuery.of(context).size.width - 30) {
            vel = Offset(-vel.dx, vel.dy);
          }
          if (ny < 0 || ny > MediaQuery.of(context).size.height - 30) {
            vel = Offset(vel.dx, -vel.dy);
          }
          _emojiVel[i] = vel;
          _emojiPos[i] = Offset(pos.dx + vel.dx, pos.dy + vel.dy);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! < 0) {
          _completeFocus();
        }
      },
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.purple[200]!, Colors.grey[200]!],
            ),
          ),
          child: Stack(
            children: [
              // bouncing emojis
              ...List.generate(_emojis.length, (i) {
                return Positioned(
                  left: _emojiPos[i].dx,
                  top: _emojiPos[i].dy,
                  child: Text(_emojis[i], style: TextStyle(fontSize: 40)),
                );
              }),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Enfocándose en',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                        fontFamily: 'SF Pro Text',
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      widget.pendiente.titulo,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w600,
                        color: Colors.purple[800],
                        fontFamily: 'SF Pro Display',
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 40),
                    // Cronómetro circular minimalista
                    SizedBox(
                      width: 120,
                      height: 120,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 120,
                            height: 120,
                            child: CircularProgressIndicator(
                              value: (_workedSeconds % 3600) / 3600,
                              strokeWidth: 3,
                              backgroundColor: Colors.purple[100]!.withOpacity(0.3),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.purple[300]!,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _showTimer = !_showTimer),
                            child: Icon(
                              CupertinoIcons.check_mark_circled,
                              size: 40,
                              color: Colors.purple[800],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 20),
                    if (_showTimer)
                      ScaleTransition(
                        scale: Tween<double>(begin: 0.95, end: 1.05).animate(
                          CurvedAnimation(
                            parent: _pulseController,
                            curve: Curves.easeInOut,
                          ),
                        ),
                        child: Container(
                          width: 220,
                          height: 220,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withAlpha(230),
                            border: Border.all(
                              color: Colors.white.withAlpha(150),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.purple[200]!.withAlpha(100),
                                blurRadius: 25,
                                offset: Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                FadeTransition(
                                  opacity: Tween<double>(begin: 0.6, end: 1.0)
                                      .animate(
                                        CurvedAnimation(
                                          parent: _animationController,
                                          curve: Curves.easeInOut,
                                        ),
                                      ),
                                  child: Icon(
                                    CupertinoIcons.check_mark_circled,
                                    size: 60,
                                    color: Colors.purple[800],
                                  ),
                                ),
                                SizedBox(height: 20),
                                Text(
                                  _formatTime(_workedSeconds),
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w300,
                                    color: Colors.purple[800],
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (_showNotification)
                Positioned(
                  top: 50,
                  left: 20,
                  right: 20,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(color: Colors.black26, blurRadius: 10),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '¿Sigues trabajando?',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: Colors.purple[800],
                            ),
                          ),
                          SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              CupertinoButton(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 30,
                                  vertical: 10,
                                ),
                                color: Colors.purple[100],
                                onPressed: _continueWorking,
                                child: Text(
                                  'Sí',
                                  style: TextStyle(color: Colors.purple[800]),
                                ),
                              ),
                              CupertinoButton(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 30,
                                  vertical: 10,
                                ),
                                color: Colors.red[100],
                                onPressed: _stopWorking,
                                child: Text(
                                  'No',
                                  style: TextStyle(color: Colors.red[800]),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // Leyenda de swipe up
              Positioned(
                bottom: 30,
                left: 0,
                right: 0,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.arrow_up,
                        size: 16,
                        color: Colors.grey[500],
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Desliza hacia arriba para salir',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                          fontFamily: 'SF Pro Text',
                        ),
                      ),
                    ],
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
