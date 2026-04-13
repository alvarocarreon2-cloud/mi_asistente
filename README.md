# mi_app

App Flutter con estimación inteligente de tareas y barra de navegación estilo liquid glass.

## IA sin exponer keys en cliente

La app **no necesita** `OPENAI_API_KEY` ni `GEMINI_API_KEY` en el móvil.
Ahora consume un backend local/servidor y, si no está disponible, usa fallback local en el cliente.

### 1) Levantar backend proxy

```bash
cd backend
npm install
cp .env.example .env
```

Edita `backend/.env` y coloca tu key:

```env
PORT=8787
GEMINI_API_KEY=AIza...
GEMINI_MODEL=gemini-1.5-flash
```

(También funciona con OpenAI si usas `OPENAI_API_KEY=sk-...`)

Inicia backend:

```bash
npm run dev
```

Health check:

```bash
curl http://localhost:8787/health
```

### 2) Ejecutar Flutter apuntando al backend

```bash
flutter run --dart-define=AI_BACKEND_URL=http://localhost:8787
```

### 2.1) Ejecutar con 1 click en VS Code

Ya está configurado:

- [./.vscode/tasks.json](.vscode/tasks.json): levanta backend (`npm run dev`).
- [./.vscode/launch.json](.vscode/launch.json): lanza Flutter con `AI_BACKEND_URL` y ejecuta el backend antes.

En VS Code abre **Run and Debug** y elige:

- `Flutter (AI Backend Local)`

### 3) Build de release

```bash
flutter build apk --release --dart-define=AI_BACKEND_URL=https://tu-backend.com
```

Para iOS:

```bash
flutter build ios --release --dart-define=AI_BACKEND_URL=https://tu-backend.com
```

## Seguridad recomendada

- Guarda la key solo en servidor (`backend/.env` o secrets del proveedor cloud).
- No subas `backend/.env` a git.
- Agrega autenticación y rate limit en el endpoint `/ai/analyze` antes de producción.
