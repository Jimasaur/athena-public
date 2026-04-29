class DemoScenarioCatalog
  ITEMS = [
    {
      slug: "rev-cycle-ideation-session",
      provider: "openai_realtime",
      agent_name: "Athena Ideation",
      caller: {
        name: "Dana Miller",
        greeting_name: "Dana",
        phone: "+14155552001",
        portrait: "Revenue cycle manager preparing ideas for the retreat."
      },
      demo_goal: "Show Athena turning a rough retreat idea into a structured idea card.",
      operator_takeaway: "A spoken idea becomes a reviewable problem, solution, impact, and next step.",
      sidecar_source: "athena_idea_capture",
      action_status: ActionDraft::PENDING_APPROVAL_STATUS,
      intent: { "label" => "rev_cycle_ideation", "confidence" => 0.91 },
      risk: { "level" => "low", "reasons" => [ "no PHI shared", "review-only output" ] },
      next_best_question: "Who owns the workflow today, and what volume would make this worth piloting?",
      facts: [
        "Caller wants pre-retreat idea shaping.",
        "Idea needs owner and impact validation.",
        "Athena captured a workshop prompt."
      ],
      showcase: [ "Realtime ideation", "idea capture", "Discord report" ],
      summary: "Dana proposed a pre-retreat intake line that captures revenue cycle improvement ideas before the workshop.",
      draft_body: "Athena captured a rev cycle idea for retreat review. No external action has been taken.",
      transcript: [
        [ "assistant", "Hi, I'm Athena. I'm here to help you think about solutions ahead of the rev cycle retreat." ],
        [ "user", "I want a better way for managers to submit improvement ideas before the retreat." ],
        [ "assistant", "Great. What problem does that solve?" ],
        [ "user", "People mention ideas in hallway conversations, but they are not polished enough to compare." ],
        [ "assistant", "I captured that as a retreat intake and idea-polishing workflow." ]
      ]
    },
    {
      slug: "automation-opportunity-discovery",
      provider: "openai_realtime",
      agent_name: "Athena Automation Discovery",
      caller: {
        name: "Priya Shah",
        greeting_name: "Priya",
        phone: "+14155552002",
        portrait: "Revenue cycle analyst with a manual-work automation idea."
      },
      demo_goal: "Show Athena capturing an automation candidate with systems and workflow triggers.",
      operator_takeaway: "Automation ideas are captured with practical pilot constraints.",
      sidecar_source: "workflow_mapper",
      action_status: ActionDraft::PENDING_APPROVAL_STATUS,
      intent: { "label" => "automation_candidate", "confidence" => 0.88 },
      risk: { "level" => "medium", "reasons" => [ "requires system access review" ] },
      next_best_question: "Which system event should trigger the automation?",
      facts: [
        "Manual work happens daily.",
        "The team wants routing and status updates automated.",
        "System dependency needs validation."
      ],
      showcase: [ "workflow mapping", "system dependency", "pilot fit" ],
      summary: "Priya described a manual work queue that could be routed automatically when required fields are present.",
      draft_body: "Athena captured an automation candidate for retreat review.",
      transcript: [
        [ "assistant", "Tell me about a repeated manual step that might be worth automating." ],
        [ "user", "Every morning someone checks a queue and forwards clean accounts to the right team." ],
        [ "assistant", "What makes an account clean enough to route?" ],
        [ "user", "Eligibility is verified and the authorization field is complete." ],
        [ "assistant", "I captured the trigger, systems question, and pilot validation step." ]
      ]
    },
    {
      slug: "denials-cost-savings-lab",
      provider: "openai_realtime",
      agent_name: "Athena Savings Lab",
      caller: {
        name: "Marcus Lee",
        greeting_name: "Marcus",
        phone: "+14155552003",
        portrait: "Denials lead with a cost savings and revenue protection idea."
      },
      demo_goal: "Show Athena framing a denials idea as a measurable impact hypothesis.",
      operator_takeaway: "The retreat team gets category, root-cause guess, and validation step.",
      sidecar_source: "impact_hypothesis_builder",
      action_status: ActionDraft::PENDING_APPROVAL_STATUS,
      intent: { "label" => "denials_cost_savings", "confidence" => 0.86 },
      risk: { "level" => "medium", "reasons" => [ "financial estimate requires validation" ] },
      next_best_question: "What denial reason code or queue should be sampled first?",
      facts: [
        "Caller sees repeated denials.",
        "Potential impact is staff time and prevented rework.",
        "Needs sample validation."
      ],
      showcase: [ "impact hypothesis", "denial category", "validation prompt" ],
      summary: "Marcus proposed analyzing repeated authorization-related denials and flagging accounts before submission.",
      draft_body: "Athena captured a denial prevention and cost-savings idea for retreat review.",
      transcript: [
        [ "assistant", "What revenue cycle issue would you like to improve?" ],
        [ "user", "We keep reworking authorization denials that look preventable." ],
        [ "assistant", "What would change if we caught those earlier?" ],
        [ "user", "We could save staff time and prevent avoidable rebills." ],
        [ "assistant", "I captured this as a denial prevention idea with a validation sample." ]
      ]
    },
    {
      slug: "retreat-review-library",
      provider: "openai_realtime",
      agent_name: "Athena Review Library",
      caller: {
        name: "Nora Patel",
        greeting_name: "Nora",
        phone: "+14155552004",
        portrait: "Workshop facilitator testing retrieval and review readiness."
      },
      demo_goal: "Show that captured calls become a searchable retreat backlog.",
      operator_takeaway: "Ideas can be reviewed from the admin Ideas page with transcript evidence.",
      sidecar_source: "idea_indexer",
      action_status: ActionDraft::PENDING_APPROVAL_STATUS,
      intent: { "label" => "workshop_review", "confidence" => 0.83 },
      risk: { "level" => "low", "reasons" => [ "review-only library" ] },
      next_best_question: "Which scoring criteria should be added before the retreat?",
      facts: [
        "Facilitator needs organized ideas.",
        "Duplicates and themes will matter later.",
        "Transcript evidence should stay attached."
      ],
      showcase: [ "idea library", "transcript evidence", "retreat prompt" ],
      summary: "Nora tested how retreat facilitators can review idea cards and compare themes before the workshop.",
      draft_body: "Athena captured a review-library improvement for retreat preparation.",
      transcript: [
        [ "assistant", "What would help the retreat team review ideas faster?" ],
        [ "user", "We need the cards grouped by theme with the original call attached." ],
        [ "assistant", "Should duplicates be merged or shown separately?" ],
        [ "user", "Show duplicates for now, but flag likely repeats." ],
        [ "assistant", "I captured this as a review library and future clustering need." ]
      ]
    }
  ].freeze

  def self.all
    ITEMS.map { |item| hydrate(item) }
  end

  def self.find(slug)
    all.find { |item| item[:slug] == slug.to_s }
  end

  def self.fetch(slug)
    find(slug) || raise(KeyError, "Unknown demo scenario: #{slug}")
  end

  def self.hydrate(item)
    use_case = UseCaseCatalog.find(item[:slug]) || {}

    item.merge(
      use_case: use_case,
      title: use_case[:title] || item[:slug].to_s.humanize,
      short_title: use_case[:short_title] || use_case[:title] || item[:slug].to_s.humanize,
      space: use_case[:space],
      transport: use_case[:transport],
      icon: use_case[:icon],
      accent: use_case[:accent],
      primary_actions: use_case[:primary_actions] || []
    )
  end
end
