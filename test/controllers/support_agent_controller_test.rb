require "test_helper"

class SupportAgentControllerTest < ActionDispatch::IntegrationTest
  test "GET the ticket form" do
    get support_agent_url
    assert_response :success
    assert_select "form"
    assert_select "select[data-preset-target=select]"
  end

  test "POST runs the agent and renders the verdict" do
    fake = {
      ticket_id: "WEB-1", decision: "escalate", confidence: 0.0, category: "triaje",
      kb_refs: [], draft_response: "Hemos derivado tu solicitud.",
      escalation_reason: "sin cuerpo", escalation_summary: "n/a",
      audit: { model: "m", api_calls: 0, iterations: 0, steps: [],
               tokens: { input: 0, output: 0 }, cost_usd: 0.0, latency_ms: 0,
               injection_suspected: false, guardrail_triggered: nil, kb_unavailable: false }
    }

    original = SupportAgent::Agent.method(:new)
    stub = Object.new
    stub.define_singleton_method(:run) { |_ticket| fake }
    SupportAgent::Agent.singleton_class.send(:define_method, :new) { |*_a, **_k| stub }

    begin
      post run_support_agent_url, params: { subject: "x", body: "" }
    ensure
      SupportAgent::Agent.singleton_class.send(:define_method, :new, original)
    end

    assert_response :success
    assert_select ".verdict--escalate"
    assert_select ".verdict-badge", text: "ESCALAR"
  end
end
