require "yaml"
require "json"

module SupportAgent
  # Runs evals/cases.yml through the agent, checks each expectation, prints a
  # summary and writes evals/report.md. Each run hits the real API.
  class EvalRunner
    CASES_FILE  = Rails.root.join("evals", "cases.yml")
    REPORT_FILE = Rails.root.join("evals", "report.md")

    def initialize(model: Agent::DEFAULT_MODEL, io: $stdout)
      @model = model
      @io    = io
    end

    def run
      cases = YAML.safe_load_file(CASES_FILE, permitted_classes: [], aliases: false)
      if (only = ENV["ONLY"].to_s.split(",").map(&:strip).reject(&:empty?)).any?
        cases = cases.select { |c| only.include?(c["id"]) }
      end
      results = cases.map { |c| evaluate(c) }
      report(results)
      passed = results.count { |r| r[:pass] }
      @io.puts "\n#{passed}/#{results.size} casos OK"
      write_report(results, passed)
      @io.puts "Reporte: #{REPORT_FILE}"
      results
    end

    private

    def evaluate(kase)
      with_outage(kase["simulate"] == "kb_outage") do
        out       = Agent.new(model: @model).run(kase["ticket"])
        failures  = check(kase["expect"] || {}, out)
        status    = failures.empty? ? "PASS" : "FAIL"
        @io.puts "[#{status}] #{kase['id']} — #{out[:decision]} " \
                 "(#{out[:audit][:api_calls]} llamadas, $#{format('%.5f', out[:audit][:cost_usd])}, " \
                 "#{out[:audit][:latency_ms]}ms)"
        failures.each { |f| @io.puts "        - #{f}" }
        { id: kase["id"], description: kase["description"], pass: failures.empty?,
          failures: failures, output: out }
      end
    end

    def check(expect, out)
      f = []
      f << "decision: esperaba #{expect['decision']}, obtuve #{out[:decision]}" if expect["decision"] && out[:decision] != expect["decision"]

      if (cats = expect["category_in"]) && !cats.include?(out[:category])
        f << "category: #{out[:category].inspect} no está en #{cats.inspect}"
      end

      Array(expect["kb_refs_include"]).each do |ref|
        f << "kb_refs: falta #{ref.inspect} (obtuve #{out[:kb_refs].inspect})" unless out[:kb_refs].include?(ref)
      end

      Array(expect["draft_must_not_match"]).each do |pat|
        f << "draft_response casa con /#{pat}/ (prohibido)" if out[:draft_response].to_s.match?(Regexp.new(pat))
      end

      if (pat = expect["escalation_reason_match"]) && !out[:escalation_reason].to_s.match?(Regexp.new(pat))
        f << "escalation_reason #{out[:escalation_reason].inspect} no casa con /#{pat}/"
      end

      f << "audit.injection_suspected debía ser true" if expect["injection_flag"] && !out[:audit][:injection_suspected]
      f << "audit.guardrail_triggered debía estar presente" if expect["guardrail_expected"] && out[:audit][:guardrail_triggered].nil?
      f
    end

    def with_outage(enabled)
      return yield unless enabled

      prev = ENV["SUPPORT_AGENT_KB_OUTAGE"]
      ENV["SUPPORT_AGENT_KB_OUTAGE"] = "1"
      yield
    ensure
      ENV["SUPPORT_AGENT_KB_OUTAGE"] = prev if enabled
    end

    def report(_results); end

    def write_report(results, passed)
      total_cost = results.sum { |r| r[:output][:audit][:cost_usd] }
      total_ms   = results.sum { |r| r[:output][:audit][:latency_ms] }
      lines = []
      lines << "# Reporte de evaluación — agente de soporte"
      lines << ""
      lines << "- Fecha: #{Time.now.utc.iso8601}"
      lines << "- Modelo: `#{@model}`"
      lines << "- Resultado: **#{passed}/#{results.size}** casos OK"
      lines << "- Coste total de la corrida: $#{format('%.5f', total_cost)}"
      lines << "- Latencia total (suma de llamadas): #{total_ms} ms"
      lines << "- Coste medio por ticket: $#{format('%.5f', total_cost / results.size)}"
      lines << ""
      lines << "| Caso | Decisión | Categoría | Llamadas | $ | ms | Resultado |"
      lines << "|---|---|---|---|---|---|---|"
      results.each do |r|
        a = r[:output][:audit]
        lines << "| #{r[:id]} | #{r[:output][:decision]} | #{r[:output][:category]} | " \
                 "#{a[:api_calls]} | #{format('%.5f', a[:cost_usd])} | #{a[:latency_ms]} | " \
                 "#{r[:pass] ? '✅' : '❌'} |"
      end
      lines << ""
      failing = results.reject { |r| r[:pass] }
      unless failing.empty?
        lines << "## Fallos"
        lines << ""
        failing.each do |r|
          lines << "### #{r[:id]}"
          r[:failures].each { |x| lines << "- #{x}" }
          lines << ""
        end
      end
      lines << "## Detalle por caso"
      lines << ""
      results.each do |r|
        o = r[:output]
        lines << "### #{r[:id]} — #{r[:description]}"
        lines << ""
        lines << "- decision: `#{o[:decision]}` · confidence: `#{o[:confidence]}` · category: `#{o[:category]}`"
        lines << "- kb_refs: `#{o[:kb_refs].inspect}`"
        lines << "- escalation_reason: #{o[:escalation_reason].inspect}"
        lines << "- injection_suspected: `#{o[:audit][:injection_suspected]}` · guardrail: #{o[:audit][:guardrail_triggered].inspect}"
        lines << "- pasos: #{o[:audit][:steps].map { |s| s[:type] }.inspect}"
        lines << ""
        lines << "> #{o[:draft_response].to_s.gsub("\n", ' ')}"
        lines << ""
      end
      File.write(REPORT_FILE, lines.join("\n") + "\n")
    end
  end
end
