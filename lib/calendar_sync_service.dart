import 'package:device_calendar/device_calendar.dart';
import 'weekly_planner_service.dart';

class CalendarSyncService {
  final DeviceCalendarPlugin _plugin = DeviceCalendarPlugin();

  Future<String?> syncPlanToCalendar(List<PlannedSession> plan) async {
    if (plan.isEmpty) {
      return 'No hay sesiones para sincronizar.';
    }

    final permissions = await _plugin.hasPermissions();
    if (!(permissions.data ?? false)) {
      final request = await _plugin.requestPermissions();
      if (!(request.data ?? false)) {
        return 'Permiso de calendario denegado.';
      }
    }

    final calendarsResult = await _plugin.retrieveCalendars();
    final calendars = calendarsResult.data;
    if (calendars == null || calendars.isEmpty) {
      return 'No se encontró un calendario disponible en el iPhone.';
    }

    Calendar? calendar = calendars.firstWhere(
      (c) => c.isReadOnly != true,
      orElse: () => calendars.first,
    );

    if (calendar.id == null) {
      return 'No se pudo obtener el calendario para guardar eventos.';
    }

    int created = 0;
    for (final session in plan) {
      final event = Event(
        calendar.id,
        title: 'Pendiente: ${session.pendiente.titulo}',
        description:
            'Plan sugerido por IA local · Dificultad ${session.pendiente.dificultad}/10 · Prioridad ${session.pendiente.prioridad}/10',
        start: session.start,
        end: session.end,
      );
      final result = await _plugin.createOrUpdateEvent(event);
      if (result?.isSuccess == true) {
        created++;
      }
    }

    return created == 0
        ? 'No se pudo crear eventos en calendario.'
        : 'Se sincronizaron $created sesiones en tu calendario.';
  }
}