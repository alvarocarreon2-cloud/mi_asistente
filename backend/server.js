const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');

dotenv.config();

const app = express();
app.use(cors());
app.use(express.json({ limit: '256kb' }));

const PORT = Number(process.env.PORT || 8787);
const GEMINI_API_KEY = process.env.GEMINI_API_KEY || '';
const GEMINI_MODEL = process.env.GEMINI_MODEL || 'gemini-1.5-flash';
const GEMINI_API_VERSION = process.env.GEMINI_API_VERSION || 'v1beta';
const OPENAI_API_KEY = process.env.OPENAI_API_KEY || '';
const OPENAI_MODEL = process.env.OPENAI_MODEL || 'gpt-4o-mini';
const AI_PROVIDER = String(process.env.AI_PROVIDER || 'auto').toLowerCase();
const OPENAI_MODEL_CANDIDATES = [
  OPENAI_MODEL,
  'gpt-5.4-mini',
  'gpt-4o-mini',
  'gpt-4.1-mini'
].filter((value, index, arr) => value && arr.indexOf(value) === index);
const GEMINI_MODEL_CANDIDATES = [
  GEMINI_MODEL,
  'gemini-2.0-flash',
  'gemini-2.0-flash-lite',
  'gemini-1.5-flash-latest',
  'gemini-1.5-flash'
];

const MAX_EVENT_RETENTION = Number(process.env.EVENT_RETENTION || 300);
let eventSequence = 0;
const realtimeEvents = [];
const appointmentsByStudent = new Map();

function normalizePushRole(value) {
  const role = String(value || '').trim().toLowerCase();
  if (role === 'student' || role === 'professional') return role;
  return '';
}

function normalizePushUserId(value) {
  return String(value || '').trim().slice(0, 120);
}

function pushRealtimeEvent({ role, userId, title, detail, type, payload }) {
  eventSequence += 1;
  realtimeEvents.push({
    id: eventSequence,
    role,
    userId,
    title: String(title || '').slice(0, 120),
    detail: String(detail || '').slice(0, 280),
    type: String(type || 'generic').slice(0, 60),
    payload: payload && typeof payload === 'object' ? payload : {},
    createdAt: new Date().toISOString()
  });

  if (realtimeEvents.length > MAX_EVENT_RETENTION) {
    realtimeEvents.splice(0, realtimeEvents.length - MAX_EVENT_RETENTION);
  }
}

function pullRealtimeEvents({ role, userId, afterId }) {
  return realtimeEvents.filter(
    (event) =>
      event.role === role &&
      event.userId === userId &&
      Number(event.id) > Number(afterId || 0)
  );
}

function normalizeStudentName(value) {
  return String(value || '').trim().slice(0, 120);
}

function normalizeAppointmentStatus(value) {
  const status = String(value || '').trim().toLowerCase();
  if (status === 'confirmed') return 'confirmed';
  if (status === 'declined') return 'declined';
  return 'pending';
}

function sanitizeStatusHistory(value) {
  if (!Array.isArray(value)) return [];
  return value
    .map((entry) => ({
      status: normalizeAppointmentStatus(entry?.status),
      actor: String(entry?.actor || 'system').slice(0, 32),
      changedAt: String(entry?.changedAt || new Date().toISOString()),
      note: String(entry?.note || '').slice(0, 280)
    }))
    .filter((entry) => Boolean(entry.changedAt));
}

function sanitizeAppointment(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const id = String(raw.id || '').trim().slice(0, 180);
  const scheduledFor = String(raw.scheduledFor || '').trim();
  const reason = String(raw.reason || '').trim().slice(0, 280);
  if (!id || !scheduledFor || !reason) return null;

  return {
    id,
    scheduledFor,
    durationMinutes: Math.max(15, Math.min(360, Number(raw.durationMinutes) || 45)),
    reason,
    createdAt: String(raw.createdAt || new Date().toISOString()),
    status: normalizeAppointmentStatus(raw.status),
    statusHistory: sanitizeStatusHistory(raw.statusHistory)
  };
}

function sortAppointments(items) {
  return [...items].sort((a, b) => String(a.scheduledFor).localeCompare(String(b.scheduledFor)));
}

const CLINICAL_KB = [
  'WHO-5: 0-100, valores <=50 pueden indicar bienestar bajo y necesidad de seguimiento.',
  'PHQ-2: 0-6, valores >=3 sugieren cribado positivo para sintomas depresivos.',
  'GAD-2: 0-6, valores >=3 sugieren cribado positivo para sintomas ansiosos.',
  'El objetivo es contencion, escucha activa y orientacion a ayuda profesional, no diagnostico.',
  'Si hay ideacion autolesiva o riesgo inminente, se debe escalar a adulto responsable y servicio de emergencia local.'
];

function normalizeMinutes(value) {
  const n = Number(value) || 45;
  return Math.min(360, Math.max(15, Math.round(n)));
}

function normalizeRisk(value) {
  const v = String(value || '').toLowerCase();
  if (v === 'high') return 'high';
  if (v === 'medium') return 'medium';
  return 'low';
}

function detectRiskSignals(text) {
  const normalized = String(text || '').toLowerCase();
  const high = [
    'me quiero morir',
    'quiero desaparecer',
    'hacerme daño',
    'lastimarme',
    'no quiero vivir',
    'suicid'
  ];
  const medium = ['ansiedad', 'ataque de panico', 'no duermo', 'muy triste', 'solo', 'agotado'];

  if (high.some((w) => normalized.includes(w))) return 'high';
  if (medium.some((w) => normalized.includes(w))) return 'medium';
  return 'low';
}

function mergeRisk(a, b) {
  const order = { low: 0, medium: 1, high: 2 };
  return order[a] >= order[b] ? a : b;
}

function resolveAiFirstRisk({ aiRisk, fallbackRisk, baselineRisk, hasAiRisk }) {
  const normalizedBaseline = normalizeRisk(baselineRisk);
  const normalizedFallback = normalizeRisk(fallbackRisk);
  const normalizedAi = normalizeRisk(aiRisk);

  // Keep a deterministic high-risk guardrail if any local safety rule saw
  // explicitly critical content, but otherwise trust the model's semantic read.
  if (normalizedFallback === 'high' || normalizedBaseline === 'high') {
    return 'high';
  }

  if (hasAiRisk) {
    return normalizedAi;
  }

  return mergeRisk(normalizedBaseline, normalizedFallback);
}

function fallbackWellbeingReply(message, risk) {
  if (risk === 'high') {
    return 'Gracias por decirmelo. Lo que cuentas es muy importante. No estas solo. En este momento te recomiendo buscar de inmediato a un adulto de confianza o al personal de orientacion de tu escuela. Si te sientes en peligro, llama a emergencias de tu pais ahora.';
  }
  if (risk === 'medium') {
    return 'Gracias por compartirlo. Noto que estas cargando bastante. Podemos dar un paso corto ahora: respira 4-4-6 por un minuto y dime que fue lo mas dificil de hoy para ayudarte a ordenarlo.';
  }
  return 'Gracias por confiar en mi. Me alegra que lo compartas. Para cuidarte mejor hoy, que situacion te hizo sentir mejor y cual te costo mas?';
}

function matchEvidenceTerms(text) {
  const normalized = String(text || '').toLowerCase();
  const terms = [
    'ansiedad',
    'ansioso',
    'preocupacion',
    'nervioso',
    'estres',
    'estresado',
    'agotado',
    'presion',
    'saturado',
    'triste',
    'solo',
    'no duermo',
    'me quiero morir',
    'quiero desaparecer',
    'hacerme daño',
    'lastimarme',
    'no quiero vivir',
    'suicid'
  ];

  return terms.filter((term) => normalized.includes(term)).slice(0, 6);
}

function buildReflectionFindings(risk, evidenceTerms) {
  const findings = [];
  const joined = evidenceTerms.join(', ');

  if (evidenceTerms.some((term) => term.includes('ans'))) {
    findings.push('senales de ansiedad');
  }
  if (evidenceTerms.some((term) => term.includes('estres') || term.includes('presion') || term.includes('saturado'))) {
    findings.push('senales de estres');
  }
  if (evidenceTerms.some((term) => term.includes('triste') || term.includes('agotado') || term.includes('solo'))) {
    findings.push('malestar emocional');
  }
  if (risk === 'high') {
    findings.push('indicadores de riesgo critico');
  }
  if (findings.length === 0) {
    findings.push('sin indicadores criticos');
  }

  return { findings, joined };
}

function buildReflectionRationale(risk, findings, evidenceTerms, latestCheckIn) {
  const evidenceText = evidenceTerms.length ? `se encontraron terminos como ${evidenceTerms.join(', ')}` : 'no se detectaron terminos de alarma claros';
  const checkInText = latestCheckIn
    ? `El ultimo check-in marco WHO-5 ${Number(latestCheckIn?.who5Percent || 0)}/100, PHQ-2 ${Number(latestCheckIn?.phq2Score || 0)}/6 y GAD-2 ${Number(latestCheckIn?.gad2Score || 0)}/6.`
    : 'No hay un check-in reciente para contrastar este comentario.';
  const actionByRisk =
    risk === 'high'
      ? 'Activar protocolo inmediato con adulto responsable y derivacion profesional el mismo dia.'
      : risk === 'medium'
        ? 'Realizar seguimiento en 24-72h, revisar sueno/carga academica y sostener escucha activa.'
        : 'Mantener seguimiento preventivo y reforzar factores protectores durante la semana.';
  const evidenceList = (evidenceTerms.length ? evidenceTerms : ['sin termino gatillo explicito'])
    .map((term) => {
      const lower = String(term).toLowerCase();
      let connotation = 'expresion de malestar general no especifico';
      let importance = 'Puede reflejar carga emocional inicial que conviene monitorear para prevenir escalada.';

      if (lower.includes('ans')) {
        connotation = 'activacion ansiosa y estado de hipervigilancia';
        importance = 'La ansiedad sostenida suele afectar concentracion, descanso y regulacion emocional.';
      } else if (lower.includes('no duermo') || lower.includes('sueno')) {
        connotation = 'alteracion del sueno y recuperacion insuficiente';
        importance = 'Dormir poco aumenta irritabilidad, fatiga cognitiva y sensibilidad al estres.';
      } else if (lower.includes('estres') || lower.includes('presion') || lower.includes('saturado')) {
        connotation = 'sobrecarga por estres percibido';
        importance = 'La sobrecarga sostenida puede deteriorar rendimiento academico y bienestar diario.';
      } else if (lower.includes('triste') || lower.includes('solo') || lower.includes('agotado')) {
        connotation = 'desgaste emocional y posible aislamiento';
        importance = 'El aislamiento y el agotamiento pueden reducir redes de apoyo y aumentar vulnerabilidad.';
      } else if (lower.includes('suicid') || lower.includes('hacerme dano') || lower.includes('no quiero vivir')) {
        connotation = 'contenido de riesgo critico autolesivo';
        importance = 'Implica posible riesgo inminente y requiere intervencion inmediata sin demora.';
      }

      return `- Frase detectada: "${term}". Connotacion clinica: ${connotation}. Por que importa: ${importance}. Accion sugerida: ${actionByRisk}`;
    })
    .join('\n');

  return `Resumen profesional: ${evidenceText}; hallazgos centrales: ${findings.join(', ')}. ${checkInText}\nAnalisis por evidencia:\n${evidenceList}`;
}

function ensureStructuredRationaleText(rationale, risk, findings, evidenceTerms, latestCheckIn) {
  const base = buildReflectionRationale(risk, findings, evidenceTerms, latestCheckIn);
  const current = String(rationale || '').trim();
  if (!current) return base;

  const hasStructuredMarkers =
    /frase detectada\s*:/i.test(current) &&
    /connotacion clinica\s*:/i.test(current) &&
    /accion sugerida\s*:/i.test(current);

  if (hasStructuredMarkers) return current;
  return `${base}\n\nNota complementaria IA: ${current}`;
}

function buildReflectionInterpretation(risk, findings, evidenceTerms, latestCheckIn) {
  const evidenceText = evidenceTerms.length ? evidenceTerms.join(', ') : 'sin terminos gatillo directos';
  const checkInText = latestCheckIn
    ? `Se contrasta con WHO-5 ${Number(latestCheckIn?.who5Percent || 0)}/100, PHQ-2 ${Number(latestCheckIn?.phq2Score || 0)}/6 y GAD-2 ${Number(latestCheckIn?.gad2Score || 0)}/6.`
    : 'No hay check-in reciente para contrastar.';

  if (risk === 'high') {
    return `Detecto un comentario con carga emocional alta. Los hallazgos principales son ${findings.join(', ')} y la evidencia textual relevante incluye ${evidenceText}. ${checkInText} Por eso sugiero contacto profesional prioritario y verificacion de apoyo inmediato.`;
  }
  if (risk === 'medium') {
    return `Detecto un comentario con carga emocional moderada. Los hallazgos principales son ${findings.join(', ')} y la evidencia textual relevante incluye ${evidenceText}. ${checkInText} Por eso sugiero seguimiento breve, escucha activa y monitoreo en los proximos dias.`;
  }
  return `Detecto un comentario con tono estable o protector. Los hallazgos principales son ${findings.join(', ')} y la evidencia textual relevante incluye ${evidenceText}. ${checkInText} Por eso sugiero seguimiento preventivo y reforzar factores protectores.`;
}

function analyzeReflectionFallback(payload) {
  const reflection = String(payload?.reflection || '').trim();
  const currentRisk = normalizeRisk(payload?.currentRisk);
  const latestCheckIn = payload?.latestCheckIn && typeof payload.latestCheckIn === 'object' ? payload.latestCheckIn : null;
  const textRisk = detectRiskSignals(reflection);
  let detectedRisk = mergeRisk(currentRisk, textRisk);

  if (latestCheckIn) {
    const who5 = Number(latestCheckIn?.who5Percent || 0);
    const phq2 = Number(latestCheckIn?.phq2Score || 0);
    const gad2 = Number(latestCheckIn?.gad2Score || 0);
    if (who5 < 50 && phq2 >= 3 && gad2 >= 3) {
      detectedRisk = mergeRisk(detectedRisk, 'high');
    } else if (who5 < 50 || phq2 >= 3 || gad2 >= 3) {
      detectedRisk = mergeRisk(detectedRisk, 'medium');
    }
  }

  const evidenceTerms = matchEvidenceTerms(reflection);
  const { findings } = buildReflectionFindings(detectedRisk, evidenceTerms);
  const rationale = buildReflectionRationale(detectedRisk, findings, evidenceTerms, latestCheckIn);
  const interpretation = buildReflectionInterpretation(detectedRisk, findings, evidenceTerms, latestCheckIn);

  const alerts = [];
  if (detectedRisk === 'high') {
    alerts.push({
      title: 'Alerta alta detectada por comentario',
      detail: 'El comentario muestra senales criticas. Se recomienda intervencion hoy.'
    });
  } else if (detectedRisk === 'medium') {
    alerts.push({
      title: 'Alerta preventiva',
      detail: 'El comentario muestra carga emocional moderada. Sugerido seguimiento en 24-72h.'
    });
  }

  return {
    data: {
      interpretation,
      detectedFindings: findings,
      rationale,
      evidenceTerms,
      patterns: evidenceTerms.length ? evidenceTerms : ['seguimiento general'],
      detectedRisk,
      alerts,
      source: 'backend-wellbeing-reflection'
    }
  };
}

function extractReflectionFromMessage(message) {
  const raw = String(message || '').trim();
  if (!raw) return '';

  const quoted = raw.match(/comentario\s*:\s*["“](.+?)["”]/i);
  if (quoted && quoted[1]) {
    return quoted[1].trim();
  }

  return raw;
}

function parseProviderJson(text) {
  const raw = String(text || '').trim();
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch (_) {
    const fenced = raw.match(/```json\s*([\s\S]*?)```/i) || raw.match(/```\s*([\s\S]*?)```/i);
    if (fenced && fenced[1]) {
      try {
        return JSON.parse(fenced[1].trim());
      } catch (_) {
        return null;
      }
    }
    const start = raw.indexOf('{');
    const end = raw.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        return JSON.parse(raw.slice(start, end + 1));
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

async function generateGeminiText(prompt) {
  const payload = {
    contents: [
      {
        parts: [{ text: prompt }]
      }
    ],
    generationConfig: {
      temperature: 0.2
    }
  };

  let lastError = null;

  for (const model of GEMINI_MODEL_CANDIDATES) {
    const url = `https://generativelanguage.googleapis.com/${GEMINI_API_VERSION}/models/${model}:generateContent?key=${GEMINI_API_KEY}`;
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });

    if (!response.ok) {
      const body = await response.text();
      lastError = body;
      continue;
    }

    const decoded = await response.json();
    const text = decoded?.candidates?.[0]?.content?.parts?.[0]?.text;
    if (typeof text === 'string' && text.trim()) {
      return { text, model };
    }
  }

  throw new Error(lastError || 'No se obtuvo respuesta valida de ningun modelo');
}

async function generateOpenAiText(prompt) {
  let lastError = null;

  for (const model of OPENAI_MODEL_CANDIDATES) {
    const payload = {
      model,
      messages: [
        {
          role: 'system',
          content: 'Responde solo con JSON valido. No incluyas markdown ni bloques de codigo.'
        },
        {
          role: 'user',
          content: prompt
        }
      ],
      temperature: 0.2
    };

    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${OPENAI_API_KEY}`
      },
      body: JSON.stringify(payload)
    });

    if (!response.ok) {
      lastError = await response.text();
      continue;
    }

    const decoded = await response.json();
    const text = decoded?.choices?.[0]?.message?.content;
    if (typeof text === 'string' && text.trim()) {
      return { text, model };
    }
  }

  throw new Error(lastError || 'Respuesta vacia de OpenAI');
}

async function generateAiText(prompt) {
  const providers =
    AI_PROVIDER === 'openai'
      ? ['openai']
      : AI_PROVIDER === 'gemini'
        ? ['gemini']
        : ['openai', 'gemini'];

  let lastError = null;

  for (const provider of providers) {
    try {
      if (provider === 'openai' && OPENAI_API_KEY) {
        const result = await generateOpenAiText(prompt);
        return { ...result, provider: 'openai' };
      }
      if (provider === 'gemini' && GEMINI_API_KEY) {
        const result = await generateGeminiText(prompt);
        return { ...result, provider: 'gemini' };
      }
    } catch (e) {
      lastError = e instanceof Error ? e.message : String(e);
    }
  }

  throw new Error(lastError || 'No hay proveedor IA disponible');
}

app.get('/health', (_, res) => {
  res.json({
    ok: true,
    providerPreference: AI_PROVIDER,
    hasGeminiKey: GEMINI_API_KEY.length > 0,
    hasOpenAiKey: OPENAI_API_KEY.length > 0,
    realtimeEventsEnabled: true,
    retainedEvents: realtimeEvents.length
  });
});

app.post('/events/publish', (req, res) => {
  try {
    const role = normalizePushRole(req.body?.role);
    const userId = normalizePushUserId(req.body?.userId);
    const title = String(req.body?.title || '').trim();
    const detail = String(req.body?.detail || '').trim();
    const type = String(req.body?.type || 'generic').trim();
    const payload = req.body?.payload;

    if (!role || !userId || !title || !detail) {
      return res.status(400).json({
        error: 'role, userId, title y detail son requeridos'
      });
    }

    pushRealtimeEvent({ role, userId, title, detail, type, payload });

    return res.json({
      ok: true,
      role,
      userId,
      latestEventId: eventSequence,
      retainedEvents: realtimeEvents.length
    });
  } catch (error) {
    return res.status(500).json({
      error: 'Fallo publicando evento',
      detail: error instanceof Error ? error.message : String(error)
    });
  }
});

app.get('/events/poll', (req, res) => {
  try {
    const role = normalizePushRole(req.query?.role);
    const userId = normalizePushUserId(req.query?.userId);
    const afterId = Number(req.query?.after || 0);

    if (!role || !userId) {
      return res.status(400).json({
        error: 'role y userId son requeridos'
      });
    }

    const events = pullRealtimeEvents({ role, userId, afterId });

    return res.json({
      ok: true,
      events,
      latestEventId: events.isNotEmpty
        ? events[events.length - 1].id
        : afterId
    });
  } catch (error) {
    return res.status(500).json({
      error: 'Fallo consultando eventos',
      detail: error instanceof Error ? error.message : String(error)
    });
  }
});

app.post('/appointments/sync-student', (req, res) => {
  try {
    const studentName = normalizeStudentName(req.body?.studentName);
    const appointments = Array.isArray(req.body?.appointments)
      ? req.body.appointments.map(sanitizeAppointment).filter(Boolean)
      : [];

    if (!studentName) {
      return res.status(400).json({ error: 'studentName es requerido' });
    }

    appointmentsByStudent.set(studentName, sortAppointments(appointments));
    return res.json({
      ok: true,
      studentName,
      count: appointments.length
    });
  } catch (error) {
    return res.status(500).json({
      error: 'Fallo sincronizando citas del estudiante',
      detail: error instanceof Error ? error.message : String(error)
    });
  }
});

app.get('/appointments/by-student', (req, res) => {
  try {
    const studentName = normalizeStudentName(req.query?.studentName);
    if (!studentName) {
      return res.status(400).json({ error: 'studentName es requerido' });
    }

    const appointments = appointmentsByStudent.get(studentName) || [];
    return res.json({
      ok: true,
      studentName,
      appointments
    });
  } catch (error) {
    return res.status(500).json({
      error: 'Fallo obteniendo citas del estudiante',
      detail: error instanceof Error ? error.message : String(error)
    });
  }
});

app.get('/appointments/all', (_, res) => {
  try {
    const students = Array.from(appointmentsByStudent.entries()).map(([studentName, appointments]) => ({
      studentName,
      appointments
    }));

    return res.json({
      ok: true,
      students
    });
  } catch (error) {
    return res.status(500).json({
      error: 'Fallo obteniendo agenda global',
      detail: error instanceof Error ? error.message : String(error)
    });
  }
});

app.post('/ai/analyze', async (req, res) => {
  try {
    if (!GEMINI_API_KEY && !OPENAI_API_KEY) {
      return res.status(503).json({ error: 'No hay API key configurada (OPENAI_API_KEY o GEMINI_API_KEY).' });
    }

    const input = String(req.body?.input || '').trim();
    const extraDetails = String(req.body?.extraDetails || '').trim();
    const now = String(req.body?.now || new Date().toISOString());
    const pendingContext = Array.isArray(req.body?.pendingContext)
      ? req.body.pendingContext.slice(0, 8).map((e) => String(e))
      : [];

    if (!input) {
      return res.status(400).json({ error: 'input es requerido' });
    }

    const combined = `${input} ${extraDetails}`.trim();
    const contextBlock = pendingContext.length
      ? pendingContext.map((e) => `- ${e}`).join('\n')
      : 'No hay otras tareas activas.';

    const prompt =
      'Eres un planificador de productividad preciso. Responde solo JSON válido con estas llaves: ' +
      'generated_title (string corto), plan_steps (array 4-6 pasos concretos para esta tarea considerando el resto de pendientes), ' +
      'estimated_minutes (int 15-360 exacto y realista, NO aproximaciones vagas), difficulty (int 1-10), priority (int 1-10), ' +
      'needs_deadline_clarification (bool), clarification_question (string corta en español), ' +
      'due_text (string opcional como "mañana 18:00"), confidence (number 0-1). ' +
      `Ahora: ${now}. Tarea objetivo: "${combined}".\nPendientes activos:\n${contextBlock}\n` +
      'Calcula tiempo por descomposición de subtareas y devuelve minutos exactos.';

    let text;
    try {
      const generated = await generateAiText(prompt);
      text = generated.text;
    } catch (e) {
      return res.status(502).json({
        error: 'Error del proveedor IA',
        providerError: e instanceof Error ? e.message : String(e)
      });
    }

    const ai = parseProviderJson(text);
    if (!ai || typeof ai !== 'object') {
      return res.status(502).json({ error: 'JSON invalido del proveedor IA' });
    }

    const data = {
      generated_title:
        typeof ai.generated_title === 'string' && ai.generated_title.trim()
          ? ai.generated_title.trim()
          : input,
      plan_steps: Array.isArray(ai.plan_steps)
        ? ai.plan_steps.map((e) => String(e).trim()).filter(Boolean).slice(0, 6)
        : [],
      estimated_minutes: normalizeMinutes(ai.estimated_minutes),
      difficulty: Math.max(1, Math.min(10, Number(ai.difficulty) || 5)),
      priority: Math.max(1, Math.min(10, Number(ai.priority) || 5)),
      needs_deadline_clarification: ai.needs_deadline_clarification === true,
      clarification_question:
        typeof ai.clarification_question === 'string' && ai.clarification_question.trim()
          ? ai.clarification_question.trim()
          : '¿Para cuándo lo necesitas?',
      due_text: typeof ai.due_text === 'string' ? ai.due_text.trim().toLowerCase() : '',
      confidence: Math.max(0, Math.min(1, Number(ai.confidence) || 0.8)),
      source: 'backend-ai'
    };

    return res.json({ data });
  } catch (error) {
    return res.status(500).json({
      error: 'Fallo interno en backend',
      detail: error instanceof Error ? error.message : String(error)
    });
  }
});

app.post('/ai/wellbeing-chat', async (req, res) => {
  try {
    const message = String(req.body?.message || '').trim();
    const currentRisk = normalizeRisk(req.body?.currentRisk);
    const analysisMode = /analiza este comentario|profesional escolar|que detectaste y por que/i.test(message);
    const reflectionText = extractReflectionFromMessage(message);
    const latestCheckIn = req.body?.latestCheckIn && typeof req.body.latestCheckIn === 'object'
      ? req.body.latestCheckIn
      : null;
    const sensorContext = req.body?.sensorContext && typeof req.body.sensorContext === 'object'
      ? req.body.sensorContext
      : null;
    const recentMessages = Array.isArray(req.body?.recentMessages)
      ? req.body.recentMessages
          .slice(-8)
          .map((m) => ({
            sender: String(m?.sender || 'user').slice(0, 10),
            text: String(m?.text || '').slice(0, 600)
          }))
      : [];

    if (!message) {
      return res.status(400).json({ error: 'message es requerido' });
    }

    const textRisk = detectRiskSignals(message);
    let detectedRisk = mergeRisk(currentRisk, textRisk);

    if (latestCheckIn) {
      const who5 = Number(latestCheckIn?.who5Percent || 0);
      const phq2 = Number(latestCheckIn?.phq2Score || 0);
      const gad2 = Number(latestCheckIn?.gad2Score || 0);
      if (phq2 >= 5 || gad2 >= 5 || who5 <= 28) {
        detectedRisk = mergeRisk(detectedRisk, 'high');
      } else if (phq2 >= 3 || gad2 >= 3 || who5 <= 50) {
        detectedRisk = mergeRisk(detectedRisk, 'medium');
      }
    }

    if (sensorContext) {
      const sleepHours = Number(sensorContext?.sleepHours ?? 8);
      const screenMinutes = Number(sensorContext?.screenMinutes ?? 0);
      const steps = Number(sensorContext?.steps ?? 0);
      const restingHeartRate = Number(sensorContext?.restingHeartRate ?? 0);

      if (sleepHours < 5 || screenMinutes > 420 || steps < 2500 || restingHeartRate > 95) {
        detectedRisk = mergeRisk(detectedRisk, 'medium');
      }
      if (sleepHours < 4 && restingHeartRate > 105) {
        detectedRisk = mergeRisk(detectedRisk, 'high');
      }
    }

    const alerts = [];
    if (detectedRisk === 'high') {
      alerts.push({
        title: 'Alerta alta de bienestar',
        detail: 'Se detectaron senales de riesgo alto. Activar protocolo de intervencion inmediata.'
      });
    } else if (detectedRisk === 'medium') {
      alerts.push({
        title: 'Alerta preventiva',
        detail: 'Se detectaron senales de malestar moderado. Sugerir seguimiento clinico en 24-72h.'
      });
    }

    if (!GEMINI_API_KEY && !OPENAI_API_KEY) {
      const fallbackAnalysis = analyzeReflectionFallback({
        reflection: reflectionText,
        currentRisk,
        latestCheckIn
      });
      return res.json({
        data: {
          replyText: fallbackWellbeingReply(message, detectedRisk),
          detectedRisk,
          alerts,
          source: 'fallback-no-key',
          interpretation: fallbackAnalysis.data.interpretation,
          detectedFindings: fallbackAnalysis.data.detectedFindings,
          rationale: fallbackAnalysis.data.rationale,
          evidenceTerms: fallbackAnalysis.data.evidenceTerms,
          patterns: fallbackAnalysis.data.patterns,
          analysisMode
        }
      });
    }

    const contextCheckIn = latestCheckIn
      ? `Ultimo check-in: WHO-5=${Number(latestCheckIn?.who5Percent || 0)}/100, PHQ-2=${Number(
          latestCheckIn?.phq2Score || 0
        )}/6, GAD-2=${Number(latestCheckIn?.gad2Score || 0)}/6. Resumen: ${String(
          latestCheckIn?.summary || ''
        )}`
      : 'No hay check-in reciente.';

    const contextMessages = recentMessages
      .map((m) => `${m.sender}: ${m.text}`)
      .join('\n');

    const sensorBlock = sensorContext
      ? `\nContexto de senales del dia: sueno=${Number(sensorContext?.sleepHours ?? 0)}h, pantalla=${Number(
          sensorContext?.screenMinutes ?? 0
        )}min, pasos=${Number(sensorContext?.steps ?? 0)}, FC reposo=${Number(
          sensorContext?.restingHeartRate ?? 0
        )} bpm.`
      : '\nSin senales de sensores disponibles hoy.';

    const prompt = analysisMode
      ? 'Eres un analista de bienestar escolar para profesionales. No diagnostiques. ' +
        'Evalua el sentido completo del comentario, no solo palabras exactas. ' +
        'Debes inferir gravedad desde contexto, intencionalidad, desesperanza, aislamiento, carga percibida, ideas de no seguir, despedida, autolesion directa o indirecta, y lenguaje coloquial o con rodeos. ' +
        'Explica de forma natural y detallada: que detectaste, por que lo consideras y que connotaciones tienen las frases del estudiante. ' +
        'En el campo rationale usa formato fijo por cada hallazgo: Frase detectada, Connotacion clinica, Por que importa y Accion sugerida. ' +
        'Devuelve SOLO JSON valido con estas llaves: ' +
        '{"replyText":"...","interpretation":"...","detectedFindings":["..."],"rationale":"...","evidenceTerms":["..."],"patterns":["..."],"detectedRisk":"low|medium|high","alerts":[{"title":"...","detail":"..."}]}. ' +
        `\nConocimiento clinico:\n- ${CLINICAL_KB.join('\n- ')}\n` +
        `\nRiesgo preliminar ya detectado: ${detectedRisk}. Usalo solo como contexto, no como respuesta final; puedes subirlo o bajarlo si el significado global del mensaje lo justifica.\n` +
        `${contextCheckIn}\n` +
        sensorBlock +
        `Historial reciente:\n${contextMessages || 'Sin historial'}\n` +
        `Comentario actual del estudiante: ${reflectionText}`
      : 'Eres un asistente de bienestar escolar para adolescentes. Tu rol es apoyo emocional breve, no diagnostico. ' +
        'Antes de responder, evalua semanticamente la gravedad del mensaje completo y no dependas solo de palabras clave. ' +
        'Responde SIEMPRE en espanol neutro, 2-4 frases maximo, tono calido y concreto, y cierra con una sola pregunta util. ' +
        'Si hay riesgo alto, prioriza seguridad inmediata y contacto con adulto/profesional. ' +
        'Devuelve SOLO JSON valido con estas llaves: ' +
        '{"replyText":"...","detectedRisk":"low|medium|high","alerts":[{"title":"...","detail":"..."}]}.' +
        `\nConocimiento clinico:\n- ${CLINICAL_KB.join('\n- ')}\n` +
        `\nRiesgo preliminar ya detectado: ${detectedRisk}. Usalo solo como contexto, no como respuesta final; puedes subirlo o bajarlo si el significado global del mensaje lo justifica.\n` +
        `${contextCheckIn}\n` +
        sensorBlock +
        `Historial reciente:\n${contextMessages || 'Sin historial'}\n` +
        `Mensaje actual del estudiante: ${message}`;

    let text;
    try {
      const generated = await generateAiText(prompt);
      text = generated.text;
    } catch (e) {
      return res.json({
        data: {
          replyText: fallbackWellbeingReply(message, detectedRisk),
          detectedRisk,
          alerts,
          source: 'fallback-provider-error',
          providerError: e instanceof Error ? e.message.slice(0, 500) : String(e).slice(0, 500)
        }
      });
    }

    const ai = parseProviderJson(text);
    if (!ai || typeof ai !== 'object') {
      return res.status(502).json({ error: 'JSON invalido del proveedor IA' });
    }

    const hasAiRisk = typeof ai?.detectedRisk === 'string' && ai.detectedRisk.trim().length > 0;
    const aiRisk = normalizeRisk(ai?.detectedRisk);
    const fallbackAnalysis = analyzeReflectionFallback({
      reflection: reflectionText,
      currentRisk,
      latestCheckIn
    });
    const finalRisk = resolveAiFirstRisk({
      aiRisk,
      fallbackRisk: fallbackAnalysis.data.detectedRisk,
      baselineRisk: detectedRisk,
      hasAiRisk
    });
    const aiAlerts = Array.isArray(ai?.alerts)
      ? ai.alerts
          .slice(0, 2)
          .map((a) => ({
            title: String(a?.title || 'Alerta preventiva').slice(0, 120),
            detail: String(a?.detail || 'Sugerido seguimiento clinico.').slice(0, 300)
          }))
      : alerts;

    const interpretation =
      typeof ai?.interpretation === 'string' && ai.interpretation.trim()
        ? ai.interpretation.trim()
        : fallbackAnalysis.data.interpretation;

    const detectedFindings = Array.isArray(ai?.detectedFindings)
      ? ai.detectedFindings.map((v) => String(v).trim()).filter(Boolean).slice(0, 8)
      : fallbackAnalysis.data.detectedFindings;

    const rawRationale =
      typeof ai?.rationale === 'string' && ai.rationale.trim()
        ? ai.rationale.trim()
        : fallbackAnalysis.data.rationale;

    const evidenceTerms = Array.isArray(ai?.evidenceTerms)
      ? ai.evidenceTerms.map((v) => String(v).trim()).filter(Boolean).slice(0, 8)
      : fallbackAnalysis.data.evidenceTerms;

    const patterns = Array.isArray(ai?.patterns)
      ? ai.patterns.map((v) => String(v).trim()).filter(Boolean).slice(0, 8)
      : fallbackAnalysis.data.patterns;

    const rationale = ensureStructuredRationaleText(
      rawRationale,
      finalRisk,
      detectedFindings,
      evidenceTerms,
      latestCheckIn
    );

    return res.json({
      data: {
        replyText:
          typeof ai?.replyText === 'string' && ai.replyText.trim()
            ? ai.replyText.trim()
            : fallbackWellbeingReply(message, finalRisk),
        detectedRisk: finalRisk,
        alerts: aiAlerts,
        source: 'backend-wellbeing-ai',
        interpretation,
        detectedFindings,
        rationale,
        evidenceTerms,
        patterns,
        analysisMode
      }
    });
  } catch (error) {
    return res.status(500).json({
      error: 'Fallo interno en wellbeing-chat',
      detail: error instanceof Error ? error.message : String(error)
    });
  }
});

app.post('/ai/wellbeing-reflection', async (req, res) => {
  try {
    const reflection = String(req.body?.reflection || '').trim();
    const currentRisk = normalizeRisk(req.body?.currentRisk);
    const latestCheckIn = req.body?.latestCheckIn && typeof req.body.latestCheckIn === 'object'
      ? req.body.latestCheckIn
      : null;
    const recentReflections = Array.isArray(req.body?.recentReflections)
      ? req.body.recentReflections.slice(-8).map((r) => ({
          text: String(r?.text || '').slice(0, 600),
          patterns: Array.isArray(r?.patterns) ? r.patterns.slice(0, 8).map((p) => String(p)) : [],
          risk: normalizeRisk(r?.risk)
        }))
      : [];
    const sensorContext = req.body?.sensorContext && typeof req.body.sensorContext === 'object'
      ? req.body.sensorContext
      : null;

    if (!reflection) {
      return res.status(400).json({ error: 'reflection es requerido' });
    }

    const fallbackData = analyzeReflectionFallback({ reflection, currentRisk, latestCheckIn });

    if (!GEMINI_API_KEY && !OPENAI_API_KEY) {
      return res.json({
        ...fallbackData,
        data: {
          ...fallbackData.data,
          source: 'fallback-no-key'
        }
      });
    }

    const recentBlock = recentReflections.length
      ? recentReflections.map((r) => `- ${r.text} [riesgo ${r.risk}; patrones: ${r.patterns.join(', ') || 'ninguno'}]`).join('\n')
      : 'Sin reflexiones previas.';

    const checkInBlock = latestCheckIn
      ? `Ultimo check-in: WHO-5=${Number(latestCheckIn?.who5Percent || 0)}/100, PHQ-2=${Number(latestCheckIn?.phq2Score || 0)}/6, GAD-2=${Number(latestCheckIn?.gad2Score || 0)}/6. Resumen: ${String(latestCheckIn?.summary || '')}`
      : 'No hay check-in reciente.';

    const sensorBlock = sensorContext
      ? `Sensores del dia: sueno=${Number(sensorContext?.sleepHours ?? 0)}h, pantalla=${Number(sensorContext?.screenMinutes ?? 0)}min, pasos=${Number(sensorContext?.steps ?? 0)}, FC reposo=${Number(sensorContext?.restingHeartRate ?? 0)} bpm.`
      : 'Sin senales de sensores disponibles.';

    const prompt = `Eres un analista de bienestar escolar. Responde solo JSON valido con estas llaves: {"interpretation":"...","detectedFindings":["..."],"rationale":"...","evidenceTerms":["..."],"patterns":["..."],"detectedRisk":"low|medium|high","alerts":[{"title":"...","detail":"..."}]}. Tu respuesta debe ser natural, detallada y clara para un profesional. Explica que detectaste y por que. No diagnostiques. Debes evaluar el significado global del comentario y no depender solo de palabras exactas. Interpreta lenguaje coloquial, rodeos, desesperanza, intencion de dano, perdida de futuro, carga percibida, aislamiento, despedida y senales indirectas de riesgo.
Conocimiento clinico:
- ${CLINICAL_KB.join('\n- ')}
  Riesgo preliminar: ${currentRisk}. Usalo solo como contexto, no como respuesta final; puedes subirlo o bajarlo si el significado global del mensaje lo justifica.
${checkInBlock}
${sensorBlock}
Reflexiones recientes:
${recentBlock}
Comentario actual: ${reflection}`;

    let text;
    try {
      const generated = await generateAiText(prompt);
      text = generated.text;
    } catch (e) {
      return res.json(fallbackData);
    }

    const ai = parseProviderJson(text);
    if (!ai || typeof ai !== 'object') {
      return res.json(fallbackData);
    }

    const hasAiRisk = typeof ai?.detectedRisk === 'string' && ai.detectedRisk.trim().length > 0;
    const aiRisk = normalizeRisk(ai?.detectedRisk || fallbackData.data.detectedRisk);
    const detectedRisk = resolveAiFirstRisk({
      aiRisk,
      fallbackRisk: fallbackData.data.detectedRisk,
      baselineRisk: currentRisk,
      hasAiRisk
    });
    const evidenceTerms = Array.isArray(ai?.evidenceTerms) && ai.evidenceTerms.length
      ? ai.evidenceTerms.map((e) => String(e).trim()).filter(Boolean)
      : fallbackData.data.evidenceTerms;
    const detectedFindings = Array.isArray(ai?.detectedFindings) && ai.detectedFindings.length
      ? ai.detectedFindings.map((e) => String(e).trim()).filter(Boolean)
      : fallbackData.data.detectedFindings;
    const patterns = Array.isArray(ai?.patterns) && ai.patterns.length
      ? ai.patterns.map((e) => String(e).trim()).filter(Boolean)
      : fallbackData.data.patterns;
    const alerts = Array.isArray(ai?.alerts)
      ? ai.alerts.slice(0, 2).map((a) => ({
          title: String(a?.title || 'Alerta preventiva').slice(0, 120),
          detail: String(a?.detail || 'Sugerido seguimiento clinico.').slice(0, 300)
        }))
      : fallbackData.data.alerts;

    const interpretation = typeof ai?.interpretation === 'string' && ai.interpretation.trim()
      ? ai.interpretation.trim()
      : fallbackData.data.interpretation;
    const rawRationale = typeof ai?.rationale === 'string' && ai.rationale.trim()
      ? ai.rationale.trim()
      : fallbackData.data.rationale;
    const rationale = ensureStructuredRationaleText(
      rawRationale,
      detectedRisk,
      detectedFindings,
      evidenceTerms,
      latestCheckIn
    );

    return res.json({
      data: {
        interpretation,
        detectedFindings,
        rationale,
        evidenceTerms,
        patterns,
        detectedRisk,
        alerts,
        source: 'backend-wellbeing-reflection'
      }
    });
  } catch (error) {
    return res.status(500).json({
      error: 'Fallo interno en wellbeing-reflection',
      detail: error instanceof Error ? error.message : String(error)
    });
  }
});

app.listen(PORT, () => {
  console.log(`AI backend listo en http://localhost:${PORT}`);
});
