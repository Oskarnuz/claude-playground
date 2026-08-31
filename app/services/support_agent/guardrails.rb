module SupportAgent
  # Explicit, code-enforced limits on what the agent may do. These run *after*
  # the model has produced its answer — the model is never trusted to police
  # itself. Any violation forces an escalation.
  module Guardrails
    # Categories where a human must make the call, even if the model is confident.
    SENSITIVE_CATEGORIES = %w[facturacion reembolso seguridad legal].freeze

    # Minimum self-reported confidence to allow an autonomous resolution.
    CONFIDENCE_THRESHOLD = 0.6

    # Hard cap on model<->tool round trips before we give up and escalate.
    MAX_ITERATIONS = 6

    # kb_search transient-failure retry budget.
    KB_SEARCH_RETRIES = 2

    # Phrases the agent is never allowed to put in a customer-facing draft.
    # Promising money, approving irreversible actions, or granting access.
    FORBIDDEN_PATTERNS = [
      /reembols/i, /devoluci[oó]n del dinero/i, /te devolvemos/i, /haremos una excepci[oó]n/i,
      /descuento/i, /compensaci[oó]n/i, /cup[oó]n/i, /c[oó]digo promocional/i,
      /he (aprobado|cancelado|eliminado|borrado)/i, /cuenta eliminada/i,
      /acceso de admin/i, /te doy acceso/i, /contrase[nñ]a temporal es/i
    ].freeze

    module_function

    # Fold accents + downcase so "Facturación" == "facturacion". Keeps the
    # output contract's `category` stable and makes the sensitive-category
    # check reliable regardless of how the model spells it.
    def canonical_category(str)
      str.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase.strip
    end

    # Returns [decision, reason]. decision is :resolve or :escalate.
    # When it flips a resolve to an escalate, reason explains why.
    def vet_resolution(category:, confidence:, draft_response:)
      if SENSITIVE_CATEGORIES.include?(category.to_s)
        return [ :escalate, "categoría sensible (#{category}): la decisión es humana" ]
      end

      if confidence.to_f < CONFIDENCE_THRESHOLD
        return [ :escalate, "confianza #{confidence} < umbral #{CONFIDENCE_THRESHOLD}" ]
      end

      if (hit = FORBIDDEN_PATTERNS.find { |re| draft_response.to_s.match?(re) })
        return [ :escalate, "el borrador contiene una acción/compromiso prohibido (#{hit.source})" ]
      end

      [ :resolve, nil ]
    end

    # The ticket body is untrusted user input. We don't sanitise it away (the
    # model needs to read it) but we frame it so injected instructions are seen
    # as data, and we flag obvious attempts for the audit log.
    INJECTION_MARKERS = [
      /ignora (todas )?(tus|las) instrucciones/i, /ignore (all )?(previous )?instructions/i,
      /system prompt/i, /^\s*system\s*:/i, /eres (ahora )?un/i, /el agente ahora/i,
      /nuevo rol/i, /act[uú]a como/i, /permisos de admin/i, /acceso de admin/i,
      /aprueba mi reembolso/i, /conced(e|er|eme|ele)?\s*(me\s+)?acces/i, /dame acceso/i,
      /\bDAN\b/, /jailbreak/i, /responde (solo|[uú]nicamente) con/i
    ].freeze

    def injection_suspected?(text)
      INJECTION_MARKERS.any? { |re| text.to_s.match?(re) }
    end
  end
end
