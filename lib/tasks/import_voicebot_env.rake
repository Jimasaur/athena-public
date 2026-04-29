namespace :athena do
  desc "Import shared Twilio/public URL settings from an OpenAI realtime voicebot env file"
  task :import_voicebot_env, [ :env_file ] => :environment do |_task, args|
    env_file = args[:env_file].presence || ENV["VOICEBOT_ENV_FILE"].presence || "/home/jimasaur/jim_dev/openai-realtime-engine/.env.voice-bot"

    unless File.exist?(env_file)
      abort "Env file not found: #{env_file}"
    end

    mappings = {
      "VOICE_BOT_PUBLIC_BASE_URL" => "PUBLIC_BASE_URL",
      "VOICE_BOT_TWILIO_ACCOUNT_SID" => "TWILIO_ACCOUNT_SID",
      "VOICE_BOT_TWILIO_AUTH_TOKEN" => "TWILIO_AUTH_TOKEN",
      "VOICE_BOT_TWILIO_FROM_NUMBER" => "VOICEBOT_TWILIO_FROM_NUMBER"
    }

    values = {}
    File.readlines(env_file, chomp: true).each do |line|
      next if line.strip.empty? || line.lstrip.start_with?("#")
      next unless line.include?("=")

      key, raw_value = line.split("=", 2)
      values[key.strip] = raw_value.to_s.strip
    end

    imported = []
    missing = []

    mappings.each do |source_key, target_key|
      value = values[source_key].to_s
      if value.blank?
        missing << source_key
        next
      end

      setting = AppSetting.find_or_initialize_by(key: target_key)
      setting.value = value
      setting.save!
      imported << "#{source_key} -> #{target_key}"
    end

    puts "Imported #{imported.size} settings from #{env_file}"
    imported.each { |entry| puts "  #{entry}" }

    return if missing.empty?

    puts "Skipped #{missing.size} empty settings:"
    missing.each { |key| puts "  #{key}" }
  end
end
