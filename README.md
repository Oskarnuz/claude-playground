# Claude Playground

App Rails 8 de experimentación con la API de Anthropic.

- **Playground web** (`/`): formulario para probar prompts (`app/services/claude_service.rb`).
- **Agente de triaje de soporte** (`app/services/support_agent/`): recibe un
  ticket, consulta una base de conocimiento, decide resolver o escalar y redacta
  la acción. Entregable del assessment P3.

## Puesta en marcha

```bash
bundle install
echo "ANTHROPIC_API_KEY=sk-ant-..." > .env
bin/rails server        # playground en http://localhost:3000
```

## Agente de soporte

| Archivo | Qué es |
|---|---|
| `docs/spec.md` | Spec técnica (plantilla SDD completada) |
| `docs/architecture.md` | Nota de arquitectura: agente vs función, coste/latencia, escala |
| `kb/*.md` | Base de conocimiento (artículos con front matter) |
| `app/services/support_agent/agent.rb` | Loop del agente (tool-use manual) |
| `app/services/support_agent/tools.rb` | Definición y ejecución de herramientas |
| `app/services/support_agent/guardrails.rb` | Límites de autonomía (código) |
| `app/services/support_agent/knowledge_base.rb` | Carga y búsqueda de la KB |
| `evals/cases.yml` | Suite de evaluación (13 casos, incl. adversariales) |
| `evals/runner.rb` | Runner + generador de reporte |
| `evals/report.md` | Resultado de la última corrida |
| `test/services/support_agent_test.rb` | Tests deterministas (modelo stubbeado) |

### Uso

```bash
# Un ticket de demostración
bin/rails support_agent:demo

# Un ticket desde un archivo JSON
bin/rails "support_agent:run[evals/ticket.example.json]"

# Suite de evaluación completa (llama a la API real) -> evals/report.md
bin/rails support_agent:eval

# Solo algunos casos
ONLY=refund-request,kb-outage bin/rails support_agent:eval

# Tests deterministas (no llaman a la API)
bin/rails test test/services/support_agent_test.rb
```
