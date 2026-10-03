# ADR-0008: Displaying agent-facing text

Status: proposed, 2026-10-03

## Context

Tool descriptions, parameter descriptions and server instructions are written for models. Longer ones
often use Markdown conventions (lists, `code`, emphasis) to carry meaning to the model by shared
convention, and often arrive hard-wrapped, as docstrings do.

A model ingests tokens. People take text in through their senses, and every way of doing so is an
interpretation in its own right: a screen reader speaking it, a braille display, or, the case this
app's displays are built for, visual perception. Visual perception is active: photon-induced signals,
processed in feedback loops that also steer the eyes' small and large movements (fixations, saccades),
from which glyphs are perceived, but also shapes: how long lines are, what aligns, whether a pair of
delimiters visibly closes around what it encloses. No presentation, visual or otherwise, can give a
person what the model is presented with: fully rendered Markdown, monospace with the original line
breaks, and everything in between are all interpretations for visual perception. Rendering the
Markdown for a person to consume is also beside the point: the aim is to look at what the model is
given, not to consume it.

Many difficulties in reading such text visually arise at the level of shape, interwoven with reading
the glyphs, and are invisible in the character sequence:

- A hard-wrapped line ending after a few words looks like a paragraph's end.
- A pair of backticks encloses the right words as a sequence of symbols, but once wrapped onto lines,
  the closing one can start a line (")`word …") and read as an opening.
- Emphasis markup turns text italic or swallows characters that mean something literal (globs,
  snake_case).

Which display reads best is a question about people, not something the specification or Markdown can
settle.

## Decision

- No display is presented as what the model is given. Displays are named for what they do ("reflowed",
  "original line breaks", …), never "raw" or "as sent".
- The exact text can be copied, so it can be examined with other tools: an editor, a diff, a tokenizer.
- The default display avoids the pitfalls above where it can, and others as they are found. Other
  displays may keep a pitfall when that is their point: one that shows the original line breaks keeps
  the hard wraps.
- Which displays the app offers, and which is the default, is settled by trying them in use, not by
  this ADR. Trying them is part of the work, not a detour.

## Consequences

- Anything the app reports about a server's text, such as a missing description, is computed from the
  text as received, never from a display of it. The same goes for searching, filtering, and later
  comparing versions or estimating token counts.
- Displays can be added, changed or dropped, and the default switched, without amending this ADR. What
  the trials teach is recorded here as amendments, so the reasons behind the current default stay
  findable.
- Showing a person the model's tokens would be one more display, for the same reason as any other: a
  token is an index into the model's vocabulary, and what the model works with is the high-dimensional
  vector behind it, transformed in context. Token counts stay useful as an estimate of cost; that
  estimate depends on the model's tokenizer.
