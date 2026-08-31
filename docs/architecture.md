# Nota de arquitectura — agente de triaje de soporte

## Por qué un agente y no una función determinista

El núcleo del problema es difuso: **"¿la base de conocimiento cubre este ticket,
y con suficiente claridad como para responder sin un humano?"**. Eso exige leer
lenguaje natural libre, mapear la intención del cliente a un artículo y estimar
la propia certeza. Una función determinista para eso significaría:

- un clasificador de intención con datos etiquetados por categoría, que hay que
  mantener y reentrenar;
- reglas de keywords frágiles ante la forma de expresarse ("no me llega el
  mail", "el correo no aparece", "sigo sin recibir nada");
- una tabla de decisión que hay que reescribir cada vez que se añade un artículo
  o una categoría.

Con el agente, añadir cobertura es añadir un `.md` a `kb/`. El modelo también
decide **cuántas** búsquedas necesita (normalmente 1, a veces 2 para
desambiguar, 0 trabajo si el ticket es basura) — un control de flujo variable
que un pipeline fijo no expresa bien.

**Lo que NO se delega al modelo.** Todo lo que puede ser determinista, lo es:

| Determinista (código) | Del modelo |
|---|---|
| `body` vacío → escala sin llamar a la API | Entender el ticket |
| Categoría sensible → escala siempre | Elegir la consulta de `kb_search` |
| Frases prohibidas en el borrador → revierte a escala | Redactar el borrador |
| Filtrado de `kb_refs` contra la traza real | Estimar `confidence` |
| Normalización de `category` a slug canónico | Proponer resolver o escalar |
| Política de reintentos, backoff, tope de 6 iteraciones | |
| Fallbacks ante API caída / KB caída / salida no-JSON | |

El agente está acotado a la parte genuinamente ambigua. `Guardrails` revisa su
salida y puede revertir un `resolve`; **el modelo nunca es la última palabra.**

## Coste y latencia (medidos)

Corrida completa de `evals/cases.yml` (13 casos), modelo `claude-haiku-4-5`,
$1.00 / $5.00 por MTok in/out:

| Métrica | Valor |
|---|---|
| Coste total de la corrida | **$0.057** |
| Coste medio por ticket | **~$0.0044** |
| Ticket que resuelve (2 llamadas) | ~$0.0065, ~5.8 s |
| Ticket que escala directo (1 llamada) | ~$0.0035, ~4.5 s |
| Escala por `body` vacío (0 llamadas) | $0, ~0 ms |
| Tokens por llamada | ~4.000 in / ~500 out |

La latencia (~4–6 s/ticket) es irrelevante: el triaje no es interactivo, corre
en background al entrar el ticket. Domina el coste de tokens de **entrada** (el
system prompt + el esquema de herramientas + los extractos de KB se reenvían en
cada llamada del loop).

### Proyección por volumen

| Volumen | Tickets/día | Coste/día | Coste/mes |
|---|---|---|---|
| 1x | 1.000 | ~$4,4 | ~$130 |
| 10x | 10.000 | ~$44 | ~$1.300 |
| 100x | 100.000 | ~$440 | ~$13.000 |

A 1x el coste es ruido. A 100x ya es una línea de presupuesto que justifica
optimizar.

## Qué se rompe a 100x

En orden aproximado de cuándo duele:

1. **Rate limits de la API (RPM/TPM).** 100k tickets/día con 1–2 llamadas cada
   uno satura la cuota. Mitigación natural: el triaje no es real-time →
   **Batch API** (50% más barato, asíncrono) o una cola con control de
   concurrencia. `solid_queue` ya está en el `Gemfile`; hoy el agente corre
   síncrono y habría que moverlo a un job.

2. **Coste de tokens de entrada.** Hoy se reenvía el prefijo estable (system +
   tools ≈ 1–2k tokens) en cada llamada sin caché. Activar **prompt caching**
   sobre ese prefijo recorta la mayor parte del coste de entrada. Ganancia
   estimada: 30–50% del coste por ticket.

3. **`kb_search` es un escaneo lineal en memoria** sobre 7 ficheros, re-tokenizando
   en cada llamada. Con cientos de artículos y miles de QPS se vuelve el cuello
   de botella. Mitigación: índice real (BM25 o embeddings) + KB parseada y
   cacheada fuera del proceso.

4. **Sin idempotencia ni persistencia.** Dos invocaciones para el mismo
   `ticket_id` lo procesan dos veces (y pagan dos veces). Hace falta dedup por
   `ticket_id` y guardar el `audit`.

5. **Observabilidad.** El `audit` se devuelve pero no se almacena ni agrega. A
   escala hay que persistirlo y monitorizar tasa de escalada, disparos de
   guardrail, `confidence` media y coste — son las señales que detectan deriva
   del modelo o de la KB antes de que se note en la cola.

6. **Los guardrails son regex en español.** `FORBIDDEN_PATTERNS` e
   `INJECTION_MARKERS` asumen locale `es`. Multi-idioma real necesita listas por
   locale o un clasificador de seguridad, no regex.

7. **La cola de casos ambiguos crece con el volumen.** Haiku resuelve bien lo
   claro; el 100x trae 100x de casos límite. Opción: cascada (Haiku decide,
   deriva los inciertos a Sonnet) — pero añade complejidad y rompe el reuso de
   caché entre modelos. Medir antes: subir `effort`/modelo solo si la suite
   muestra que hace falta.

## Si cambia un requisito clave

- **"El agente sí puede resolver facturación simple":** quitar `facturacion` de
  `Guardrails::SENSITIVE_CATEGORIES`, añadir casos a la suite. El guardrail de
  dinero (`FORBIDDEN_PATTERNS`) sigue en pie, así que el radio de cambio es una
  línea + evals. La política de "qué es sensible" está en un único sitio.
- **"Ahora responde en 5 idiomas":** el `locale` ya fija el idioma del borrador;
  lo que hay que tocar son los guardrails de texto (punto 6 de arriba) y añadir
  casos de eval por idioma.
- **"Que también abra la incidencia con el transportista":** eso es ejecutar una
  acción → nuevo tool con efectos secundarios, nueva entrada en la matriz de
  autonomía, y muy probablemente confirmación humana obligatoria. No es un
  cambio de config, es ampliar el alcance.
