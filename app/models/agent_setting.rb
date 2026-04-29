class AgentSetting < ApplicationRecord
  validates :agent_id, presence: true, uniqueness: true
end
