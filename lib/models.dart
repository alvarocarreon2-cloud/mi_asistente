class Pendiente {
  String descripcion;
  String titulo;
  List<String> escaleta;
  int tiempoEstimado; // en minutos
  int dificultad; // 1-10
  int prioridad; // 1-10
  DateTime? horaAsignada;
  bool completado;
  bool focoActivado;
  String schedulingReason; // Razón de la sugerencia de fecha

  Pendiente({
    required this.descripcion,
    required this.titulo,
    required this.escaleta,
    required this.tiempoEstimado,
    required this.dificultad,
    required this.prioridad,
    this.horaAsignada,
    this.completado = false,
    this.focoActivado = false,
    this.schedulingReason = '',
  });
}