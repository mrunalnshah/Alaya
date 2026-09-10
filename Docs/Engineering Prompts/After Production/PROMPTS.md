# Prompts for changing Alaya

Copy-paste ready. Every prompt assumes you have `ARCH_M_MAINTENANCE.md` and the bundles it names.

**The pattern is always two steps.** Route first with ARCH_M alone, then build with the bundles. Skipping the
routing step is how you end up uploading 80,000 lines for a two-line change — or, worse, uploading too little and
getting code written against an invented API.

---

## 0 · When you do not know what you need

Send `ARCH_M_MAINTENANCE.md` **and nothing else**.

```
I want to: <one or two sentences>

You have Alaya's maintenance architecture. Do not write code yet.

1. Which routing-table row (§3) matches, and what should I upload?
2. What will this touch that I have not mentioned?
3. Which of §6's rules does it come near?
4. Does it need more than one session? If so, what is the split?

Ask about anything ambiguous. Do not guess at an API you cannot see —
if you need a signature, name the bundle that has it.
```

Use this whenever the change is more than a wording tweak. It costs one cheap round and routinely changes what
you upload.

---

## 1 · Fix a bug

**Upload:** `F_<feature>` · `B6_SHARED` — plus `B3_DOMAIN` if a number is wrong rather than a pixel.

```
Bug: <what you see>
Expected: <what should happen>
Where: <screen or flow>
Steps: <how to reproduce>

Find the cause before proposing a fix. If the bundles I gave you do not
contain it, say which bundle would and stop.

Then:
- Explain the cause in two or three sentences.
- Give me complete changed files, nothing unchanged.
- Say whether a test would have caught this, and if not, why not.
```

**That last line earns its place.** Three bugs in this project reached the user through green test runs — every
one because the tests exercised a widget while the wiring around it was absent.

---

## 2 · Change or enhance the UI

**Upload:** `F_<feature>` · `B6_SHARED` · `ARB` if any words change.

```
Change: <what should look or behave differently>
Screen: <which one>

Constraints — these are binding, not preferences:
- Start from the screen's existing ARCH_5 §3 archetype. Do not invent a new one.
- No string literal, raw colour, spacing, radius, duration, icon size or text style.
- Money through AmountText, Qty through QtyText, DateKey through DateText.
- All four states stay implemented: loading, empty, error, populated.
- Every list stays virtualised.
- Must render at 320×640 with textScaler 2.0 without overflowing.

Give me complete changed files and an ARB patch if strings changed.
If what I asked conflicts with a constraint, stop and tell me rather than
working around it.
```

---

## 3 · Add a feature to something that already exists

A new screen, a new field, a new action inside a module that is already there.

**Upload:** `F_<feature>` · `B5_APP` · `B6_SHARED` · `ARB` — plus `B3_DOMAIN` if it needs new logic.

```
Add: <what the user will be able to do>
Where it belongs: <feature>

Before writing anything, tell me:
- Which ARCH_5 §3 archetype the new surface uses.
- Whether it needs a route, and if so what navigates to it.
- Whether it needs a new provider, and in which file.

Then write it. Complete files only, ARB as a patch.
Every new route needs a widget that navigates to it — a route nothing
reaches is a feature nobody can use.
```

**The route line is not boilerplate.** Four screens in Phase 8B were built, routed, tested and unreachable.

---

## 4 · Add a whole new module

Your recipe example. This is the only change that needs most of the codebase, and it should be split.

**Session 1 — data and logic.** Upload `ARCH_1` · `ARCH_2` · `ARCH_M` · `B1_CORE` · `B2_SCHEMA` · `B3_DOMAIN`.

```
New module: <name>
What it does: <two or three sentences>
Connects to: <existing modules, and how>

This session is data and domain only. No UI.

Give me:
- The drift tables, with every column ARCH_2 §2 requires.
- The migration, following ARCH_2 §13.
- The entities and the repository contract.
- Any engine, pure, in domain.

Before you write: tell me what you are about to add to the schema and why,
and I will confirm. A migration is forward-only and cannot be undone on a
device that has already run it.
```

**Session 2 — the data layer.** Upload `ARCH_M` · the new `B2` and `B3` files · `B4_DATA`.

```
Here is what session 1 produced. Now the DAO and the repository
implementation, following the pattern of the nearest existing one.
```

**Session 3 — the screens.** Upload `ARCH_5` · `ARCH_M` · new `B3` files · `B5_APP` · `B6_SHARED` · `F_<nearest>`.

```
Now the screens. F_<nearest> is the pattern to copy.

Each screen: declare its ARCH_5 §3 archetype in the doc comment, implement
all four states, and be reachable from something a user can find.
Wire the routes in B5_APP and add a drawer destination if it deserves one.
```

**Session 4 — strings and tests.** Upload `ARCH_M` · the new feature files · `ARB` · `B7_TESTKIT`.

```
Now the ARB keys as a patch, and widget tests using the existing harnesses.
Four states per screen, plus a 320×640 textScaler-2.0 test.
```

**Build between every session.** A schema error found in session 1 costs one round; found in session 4 it
invalidates everything after it.

---

## 5 · Change the database

**Upload:** `B2_SCHEMA` · `B3_DOMAIN` · `F_<feature>` · `ARB` — and **`ARCH_2_DATABASE.md`**, always.

```
Schema change: <add a column / add a table / change a type>
Why: <what the user gains>

Stop and answer these before writing a migration:
1. What breaks for someone already running the app with data?
2. Is the new column nullable, or does it need a default for existing rows?
3. Does anything need backfilling, and from what?
4. What does the rollback look like if this ships broken?

Then the migration, following ARCH_2 §13, plus every entity, DAO and
repository the change touches.
```

**Question 4 is the one people skip.** A migration runs once per device and cannot be re-run; there is no undo in
the field.

---

## 6 · Change a calculation

**Upload:** `B3_DOMAIN` · `B1_CORE`.

```
Calculation: <which number>
Currently: <what it does>
Should: <what it should do>

Engines are pure — no Flutter, no drift, no data/. Keep it that way.

Give me the changed engine and a unit test that fails on the old behaviour
and passes on the new one.
```

Money is integer minor units throughout. Any change touching money should say what it does about rounding.

---

## 7 · Change wording

**Upload:** `ARB` only.

```
Change these strings: <list them, or describe the tone change>

Return a JSON patch of only the changed and added keys. Not the whole file.

Keep placeholders and plural forms intact — a translator needs the shape,
not just the words.
```

If the change touches the **backup warning**, stop: ARCH_3 §3.4 fixes that text verbatim and it must appear on
every export, every time.

---

## 8 · Fix a build error

The fastest loop in this whole workflow. **Upload nothing new** — the model already has the bundles.

```
<paste the analyzer output verbatim, all of it>

Fix these. For each:
- Say what the real cause was, not just the line.
- If it is an API that differs from what you assumed, say so plainly —
  I would rather know the surface was guessed than have it quietly patched.

Complete files only.
```

**Paste every error, not the first one.** They usually share a cause, and a model seeing all eight fixes them in
one round instead of eight.

---

## 9 · Fix a failing test

**Upload:** `B7_TESTKIT` · `F_<feature>`.

```
<paste the test output>

Before fixing: is the test wrong, or is the code wrong? Say which and why.

Watch for these — all three have happened here:
- A Stream.value fake resolves in the first frame, so a loading-state
  assertion passes for the wrong reason.
- A lazy list does not build rows below the fold, so findsNothing passes
  for the wrong reason.
- Extending a contract obliges every implementer, including test fakes.
```

---

## 10 · Performance

**Upload:** `F_<feature>` · `B6_SHARED` — plus `B2_SCHEMA` if a query is the suspect.

```
Slow: <what, and how slow>
Measured with: <how you know>

Find the cause before proposing a fix. If you need a measurement I have
not given you, tell me how to get it rather than guessing.

Alaya's rules: every list virtualised, no work in build(), queries watched
not polled.
```

**Give it a measurement.** Without one, any answer is a guess with confident phrasing.

---

## 11 · Add a package

**Upload:** `ARCH_1_FOUNDATION.md` · the bundle that will import it.

```
I want to add: <package, and what for>

Before anything:
1. Is it already in ARCH_1 §7's table? If not, it needs a row and a reason.
2. Does §7.4 or §7.3 forbid or complicate it?
3. Can this be done without a package? Say honestly.

If it goes ahead, give me the `flutter pub add` line and nothing else —
never a version constraint, never `any`.
```

**`file_picker` is permanently banned.** It resolves to a 2020 version whose `jcenter()` call fails at
`assembleDebug` while `pub get`, the analyzer and `flutter test` all pass. Use the SAF channel in `B4_DATA`.

---

## What not to say

| Instead of | Say |
|---|---|
| "Here's my whole app, fix X" | Route first. More context makes answers vaguer, not sharper |
| "Give me the updated file" for the ARB | "Return a JSON patch of changed keys only" |
| "Make the UI better" | Name the screen and what specifically should differ |
| "Add recipes" | Split it. §4 has the four sessions |
| "It doesn't work" | Paste the error, the steps, and what you expected |
| "Just make it compile" | Ask what the real cause was. A silenced error comes back |

---

## Two lines worth putting in every prompt

```
Do not guess at an API you cannot see. If you need a signature,
name the bundle that has it and I will upload it.
```

Every wrong-API failure in this project — `local_auth` twice, the ads SDK three times, the notification plugin
four times — came from writing against a remembered signature rather than a visible one.

```
If what I asked conflicts with a rule in ARCH_M §6, stop and tell me
rather than working around it.
```

The rules exist because each was paid for once. A model that quietly routes around one has spent that money
again.
