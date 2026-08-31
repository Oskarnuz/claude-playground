class PromptsController < ApplicationController
  def new
    @system_prompt = ""
    @user_message  = ""
    @model         = "claude-haiku-4-5-20251001"
    @response      = nil
    @usage         = nil
  end

  def create
    @system_prompt = params[:system_prompt]
    @user_message  = params[:user_message]
    @model         = params[:model].presence || "claude-haiku-4-5-20251001"

    result    = ClaudeService.call(
      system_prompt: @system_prompt,
      user_message:  @user_message,
      model:         @model
    )

    @response = result[:text]
    @usage    = result
    render :new
  end
end
