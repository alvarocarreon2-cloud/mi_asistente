import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mi Asistente',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: HomeScreen(),
    );
  }
}

class Task {
  final String title;
  final DateTime scheduledAt;

  Task({required this.title, required this.scheduledAt});
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<Task> _tasks = [];

  Future<void> _goToCapture() async {
    final Task? newTask = await Navigator.push<Task?>(
      context,
        MaterialPageRoute(builder: (_) => CaptureScreen()),
    );

    // Depuración: ver el valor retornado desde CaptureScreen
    // (si es null, no se agregará)
    // ignore: avoid_print
    print('Capture returned: $newTask');

    if (newTask == null) return;

      // Debug log
      // ignore: avoid_print
      print('Received new task: ${newTask.title} at ${newTask.scheduledAt}');

    setState(() {
      _tasks.add(newTask);
      _tasks.sort((a, b) => _compareScheduled(a, b));
    });
  }

  int _compareScheduled(Task a, Task b) {
    try {
      final DateTime aDt = a.scheduledAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final DateTime bDt = b.scheduledAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return aDt.compareTo(bDt);
    } catch (_) {
      // Fallback: keep original order if comparison fails
      return 0;
    }
  }

  Future<void> _editTask(int index) async {
    final task = _tasks[index];
    final edited = await showDialog<Task?>(
      context: context,
      builder: (context) {
        final TextEditingController controller = TextEditingController(text: task.title);
        DateTime pickedDate = task.scheduledAt;
        TimeOfDay pickedTime = TimeOfDay(hour: task.scheduledAt.hour, minute: task.scheduledAt.minute);

        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text('Editar pendiente'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: controller, decoration: const InputDecoration(border: OutlineInputBorder())),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(context: context, initialDate: pickedDate, firstDate: DateTime(now.year - 5), lastDate: DateTime(now.year + 5));
                        if (picked != null) setState(() => pickedDate = DateTime(picked.year, picked.month, picked.day, pickedTime.hour, pickedTime.minute));
                      },
                      icon: const Icon(Icons.calendar_today),
                      label: Text('${pickedDate.day}/${pickedDate.month}/${pickedDate.year}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final picked = await showTimePicker(context: context, initialTime: pickedTime);
                        if (picked != null) setState(() => pickedTime = picked);
                      },
                      icon: const Icon(Icons.access_time),
                      label: Text('${pickedTime.hour.toString().padLeft(2,'0')}:${pickedTime.minute.toString().padLeft(2,'0')}'),
                    ),
                  ),
                ]),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
              TextButton(
                onPressed: () {
                  final t = controller.text.trim();
                  if (t.isEmpty) return;
                  final combined = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute);
                  Navigator.pop(context, Task(title: t, scheduledAt: combined));
                },
                child: const Text('Guardar'),
              ),
            ],
          );
        });
      },
    );

    if (edited != null) {
      setState(() {
        _tasks[index] = edited;
        _tasks.sort((a, b) => _compareScheduled(a, b));
      });
    }
  }

  Future<void> _deleteTask(int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar'),
        content: const Text('¿Eliminar este pendiente?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _tasks.removeAt(index);
      });
    }
  }

  Future<void> _deleteAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar todos'),
        content: const Text('¿Eliminar todos los pendientes? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar todos')),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _tasks.clear());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inicio'), actions: [
        IconButton(
          tooltip: 'Eliminar todos',
          icon: const Icon(Icons.delete_sweep),
          onPressed: _deleteAll,
        ),
      ]),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Pendientes',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _tasks.isEmpty
                  ? const Center(
                      child: Text('Aún no tienes pendientes.'),
                    )
                  : ListView.separated(
                      itemCount: _tasks.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final task = _tasks[index];
                        String subtitle;
                        try {
                          final dt = task.scheduledAt;
                          subtitle = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
                              '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                        } catch (_) {
                          subtitle = 'Fecha inválida';
                        }

                        return ListTile(
                          leading: const Icon(Icons.assignment_outlined),
                          title: Text(task.title),
                          subtitle: Text(subtitle),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(icon: const Icon(Icons.edit), tooltip: 'Editar', onPressed: () => _editTask(index)),
                              IconButton(icon: const Icon(Icons.delete), tooltip: 'Eliminar', onPressed: () => _deleteTask(index)),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _goToCapture,
              icon: const Icon(Icons.mic),
              label: const Text('Capturar pendiente'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final TextEditingController _controller = TextEditingController();
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final now = TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: now);
    if (picked == null) return;
    setState(() => _selectedTime = picked);
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (_selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona fecha y hora')));
      return;
    }

    final scheduled = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );

    // Depuración: imprimir antes de salir
    // ignore: avoid_print
    print('Submitting task: $text at $scheduled');

    Navigator.pop(context, Task(title: text, scheduledAt: scheduled));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Capturar')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Cuéntame qué te encargaron (como lo dirías normal).',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: 'Ej: Presentación de estadística para el viernes...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today),
                    label: Text(_selectedDate == null
                        ? 'Seleccionar fecha'
                        : '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.access_time),
                    label: Text(_selectedTime == null
                        ? 'Seleccionar hora'
                        : '${_selectedTime!.hour.toString().padLeft(2,'0')}:${_selectedTime!.minute.toString().padLeft(2,'0')}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _submit,
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );
  }
}