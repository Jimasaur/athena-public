class UseCaseCatalog
  ITEMS = [
    {
      slug: "rev-cycle-ideation-session",
      space: "Healthcare Revenue Cycle",
      transport: "Twilio + OpenAI Realtime API",
      icon: "bulb",
      title: "Rev Cycle Ideation Session",
      short_title: "Ideation Session",
      headline: "A phone-based thought partner for polishing retreat-ready revenue cycle ideas.",
      summary: "Call Athena before the retreat, talk through a rough idea, and leave behind a structured idea card for review.",
      audience: "Revenue cycle leaders, analysts, managers, and frontline staff with ideas that need shaping before workshop discussion.",
      promise: "A messy spoken thought becomes a clear problem, solution, impact hypothesis, and next step.",
      state_focus: "Idea capture and refinement",
      maturity: "Primary demo path",
      primary_actions: [ "Brainstorm", "Clarify problem", "Extract impact", "Capture next step" ],
      workflow: [ "Caller dials Athena", "Athena guides ideation", "Idea card is saved", "Discord report is posted", "Workshop team reviews" ],
      sidecars: [ "idea_capture", "impact_classifier", "retreat_reporter", "safety_gate" ],
      outcomes: [ "Idea card", "Transcript evidence", "Discord report", "Retreat discussion prompt" ],
      mvp: [ "Inbound call", "Realtime ideation prompt", "IdeaCapture record", "Discord report", "Admin idea library" ],
      risks: [ "Caller may share PHI", "Ideas may be vague", "Impact estimates need human review" ],
      accent: "emerald"
    },
    {
      slug: "automation-opportunity-discovery",
      space: "Automation",
      transport: "Twilio + OpenAI Realtime API",
      icon: "robot",
      title: "Automation Opportunity Discovery",
      short_title: "Automation Discovery",
      headline: "A guided intake line for repetitive work, handoff gaps, and automation candidates.",
      summary: "Athena helps callers describe manual work, repeated exceptions, routing delays, and AI/RPA opportunities.",
      audience: "Operational teams looking for realistic automation pilots in patient access, billing, coding, denials, and follow-up.",
      promise: "Potential automations are captured with workflow area, trigger, data needs, risk, and first pilot step.",
      state_focus: "Workflow and data requirements",
      maturity: "Workshop-ready prototype",
      primary_actions: [ "Map manual steps", "Identify trigger", "List systems", "Score pilot fit" ],
      workflow: [ "Caller describes friction", "Athena asks workflow questions", "Systems and handoffs are captured", "Pilot candidate is posted" ],
      sidecars: [ "workflow_mapper", "system_dependency_extractor", "pilot_fit_scorer", "retreat_reporter" ],
      outcomes: [ "Automation candidate", "Required systems list", "Risk notes", "Pilot fit score" ],
      mvp: [ "Capture manual workflow", "Detect automation trigger", "Store systems involved", "Report to Discord" ],
      risks: [ "Over-promising automation", "Missing integration constraints", "Privacy review required" ],
      accent: "sky"
    },
    {
      slug: "denials-cost-savings-lab",
      space: "Denials and Cost Savings",
      transport: "Twilio + OpenAI Realtime API",
      icon: "receipt-refund",
      title: "Denials and Cost Savings Lab",
      short_title: "Savings Lab",
      headline: "A capture line for denial prevention, underpayment, leakage, and staff-time savings ideas.",
      summary: "Athena turns cost-saving and revenue-protection ideas into clear hypotheses for retreat prioritization.",
      audience: "Denials, billing, coding, authorization, and revenue integrity teams with improvement ideas.",
      promise: "The retreat team gets a sharper view of financial impact, process owner, and next validation step.",
      state_focus: "Impact and prioritization",
      maturity: "Discovery path",
      primary_actions: [ "Name leakage source", "Estimate impact", "Find owner", "Define validation step" ],
      workflow: [ "Caller shares issue", "Athena clarifies loss or cost driver", "Impact is framed", "Idea is queued for scoring" ],
      sidecars: [ "impact_hypothesis_builder", "category_classifier", "owner_mapper", "retreat_reporter" ],
      outcomes: [ "Savings hypothesis", "Denial category", "Process owner", "Validation question" ],
      mvp: [ "Capture problem", "Classify category", "Draft impact hypothesis", "Store for workshop" ],
      risks: [ "Financial estimates need validation", "Root cause may be uncertain", "Requires operational owner" ],
      accent: "amber"
    },
    {
      slug: "retreat-review-library",
      space: "Workshop Review",
      transport: "Twilio + OpenAI Realtime API",
      icon: "folders",
      title: "Retreat Review Library",
      short_title: "Review Library",
      headline: "A searchable library of pre-retreat ideas, evidence, and discussion prompts.",
      summary: "Captured calls become structured cards the workshop team can sort, compare, and retrieve during the retreat.",
      audience: "Workshop facilitators, IT Directors, finance leaders, and revenue cycle sponsors.",
      promise: "The retreat starts with organized, reviewable ideas instead of scattered notes and hallway conversations.",
      state_focus: "Retrieval and workshop readiness",
      maturity: "Next build target",
      primary_actions: [ "Review ideas", "Compare categories", "Open transcripts", "Select pilots" ],
      workflow: [ "Ideas are captured", "Cards are categorized", "Facilitator reviews", "Retreat team selects pilots" ],
      sidecars: [ "idea_indexer", "duplicate_detector", "theme_clusterer", "pilot_prioritizer" ],
      outcomes: [ "Idea backlog", "Theme clusters", "Pilot shortlist", "Decision trail" ],
      mvp: [ "Admin idea index", "Idea detail page", "Category filters", "Transcript evidence" ],
      risks: [ "Needs search and tagging", "Duplicates may pile up", "Governance needed before execution" ],
      accent: "violet"
    }
  ].freeze

  def self.all
    ITEMS.map { |item| hydrate(item) }
  end

  def self.find(slug)
    all.find { |item| item[:slug] == slug.to_s }
  end

  def self.hydrate(item)
    item.merge(user_stories: user_stories_for(item))
  end

  def self.user_stories_for(item)
    title = item[:short_title]
    [
      story("Typical", "Revenue cycle manager", "Rough Idea Capture", "As a revenue cycle manager, I want to call Athena with a rough #{title.downcase} thought so it becomes a usable retreat card.", "Needs conversation-linked idea records and transcript evidence.", "The call should feel forgiving and conversational."),
      story("Typical", "Frontline staff member", "Small Friction Capture", "As a frontline staff member, I want to share a small daily annoyance without writing a formal proposal.", "Needs lightweight capture with no required jargon.", "Athena should validate small ideas as worth capturing."),
      story("Typical", "Analyst", "Impact Hypothesis", "As an analyst, I want Athena to ask about volume, time, dollars, or denial impact so the idea can be scored later.", "Needs structured impact fields and source transcript.", "Athena should ask one impact question at a time."),
      story("Typical", "IT Director", "Pilot Shape", "As an IT Director, I want each idea to include systems, data needs, and first pilot step.", "Needs fields for dependencies, owner, risk, and next step.", "The output should be practical enough for follow-up."),
      story("Typical", "Workshop facilitator", "Retreat Readiness", "As a facilitator, I want ideas grouped by theme before the retreat starts.", "Needs categories, tags, and sortable idea cards.", "Review should be fast during prep."),
      story("Edge", "Caller with PHI risk", "Privacy Guardrail", "As a caller, I need Athena to stop me from sharing patient identifiers.", "Needs prompt guardrails and future redaction checks.", "The reminder should be calm, not scary."),
      story("Edge", "Vague caller", "Clarify Ambiguity", "As a caller with a vague idea, I want Athena to help pull out the actual problem.", "Needs guided questions and fallback idea card defaults.", "Athena should ask clarifying questions without making the call feel like a form."),
      story("Edge", "Skeptical leader", "Evidence Trail", "As a skeptical leader, I want to see what was actually said before prioritizing an idea.", "Needs transcript evidence linked to every card.", "The detail page should make source context obvious."),
      story("Operator", "Discord reviewer", "Immediate Report", "As a Discord-first reviewer, I want every captured idea posted to the retreat channel.", "Needs webhook or OpenClaw channel delivery with retry-visible events.", "The report should include title, category, impact, and next step."),
      story("Operator", "Workshop owner", "Future Retrieval", "As the workshop owner, I want a DB-backed library that can later support search, clustering, and exports.", "Needs first-class idea tables rather than only transcript blobs.", "The system should feel like the beginning of a retreat backlog.")
    ]
  end

  def self.story(kind, actor, title, story, architecture, experience)
    {
      kind: kind,
      actor: actor,
      title: title,
      story: story,
      architecture: architecture,
      experience: experience
    }
  end
end
