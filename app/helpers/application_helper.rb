module ApplicationHelper
  def format_phone(value)
    raw = value.to_s.strip
    return raw if raw.blank?

    digits = raw.gsub(/[^\d]/, "")
    if digits.length == 11 && digits.start_with?("1")
      local = digits[1..]
      return "+1 (#{local[0, 3]}) #{local[3, 3]}-#{local[6, 4]}"
    end
    if digits.length == 10
      return "(#{digits[0, 3]}) #{digits[3, 3]}-#{digits[6, 4]}"
    end

    raw
  end

  def tabler_icon(name, size: 20, class_name: nil, alt: nil)
    tag.i(
      "",
      class: [ "ti", "ti-#{name}", class_name ].compact.join(" "),
      style: "font-size: #{size}px;",
      title: alt || "#{name.to_s.tr('-', ' ')} icon",
      aria: { hidden: "true" }
    )
  end

  def app_setting_display_value(app_setting)
    return "Not set" if app_setting.value.blank?
    return "Stored secret" if app_setting.sensitive?

    app_setting.value
  end

  def app_setting_form_value(app_setting)
    app_setting.sensitive? ? "" : app_setting.value
  end

  def app_setting_value_field_type(app_setting)
    app_setting.sensitive? ? "password" : "text"
  end

  def app_setting_value_placeholder(app_setting)
    return "Stored; enter replacement" if app_setting.sensitive? && app_setting.value.present?

    "Not set"
  end
end
