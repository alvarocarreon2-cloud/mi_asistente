import 'models.dart';

class TimeSlot {
  final DateTime start;
  final DateTime end;

  TimeSlot({required this.start, required this.end});
}

class PlannedSession {
  final Pendiente pendiente;
  final DateTime start;
  final DateTime end;

  PlannedSession({
    required this.pendiente,
    required this.start,
    required this.end,
  });
}

class WeeklyPlannerService {
  static List<PlannedSession> buildWeeklyPlan(List<Pendiente> pendientes, {DateTime? now}) {
    final DateTime referenceNow = now ?? DateTime.now();
    final DateTime weekEnd = referenceNow.add(const Duration(days: 7));

    final List<Pendiente> pending = pendientes
        .where((p) => !p.completado)
        .toList()
      ..sort((a, b) {
        final int priorityCompare = b.prioridad.compareTo(a.prioridad);
        if (priorityCompare != 0) return priorityCompare;

        final DateTime aDue = a.horaAsignada ?? weekEnd;
        final DateTime bDue = b.horaAsignada ?? weekEnd;
        return aDue.compareTo(bDue);
      });

    final List<PlannedSession> sessions = [];
    final List<TimeSlot> freeSlots = _generateFreeSlots(referenceNow);

    for (final task in pending) {
      int remaining = task.tiempoEstimado.clamp(15, 240);
      for (final slot in freeSlots) {
        if (remaining <= 0) break;

        final DateTime slotStart = slot.start;
        final DateTime slotEnd = slot.end;

        final DateTime start = _nextAvailableStart(slotStart, slotEnd, sessions);
        if (!start.isBefore(slotEnd)) continue;

        final int availableMin = slotEnd.difference(start).inMinutes;
        if (availableMin < 15) continue;

        final int chunk = remaining > 90 ? 90 : remaining;
        final int useMin = chunk <= availableMin ? chunk : availableMin;
        if (useMin < 15) continue;

        final DateTime end = start.add(Duration(minutes: useMin));
        sessions.add(PlannedSession(pendiente: task, start: start, end: end));
        remaining -= useMin;
      }
    }

    sessions.sort((a, b) => a.start.compareTo(b.start));
    return sessions;
  }

  static DateTime? suggestNextSessionStart(List<Pendiente> pendientes, {DateTime? now}) {
    final session = suggestNextSession(pendientes, now: now);
    return session?.start;
  }

  static PlannedSession? suggestNextSession(List<Pendiente> pendientes, {DateTime? now}) {
    final plan = buildWeeklyPlan(pendientes, now: now);
    if (plan.isEmpty) return null;

    final DateTime referenceNow = now ?? DateTime.now();
    final upcoming = plan.where((session) => !session.end.isBefore(referenceNow)).toList();
    if (upcoming.isEmpty) return plan.first;
    return upcoming.first;
  }

  static List<TimeSlot> _generateFreeSlots(DateTime from) {
    final List<TimeSlot> slots = [];
    final DateTime startDay = DateTime(from.year, from.month, from.day);

    for (int i = 0; i < 7; i++) {
      final DateTime day = startDay.add(Duration(days: i));
      final bool isWeekend = day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

      if (isWeekend) {
        slots.add(TimeSlot(
          start: DateTime(day.year, day.month, day.day, 10, 0),
          end: DateTime(day.year, day.month, day.day, 13, 0),
        ));
        slots.add(TimeSlot(
          start: DateTime(day.year, day.month, day.day, 16, 0),
          end: DateTime(day.year, day.month, day.day, 19, 0),
        ));
      } else {
        slots.add(TimeSlot(
          start: DateTime(day.year, day.month, day.day, 18, 0),
          end: DateTime(day.year, day.month, day.day, 21, 0),
        ));
      }
    }

    return slots.where((slot) => slot.end.isAfter(from)).toList();
  }

  static DateTime _nextAvailableStart(DateTime slotStart, DateTime slotEnd, List<PlannedSession> sessions) {
    DateTime cursor = slotStart;
    final List<PlannedSession> sameSlotSessions = sessions
        .where((s) => s.start.isBefore(slotEnd) && s.end.isAfter(slotStart))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    for (final session in sameSlotSessions) {
      if (cursor.isBefore(session.start)) {
        return cursor;
      }
      if (cursor.isBefore(session.end)) {
        cursor = session.end.add(const Duration(minutes: 10));
      }
    }
    return cursor;
  }
}