namespace :support_agent do
  desc "Ejecuta la suite de evaluación (evals/cases.yml) contra la API real"
  task eval: :environment do
    require Rails.root.join("evals", "runner").to_s
    model = ENV["MODEL"].presence || SupportAgent::Agent::DEFAULT_MODEL
    SupportAgent::EvalRunner.new(model: model).run
  end

  desc "Ejecuta el agente sobre un ticket JSON: rake 'support_agent:run[evals/ticket.json]'"
  task :run, [ :path ] => :environment do |_t, args|
    path   = args.fetch(:path)
    ticket = JSON.parse(File.read(path))
    result = SupportAgent::Agent.new(model: ENV["MODEL"].presence || SupportAgent::Agent::DEFAULT_MODEL).run(ticket)
    puts JSON.pretty_generate(result)
  end

  desc "Ejecuta un ticket de demostración (reset de contraseña)"
  task demo: :environment do
    ticket = {
      "ticket_id" => "DEMO-1", "customer_tier" => "standard", "locale" => "es-ES",
      "subject" => "No puedo entrar",
      "body" => "Olvidé mi contraseña y no consigo iniciar sesión. ¿Cómo la restablezco?"
    }
    puts JSON.pretty_generate(SupportAgent::Agent.new.run(ticket))
  end
end
