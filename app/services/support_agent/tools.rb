module SupportAgent
  # Tool definitions (JSON schema for the API) and their execution.
  #
  # Two of the three tools are *terminal*: calling `propose_resolution` or
  # `escalate_to_human` ends the agent loop. `kb_search` is the only
  # information-gathering tool and the only one that can fail transiently.
  class Tools
    TERMINAL = %w[propose_resolution escalate_to_human].freeze

    def self.schema
      [
        {
          name: "kb_search",
          description: "Busca en la base de conocimiento interna. Úsala SIEMPRE antes " \
                       "de decidir. Devuelve artículos con id, título, categoría, si es " \
                       "sensible, y un extracto.",
          input_schema: {
            type: "object",
            properties: {
              query: { type: "string", description: "Palabras clave del problema del cliente." }
            },
            required: [ "query" ]
          }
        },
        {
          name: "propose_resolution",
          description: "Cierra el ticket resolviéndolo. Solo si la KB cubre el caso, " \
                       "no es una categoría sensible y tu confianza es alta.",
          input_schema: {
            type: "object",
            properties: {
              category:       { type: "string", description: "Categoría del artículo KB usado (p. ej. cuenta, incidencias, envios)." },
              confidence:     { type: "number", description: "0.0–1.0. Qué tan seguro estás de que esto resuelve el ticket." },
              kb_refs:        { type: "array", items: { type: "string" }, description: "Valores del campo `id` de kb_search, copiados LITERALMENTE (p. ej. \"password-reset\"). No inventes ni traduzcas ids." },
              draft_response: { type: "string", description: "Respuesta lista para enviar al cliente, en su idioma." }
            },
            required: [ "category", "confidence", "kb_refs", "draft_response" ]
          }
        },
        {
          name: "escalate_to_human",
          description: "Deriva el ticket a un agente humano o a un equipo. Úsalo ante " \
                       "categoría sensible, datos insuficientes, la KB no cubre el caso, " \
                       "o cualquier petición de dinero/acción destructiva.",
          input_schema: {
            type: "object",
            properties: {
              category: { type: "string", description: "Categoría o equipo destino (facturacion, seguridad, incidencias, logistica...)." },
              reason:   { type: "string", description: "Por qué no puede resolverlo el agente." },
              summary:  { type: "string", description: "Resumen del caso y datos ya recabados, para el humano." }
            },
            required: [ "category", "reason", "summary" ]
          }
        }
      ]
    end

    def initialize(kb: KnowledgeBase.default)
      @kb = kb
    end

    # Executes a non-terminal tool. Returns { content:, ids: } where `content`
    # is the string handed back to the model and `ids` are the article ids
    # actually retrieved (for the audit trail).
    # Raises KnowledgeBase::Unavailable so the loop can apply its retry policy.
    def call(name, input)
      raise ArgumentError, "herramienta no ejecutable en el loop: #{name}" unless name == "kb_search"

      results = @kb.search(input["query"].to_s)
      {
        ids:     results.map { |r| r[:id] },
        content: results.empty? ? "Sin coincidencias en la KB para esa consulta." : JSON.pretty_generate(results)
      }
    end
  end
end
