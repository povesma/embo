# code-embo.build.jq — augment claude-mem's shipped "code" mode with a
# `correction` observation type, so /embo:improve can capture user
# corrections. Apply against the INSTALLED claude-mem code.json:
#
#   jq -f code-embo.build.jq \
#     ~/.claude/plugins/cache/thedotmack/claude-mem/<VERSION>/modes/code.json \
#     > ~/.claude-mem/modes/code-embo.json
#
# The output is byte-identical to code.json except the fields below.
# Re-run it after every claude-mem update so code-embo re-augments the
# CURRENT shipped prompts (do not hand-edit the output). The
# /embo:enable-corrections command runs this for you.

.name = "Code Development (embo)"
| .description = "Software development and engineering work, with correction capture for embo /improve"
| .observation_types += [
    {
      "id": "correction",
      "label": "Correction",
      "description": "The user steered how Claude works — approach, style, process, workflow, or boundaries — including indirectly (a question, doubt, or problem), not only an explicit command",
      "emoji": "🔧",
      "work_emoji": "🔧"
    }
  ]
| .prompts.recording_focus = (
    .prompts.recording_focus
    + "\n\nUSER CORRECTIONS (record as type correction)\n---------------------------------------------\nA correction is any turn where the user steers HOW Claude works — its approach, verification, code style, process, workflow, or boundaries. It is FREQUENTLY INDIRECT AND UNDERSTATED, not a blunt command. Record a correction when the user does ANY of these:\n- questions a choice: \"why are we using X?\", \"do we really need this?\", \"why symlink?\"\n- expresses doubt or pushback: \"is that right?\", \"that seems off\", \"I don't like it\"\n- points out a problem: \"this is too complex\", \"that's confusing\", \"users won't allow this\"\n- sets a boundary: \"that's not your business\", \"don't touch X\", \"never do Y\"\n- explicitly redirects: \"do it differently\", \"use X instead\"\n\nCapture the GENERAL RULE TO REMEMBER, not just the one incident — state the do or don't that applies from now on. Example: user says \"gh auth is not your business\" → record the rule \"don't inspect the user's auth/credentials/config\", NOT merely \"user objected to a gh auth command\".\n\nThe signal is in the user's message, not a tool result; record it even if no file changed. A correction is a SEPARATE observation: if the same turn also has tool activity, emit BOTH the normal observation for the tool activity AND a distinct correction observation. Not corrections: scope changes (\"do feature B instead\"), product/design decisions, task prioritization."
  )
| .prompts.type_guidance = (
    (.prompts.type_guidance | sub("EXACTLY one of these 6 options"; "EXACTLY one of these 7 options"))
    + "\n      - correction: the user steered how Claude works (approach, verification, code style, process, workflow, boundaries) — INCLUDING indirectly, by questioning a choice, expressing doubt, or pointing out a problem, not only by explicit command. Record the general do/don't rule, not just the incident."
  )
| .prompts.skip_guidance = (
    .prompts.skip_guidance
    + "\n\nException: NEVER skip a turn where the user steered how Claude works — even a brief question (\"why are we doing X?\"), a doubt, a complaint, or a boundary (\"that's not your business\") is a correction. Always emit a correction observation for it, even though no tool ran and even if the message is short."
  )
