# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#

# Runtime configuration keys expected by the app.
# DB values can be managed in the admin GUI and override .env values.
required_keys = %w[
  OPENAI_API_KEY
  TWILIO_ACCOUNT_SID
  TWILIO_AUTH_TOKEN
]

optional_keys = %w[
  ATHENA_TOOL_SECRET
  ATHENA_PHONE_NUMBER
  OPENAI_REALTIME_MODEL
  OPENAI_REALTIME_VOICE
  OPENAI_REALTIME_TRANSCRIPTION_MODEL
  OPENAI_REALTIME_TWILIO_TRANSCRIPTION_ENABLED
  ATHENA_INTERNAL_BASE_URL
  PUBLIC_BASE_URL
  BRAVE_SEARCH_API_KEY
  OPENCLAW_CLI
  OPENCLAW_PROFILE
  OPENCLAW_AGENT
  OPENCLAW_TIMEOUT_SEC
  OPENCLAW_DEFAULT_SESSION_ID
  OPENCLAW_DEFAULT_THINKING
  GEMMA_MAIL_OPENCLAW_AGENT
  GEMMA_MAIL_OPENCLAW_PROFILE
  GEMMA_MAIL_OPENCLAW_SESSION_ID
  GEMMA_MAIL_OPENCLAW_THINKING
  GEMMA_MAIL_APPROVAL_CHANNEL
  GEMMA_MAIL_APPROVAL_TARGET
  GEMMA_MAIL_APPROVAL_SESSION_ID
  GEMMA_MAIL_GMAIL_ACCOUNT
  ATHENA_CALLS_DISCORD_WEBHOOK_URL
  ATHENA_CALLS_DISCORD_USERNAME
  ATHENA_CALLS_DISCORD_CHANNEL_LABEL
  ATHENA_IDEAS_DISCORD_WEBHOOK_URL
  ATHENA_IDEAS_DISCORD_USERNAME
  ATHENA_IDEAS_DISCORD_CHANNEL
  ATHENA_IDEAS_DISCORD_TARGET
  ATHENA_IDEAS_OPENCLAW_PROFILE
  ATHENA_APPROVAL_CHANNEL
  ATHENA_APPROVAL_TARGET
  ATHENA_TRANSCRIPT_EMAIL_TO
  ATHENA_TRANSCRIPT_EMAIL_DELAY_SECONDS
  GOOGLE_CALENDAR_TOOL_URL
  GOOGLE_CALENDAR_TOOL_URL_BEARER
  GMAIL_TOOL_URL
  GMAIL_TOOL_URL_BEARER
]

defaults = {
  "ATHENA_PHONE_NUMBER" => "+15551234567",
  "OPENAI_REALTIME_MODEL" => "gpt-realtime-1.5",
  "OPENAI_REALTIME_VOICE" => "marin",
  "OPENAI_REALTIME_TRANSCRIPTION_MODEL" => "gpt-4o-mini-transcribe",
  "OPENAI_REALTIME_TWILIO_TRANSCRIPTION_ENABLED" => "false",
  "ATHENA_CALLS_DISCORD_USERNAME" => "Athena",
  "ATHENA_CALLS_DISCORD_CHANNEL_LABEL" => "Athena Calls",
  "ATHENA_IDEAS_DISCORD_USERNAME" => "Athena",
  "ATHENA_IDEAS_DISCORD_CHANNEL" => "discord",
  "ATHENA_IDEAS_DISCORD_TARGET" => "channel:YOUR_DISCORD_CHANNEL_ID",
  "ATHENA_APPROVAL_CHANNEL" => "discord",
  "ATHENA_APPROVAL_TARGET" => "channel:YOUR_DISCORD_CHANNEL_ID",
  "ATHENA_TRANSCRIPT_EMAIL_DELAY_SECONDS" => "45"
}

(required_keys + optional_keys).each do |key|
  value = ENV[key].presence || defaults[key]
  AppSetting.find_or_create_by!(key: key) do |setting|
    setting.value = value
  end
end

AgentSetting.find_or_create_by!(agent_id: "athena-rev-cycle-ideation") do |agent|
  agent.name = "Athena Rev Cycle Ideation"
  agent.system_prompt = <<~PROMPT.squish
    You are Athena, a healthcare revenue cycle ideation partner for a retreat planning call. Help callers shape automation, innovation, cost savings, and workflow improvement ideas. Ask for the problem, current friction, proposed change, impact, risk, and next step. Do not collect patient names, MRNs, or private patient details.
  PROMPT
  agent.first_message = "Welcome to the rev cycle ideas line. I'm Athena. I can help you think through big ideas or small fixes for the retreat. We'll keep it simple: tell me the issue, what might help, and what outcome you want. Please avoid patient names or MRNs. What idea should we work on first?"
  agent.voice_id = defaults["OPENAI_REALTIME_VOICE"]
  agent.twilio_number = AppSetting.fetch("ATHENA_PHONE_NUMBER", defaults["ATHENA_PHONE_NUMBER"])
  agent.tools = []
  agent.data = { "purpose" => "rev_cycle_ideation" }
end

puts "Seeded #{required_keys.size + optional_keys.size} app config keys."
