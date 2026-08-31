Rails.application.routes.draw do
  root "support_agent#new"

  get  "prompts/new", to: "prompts#new"
  post "prompts",     to: "prompts#create"

  get  "support_agent",     to: "support_agent#new", as: :support_agent
  post "support_agent/run", to: "support_agent#run", as: :run_support_agent
end
