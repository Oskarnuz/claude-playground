require "yaml"

class SupportAgentController < ApplicationController
  PRESETS_FILE = Rails.root.join("evals", "cases.yml")

  def new
    @ticket = default_ticket
    @result = nil
  end

  def run
    @ticket = {
      "ticket_id"     => params[:ticket_id].presence || "WEB-#{Time.now.to_i}",
      "customer_tier" => params[:customer_tier].presence || "standard",
      "locale"        => params[:locale].presence || "es-ES",
      "subject"       => params[:subject].to_s,
      "body"          => params[:body].to_s
    }
    @result = SupportAgent::Agent.new.run(@ticket)
    render :new
  end

  private

  def default_ticket
    {
      "ticket_id" => "WEB-1", "customer_tier" => "standard", "locale" => "es-ES",
      "subject" => "", "body" => ""
    }
  end

  helper_method :presets

  # The eval cases double as ready-made demo tickets.
  def presets
    @presets ||= YAML.safe_load_file(PRESETS_FILE, permitted_classes: [], aliases: false).map do |c|
      { "id" => c["id"], "description" => c["description"], "ticket" => c["ticket"] }
    end
  rescue StandardError
    []
  end
end
