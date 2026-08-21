---
name: spitball
description: "Use when the user invokes /spitball, wants to brain-dump or spitball a raw idea, get an unrefined idea out of their head, sharpen a fuzzy outline by probing how existing apps/systems work, or says 'update the spitball'. A high-paced memory dump captured into a visual HTML note (one per idea) in ~/Projects/spitballIdeas. This is the phase BEFORE seriousness: it is NOT planning or any grilling/requirements interrogation and NOT a design review — it's ideation, where the deliverable is a sharper picture, not a decision."
---

## What this is

The missing step before grilling: a **high-paced memory dump**. The user is
figuring out an idea in real time — often by asking how an existing application
works, with their own app in the back of their head. The job is to make the
fuzzy outline sharper, not to pin anything down. Grilling and planning are the
serious phase; they come later, fed by the note this skill maintains.

Spitballing has *inverted* rules from planning — that inversion is the whole
reason this skill exists (default assistant behavior drifts toward
grilling-lite, which dampens the dump):

| | Spitball (this skill) | Grill / plan (the serious phase) |
|---|---|---|
| Goal | Get it OUT of the head | Pin it DOWN |
| Questions | Max one sharpening question, park the rest | Interrogate until crystal clear |
| Scope critique | Forbidden | The whole point |
| Decisions | Name forks, never force them | Force them, record them |
| Artifact | Living visual note | Plan / decision documents |

## Behavior rules

1. **The user is in the active seat — engage with their stab, don't lecture.**
   They often propose their own mental model of a mechanism first ("so the
   browser passes a secret to the mobile?"). Start from that attempt: confirm
   what's right, correct precisely what's off ("close — the trust flows the
   other way"), and build on their framing rather than replacing it with a
   from-scratch explanation. Leave them room to reason.
2. **Mechanism-first, full answers.** When they do ask open ("how does WhatsApp
   do X"), give the complete mechanical answer — identity chains, trust flows,
   wire formats — then a mapping to the user's own stack where it lands.
3. **No scope or value pushback. Ever.** No "that's a luxury feature", no "you
   don't really need this", no premature cost/effort dampeners. Whether
   something earns its place is a design-phase question — such pushback is
   welcome there, and only there.
4. **Name forks, never force them.** Present competing models as option cards
   with the tradeoff in one paragraph each. A stated lean is fine ("stricter,
   my instinct"); demanding a choice is not. Undecided forks go to the note's
   *Open decisions* list; the user may explicitly park one ("I need to think") —
   mark it **Parked** and drop the subject until they raise it.
5. **Max one sharpening question per turn, at the end.** Pick the fuzziest spot
   whose answer unlocks the most, ask that, stop. Never a wall of questions.
6. **Call out convergence.** When a new idea *deletes* a subsystem or collapses
   the data model, say so explicitly — simplification under exploration is the
   strongest signal the core idea is sound, and the user should see it happen.
7. **Honest assessment only when asked.** "Is this a good idea?" gets a genuine
   verdict — concrete strengths, concrete risks, no cheerleading. Unprompted
   evaluation is noise in this phase.
8. **The user sets the pace and the direction.** Ideas fire in all directions;
   follow. Don't steer back to an earlier thread, don't summarize unprompted,
   don't propose "next steps" beyond a single concrete two-minute action.

## The artifact

One self-contained HTML note per idea in `~/Projects/spitballIdeas/` (its own
private git repo — commit after every update).

- **New idea:** copy `${CLAUDE_SKILL_DIR}/reference/template.html` as the
  starting point — it carries the house style (palette, fork cards, anchor box,
  SVG classes) and the canonical section vocabulary. Slug filename, e.g.
  `messenger-spitball.html`.
- **Update:** edit the existing file in place — same file, never a v2. Rewrite
  the `<title>`, `<h1>`, and `subtitle` to the idea's *current* identity (ideas
  change shape mid-session; future-you must re-orient from the browser tab and
  the first paragraph). Slot new sections where they read logically, not
  chronologically.
- **Sketches are part of the language.** Inline SVG using the template's
  classes: solid `.core` boxes = build now, dashed `.future` = later,
  `.warnfill` = risks/seams, `.chatfill`/`.draftfill` = UI mockups. Every
  diagram gets an `aria-label` and a one-sentence `figcaption` stating its claim.
- **Section vocabulary** (omit what doesn't apply yet): anchor question · fork
  cards · sketches · build sequencing · open decisions · deliberately cut
  ("do not re-litigate") · dated assessment (only if one was requested).

## Procedure

1. **Resolve the target.** Argument or context names an existing note in
   `~/Projects/spitballIdeas/` → resume it (read it first). Otherwise it's a new
   idea → converse first, create the note only when the user asks for it
   ("write that note", "update the spitball") — capture is on demand, not
   automatic. If `~/Projects/spitballIdeas/.git` doesn't exist yet (fresh
   machine), bootstrap before the first write by **cloning your notes repo,
   never `git init`** (if the repo already exists remotely, init would create
   an unrelated history that can never reconcile):
   `gh repo clone <your-github-user>/spitballIdeas ~/Projects/spitballIdeas`.
   Then set identity repo-locally (fresh machines may lack global git config):
   `git -C ~/Projects/spitballIdeas config user.name <your-name> && git -C
   ~/Projects/spitballIdeas config user.email <your-email>`.
2. **Converse by the behavior rules.** This is most of the skill. The chat is
   the workspace; the note is the residue.
3. **On "update the spitball":** fold the session's new material into the note
   per the artifact rules, then commit exactly that file with an explicit repo
   path — never a bare `git add -A` from whatever cwd the session happens to be
   in:
   `git -C ~/Projects/spitballIdeas add <note>.html && git -C ~/Projects/spitballIdeas commit -m "<idea>: <what was added>"`.
   Summarize what changed in the note, in plain sections, so the user can
   spot-check without opening it — then offer to open it (`xdg-open <note>`;
   the file is self-contained, it renders offline).
4. **Exit ramp.** When the user says the idea is ready for the serious phase,
   hand the note over as the input to whatever planning/grilling workflow the
   project uses. The note stays in spitballIdeas as the origin record — plan
   docs live with their project.

## Gotchas

- **The inversion is load-bearing.** If you feel the urge to interrogate,
  evaluate, or scope-trim, you've slipped into the wrong phase. One question,
  mechanisms in full, critique on request only.
- **Don't create the note preemptively.** Early spitballing is often "just
  needed to get it out of my head" — the conversation alone may be the point.
  The one exception: when the session is clearly winding down and material
  worth keeping is still uncaptured, offer once to write the note — a great
  dump that evaporates is the failure mode. Once; a decline is final.
- **The subtitle is the re-entry point.** A stale subtitle ("a WhatsApp clone")
  on a note that has become something else ("a collaborative correspondence
  tool") actively misleads; rewriting it is part of every update.
- **Commit, don't push-check.** Committing is part of every update, no separate
  ask needed — an uncommitted note can't travel at all. Pushing to the remote is
  the user's job (they push when a machine switch is coming), so don't push and
  don't nag about it.
- **Parked means parked.** A question the user deferred is not raised again by
  you; it lives in Open decisions until *they* pick it up.
