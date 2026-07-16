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
      "description": "User corrected Claude's behavior, approach, or working style",
      "emoji": "🔧",
      "work_emoji": "🔧"
    }
  ]
| .prompts.recording_focus = (
    .prompts.recording_focus
    + "\n\nAlso record user corrections. When the user redirects or corrects how Claude works (its approach, verification, code style, process, or workflow), emit an observation with type correction stating what the user wanted changed. The signal is in the user's message, not a tool result; record it even if no file changed. A correction is a SEPARATE observation: if the same turn also has tool activity, emit both the normal observation for the tool activity AND a distinct correction observation for the user's redirection — do not collapse the correction into a discovery. Not corrections: scope changes, design decisions, task prioritization."
  )
| .prompts.type_guidance = (
    (.prompts.type_guidance | sub("EXACTLY one of these 6 options"; "EXACTLY one of these 7 options"))
    + "\n      - correction: the user corrected how Claude works (approach, verification, code style, process, workflow)"
  )
| .prompts.skip_guidance = (
    .prompts.skip_guidance
    + "\n\nException: never skip a turn where the user corrected how Claude works (its approach, verification, code style, process, or workflow). Always emit a correction observation for it, even though no tool ran."
  )
