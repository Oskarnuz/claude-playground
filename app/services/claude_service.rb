require "net/http"
require "json"
require "uri"

# Thin wrapper over the Anthropic Messages API (raw HTTP, no SDK gem — keeps the
# existing project style and avoids touching the bundle).
#
# - `.call`     : one-shot prompt used by the web playground (unchanged contract).
# - `.create`   : lower-level call that supports `tools` and returns the raw
#                 content blocks, token usage, cost and latency. Used by the
#                 support agent loop.
class ClaudeService
  API_URL         = URI("https://api.anthropic.com/v1/messages")
  DEFAULT_MODEL   = "claude-haiku-4-5-20251001"
  OPEN_TIMEOUT    = 10
  READ_TIMEOUT    = 60

  # USD per 1M tokens.
  PRICING = {
    "claude-haiku-4-5-20251001" => { input: 1.00,  output: 5.00  },
    "claude-sonnet-4-6"         => { input: 3.00,  output: 15.00 },
    "claude-opus-4-7"           => { input: 15.00, output: 75.00 }
  }.freeze

  Error = Class.new(StandardError)

  # --- Playground entry point (unchanged external behaviour) -----------------
  def self.call(system_prompt:, user_message:, model: DEFAULT_MODEL)
    result = create(
      system:   system_prompt,
      messages: [ { role: "user", content: user_message } ],
      model:    model
    )

    {
      text:          result[:text] || result[:error],
      input_tokens:  result[:input_tokens],
      output_tokens: result[:output_tokens],
      total_tokens:  result[:input_tokens] + result[:output_tokens],
      cost_usd:      result[:cost_usd]
    }
  end

  # --- Agent entry point ----------------------------------------------------
  # Returns a Hash:
  #   ok:            Boolean
  #   status:        HTTP status (Integer)
  #   stop_reason:   "end_turn" | "tool_use" | "max_tokens" | "refusal" | nil
  #   content:       Array of raw content blocks (text / tool_use)
  #   text:          concatenated text blocks (String)
  #   tool_uses:     Array of { id:, name:, input: } for tool_use blocks
  #   input_tokens:, output_tokens:, cost_usd:, latency_ms:
  #   error:         String when ok == false
  def self.create(messages:, system: nil, tools: nil, model: DEFAULT_MODEL, max_tokens: 1024)
    body = { model: model, max_tokens: max_tokens, messages: messages }
    body[:system] = system if system.is_a?(String) && !system.strip.empty?
    body[:tools]  = tools if tools && !tools.empty?

    started  = monotonic_ms
    response = post(body)
    latency  = monotonic_ms - started
    data     = JSON.parse(response.body)

    unless response.code.to_i == 200
      return failure("Error #{response.code}: #{data.dig('error', 'message') || response.body}",
                     status: response.code.to_i, latency_ms: latency)
    end

    usage         = data["usage"] || {}
    input_tokens  = usage["input_tokens"].to_i
    output_tokens = usage["output_tokens"].to_i
    blocks        = data["content"] || []

    {
      ok:            true,
      status:        200,
      stop_reason:   data["stop_reason"],
      content:       blocks,
      text:          blocks.select { |b| b["type"] == "text" }.map { |b| b["text"] }.join("\n").strip,
      tool_uses:     blocks.select { |b| b["type"] == "tool_use" }
                           .map { |b| { id: b["id"], name: b["name"], input: b["input"] || {} } },
      input_tokens:  input_tokens,
      output_tokens: output_tokens,
      cost_usd:      cost_for(model, input_tokens, output_tokens),
      latency_ms:    latency,
      error:         nil
    }
  rescue JSON::ParserError => e
    failure("Respuesta no-JSON de la API: #{e.message}", status: response&.code.to_i, latency_ms: 0)
  rescue => e
    failure("Error de red: #{e.message}", status: 0, latency_ms: 0)
  end

  def self.cost_for(model, input_tokens, output_tokens)
    prices = PRICING[model] || { input: 0, output: 0 }
    (input_tokens * prices[:input] + output_tokens * prices[:output]) / 1_000_000.0
  end

  # --- internals ----------------------------------------------------------
  def self.post(body)
    http             = Net::HTTP.new(API_URL.host, API_URL.port)
    http.use_ssl     = true
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    request = Net::HTTP::Post.new(API_URL.request_uri)
    request["x-api-key"]         = ENV["ANTHROPIC_API_KEY"]
    request["anthropic-version"] = "2023-06-01"
    request["content-type"]      = "application/json"
    request.body = body.to_json

    http.request(request)
  end
  private_class_method :post

  def self.failure(message, status:, latency_ms:)
    {
      ok: false, status: status, stop_reason: nil, content: [], text: nil, tool_uses: [],
      input_tokens: 0, output_tokens: 0, cost_usd: 0.0, latency_ms: latency_ms, error: message
    }
  end
  private_class_method :failure

  def self.monotonic_ms
    Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
  end
  private_class_method :monotonic_ms
end
