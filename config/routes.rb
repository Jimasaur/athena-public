Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  post "webhooks/twilio/inbound" => "twilio_register#inbound", as: :twilio_inbound
  post "webhooks/twilio/outbound" => "twilio_register#outbound", as: :twilio_outbound
  post "webhooks/twilio/status" => "twilio_register#status", as: :twilio_status_webhook
  post "webhooks/twilio/transcription" => "twilio_register#transcription", as: :twilio_transcription_webhook
  mount TwilioMediaStream.new => "/webhooks/twilio/stream"
  match "voice/inbound" => "twilio_register#inbound", via: [ :get, :post ]
  match "voice/outbound" => "twilio_register#outbound", via: [ :get, :post ]
  post "voice/outbound/status" => "twilio_register#status"
  mount TwilioMediaStream.new => "/ws/twilio-media"
  post "agent_tools/lookup" => "agent_tools#lookup", as: :agent_tools_lookup
  post "agent_tools/update" => "agent_tools#update", as: :agent_tools_update
  post "agent_tools/web_search" => "agent_tools#web_search", as: :agent_tools_web_search
  post "agent_tools/openclaw_chat" => "agent_tools#openclaw_chat", as: :agent_tools_openclaw_chat
  post "agent_tools/status" => "agent_tools#status", as: :agent_tools_status
  post "agent_tools/command" => "agent_tools#command", as: :agent_tools_command
  post "agent_tools/summarize_last_call" => "agent_tools#summarize_last_call", as: :agent_tools_summarize_last_call
  post "agent_tools/find_contact" => "agent_tools#find_contact", as: :agent_tools_find_contact
  post "agent_tools/capture_idea" => "agent_tools#capture_idea", as: :agent_tools_capture_idea
  post "agent_tools/draft_follow_up" => "agent_tools#draft_follow_up", as: :agent_tools_draft_follow_up
  post "agent_tools/athena_calls_latest" => "agent_tools#athena_calls_latest", as: :agent_tools_athena_calls_latest
  post "agent_tools/athena_call_summary" => "agent_tools#athena_call_summary", as: :agent_tools_athena_call_summary
  post "agent_tools/calendar_availability" => "agent_tools#calendar_availability", as: :agent_tools_calendar_availability
  post "agent_tools/gmail_send" => "agent_tools#gmail_send", as: :agent_tools_gmail_send

  get "use-cases" => "use_cases#index", as: :use_cases
  get "use-cases/:slug" => "use_cases#show", as: :use_case

  # Defines the root path route ("/")
  namespace :admin do
    root "dashboard#show"
    resources :action_drafts, only: [] do
      member do
        post :approve
        post :reject
        post :execute
      end
    end
    resources :demo_scenarios, only: [ :index ] do
      member do
        post :launch
      end
      collection do
        post :seed_all
      end
    end
    resources :conversations, only: [ :index, :show, :destroy ]
    resources :idea_captures, only: [ :index, :show ]
    resources :customers, only: [ :index, :show, :new, :create, :edit, :update, :destroy ]
    resources :outbound_calls, only: [ :create ]
    resources :app_settings, except: [ :show ] do
      patch :realtime, on: :collection
    end
    resources :agent_settings do
      member do
        post :sync_from
        post :push_to
      end
      collection do
        post :sync_all
      end
    end
  end

  root "home#index"
end
