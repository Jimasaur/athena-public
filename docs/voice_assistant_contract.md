# Athena Voice Assistant Contract

This document defines the lightweight tool contract for using Athena as a revenue cycle ideation voice assistant.

## Goal

Keep Athena simple and safe:

- Athena handles routing, storage, and execution
- the assistant handles reasoning, ideation, summarization, and drafting
- risky actions stay behind explicit human approval

## Core Flow

**User -> Athena -> assistant -> Athena -> user**

Athena should send compact, structured prompts to the assistant and expect compact, structured replies.

## First Commands

### 1. `capture_idea`
Capture a revenue cycle automation, innovation, cost savings, or workflow improvement idea.

Use when the caller shares:
- a retreat idea
- a repeated manual workflow
- a denial or cost savings opportunity
- a process improvement that needs review

Expected assistant output:
- confirm the idea was captured
- keep the spoken reply brief
- avoid patient names, MRNs, or private patient details

### 2. `status`
Return a short system summary.

Use when the user asks:
- what is running
- whether the system is healthy
- whether a call, webhook, or tool is available

Expected assistant output:
- 1-3 bullets
- no speculation
- include only known facts

### 3. `summarize_last_call`
Summarize the most recent call or conversation.

Use when the user asks:
- what just happened
- summarize the call
- what did that person say

Expected assistant output:
- short summary
- notable points
- any follow-up needed
- keep names and sensitive details minimal unless needed

### 4. `find_contact`
Look up a contact or recent conversation by phone number, name, or identifier.

Use when the user asks:
- who was that
- find the contact
- pull up the number

Expected assistant output:
- matching contact or conversation
- confidence level if ambiguous
- ask for clarification if multiple matches

### 5. `draft_follow_up`
Draft a follow-up message, note, or call summary.

Use when the user asks:
- draft a text
- draft an email
- write a follow-up note

Expected assistant output:
- concise draft
- optional subject line
- one suggested next step

### 6. `web_search`
Search the web for current information.

Use when the user asks:
- what changed
- find current info
- look this up

Expected assistant output:
- concise answer
- source-aware summary
- no fabricated certainty

## Prompt Format

Athena should send the assistant a structured request like this:

```json
{
  "command": "capture_idea",
  "user_request": "Capture this rev cycle improvement idea.",
  "context": {
    "conversation_id": "11",
    "call_sid": "CA_EXAMPLE",
    "caller": "+14155552001",
    "called_number": "+15551234567"
  },
  "constraints": {
    "tone": "direct",
    "length": "short",
    "safety": "do_not_execute_external_actions"
  }
}
```

### Prompt rules

- keep it short
- include only relevant context
- state the command clearly
- do not include unnecessary raw logs
- do not include secrets
- do not ask the assistant to take external actions unless the command explicitly allows it

## Suggested Response Format

Athena should expect something like:

```json
{
  "summary": "User tested the call flow and asked about tool access.",
  "highlights": [
    "Call connected successfully",
    "Assistant described available tools",
    "Conversation ended cleanly"
  ],
  "follow_up": [
    "No immediate follow-up needed"
  ]
}
```

## Safety Rules

- Read-only commands are allowed first
- Drafts are allowed next
- Any outbound action needs approval
- Edits to records should be explicit and logged
- Do not let the assistant silently act on behalf of the user

## Next Step

Wire these commands into Athena one at a time, starting with:

1. `capture_idea`
2. `status`
3. `summarize_last_call`

Then add `find_contact`, `draft_follow_up`, and `web_search` once the basic loop is stable.
