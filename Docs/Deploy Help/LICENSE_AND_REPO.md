# Licensing, and the private repo

Two separate questions people conflate: **the licence on your code**, and **the licences on the code you
depend on**. You have obligations under the second whether or not you publish the first.

---

## Part 1 — Your licence: All Rights Reserved

You want it private and you may want to sell it. **Do not use MIT, Apache-2.0 or BSD.** Those grant
everyone permission to use, modify, sell and rebrand your work, and once granted for a released version
you cannot revoke it. If you ever license the app to a buyer, an earlier MIT release means they are paying
for something a competitor already has legally.

For a private, possibly-commercial project the correct answer is **no open-source licence at all** —
copyright is automatic, and absent a licence nobody has permission to do anything with it. Say so
explicitly so there is no ambiguity:

**`LICENSE`** — put this at the repo root:

```
Copyright (c) 2026 WildeWulf. All rights reserved.

This software and its source code are proprietary and confidential.

No permission is granted to use, copy, modify, merge, publish, distribute,
sublicense, or sell copies of this software, in whole or in part, by any
person or entity, except under a separate written agreement signed by the
copyright holder.

Unauthorised copying, distribution or use of this software, via any medium,
is strictly prohibited.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

Publishing a compiled app on Play does **not** put your source in the public domain, and does not oblige
you to release it. You keep everything.

### If you later change your mind

**Dual licensing is the move**, not relicensing: keep All Rights Reserved as the default and sell
commercial licences on top. Going from proprietary to open is easy; going back is impossible.

---

## Part 2 — The licences you already owe

Your dependencies are permissively licensed, which means **you may ship them commercially and closed —
but you must reproduce their notices.** Flutter is BSD-3-Clause; drift, riverpod, go_router and most of
the rest are MIT. Neither forces you to open your code. Both require attribution.

**Flutter gives you this almost free**, and you should wire it up:

```dart
// Somewhere in Settings › About
showLicensePage(
  context: context,
  applicationName: 'Alaya',
  applicationVersion: '1.0.0',
  applicationLegalese: '\u00A9 2026 WildeWulf',
);
```

`showLicensePage` collects every licence from every package in your build automatically. **One route and
you are compliant** — and if you skip it you are shipping other people's code without their notice, which
is the one licensing mistake that is actually actionable against you.

Add a **Settings › About › Open-source licences** row pointing at it. That is a real gap in the app today.

---

## Part 3 — The private repo

### Before the first commit

**Verify nothing secret is tracked.** Your `.gitignore` should already cover these; confirm rather than
assume:

```bash
cat >> .gitignore <<'EOF'

# Release signing — losing these is recoverable, leaking them is not
android/key.properties
*.jks
*.keystore

# Obfuscation symbols: not secret, but large and per-build
build/symbols/
EOF

git check-ignore -v android/key.properties *.jks 2>/dev/null || echo "NOT IGNORED — fix before committing"
git ls-files | grep -E '\.(jks|keystore)$|key\.properties' && echo "ALREADY TRACKED — see below" || echo "clean"
```

**If a keystore is already in history, removing the file is not enough** — it stays in every past commit.
Either rewrite history with `git filter-repo`, or, far simpler for a repo with no collaborators: delete the
repo, `rm -rf .git`, and start a fresh history. You lose the log, which is worth less than a leaked signing
key.

### What to commit that people usually don't

- **`drift_schemas/*.json`** — the schema snapshots. Without these, step-by-step migrations are impossible
  and ARCH_2 §13 calls that unrecoverable. They are the most important files in the repo after the source
- **`test/shared/golden/goldens/*.png`** — golden baselines are part of the test suite, not build output
- **`docs/`, `ARCH_*.md`, `PROMPTS.md`, `ARCH_M_MAINTENANCE.md`** — the architecture *is* the asset

### Where to host it

| Option | Private repos | Note |
|---|---|---|
| **GitHub Free** | Unlimited, unlimited collaborators | **Use this.** No reason to look further |
| GitLab Free | Unlimited | Fine. Better built-in CI if you ever want it |
| Codeberg | Unlimited | Non-profit, no CI to speak of |
| A local drive only | — | **Not a backup.** One drive failure and the project is gone |

```bash
gh repo create wildewulf/alaya --private --source=. --remote=origin
git add -A && git commit -m "Alaya v1"
git push -u origin main
git tag -a v1.0.0 -m "First release" && git push origin v1.0.0
```

**Tag every release you upload to Play.** When a crash report arrives from version 1.0.3 you need to be
able to check out exactly what 1.0.3 was.

### One thing worth more than the code

**Back up `key.properties` and the `.jks` file somewhere that is not the repo and not only your laptop** —
a password manager, an encrypted archive in cloud storage, a printed copy in a drawer.

If you accept Play App Signing (you should) a lost upload key is recoverable through Google support. If you
decline it, **a lost signing key means you can never update the app again** — not a new version, a new
listing, and every existing user stranded. It is the single most expensive mistake available to you.

---

## Part 4 — Keeping it private while showing it off

You want it private *for now*, and you also want it to count as portfolio evidence. Those are compatible:

**Publish the architecture, not the source.** `ARCH_M_MAINTENANCE.md`, `PROMPTS.md`, the bundle script and
honest write-ups of the process are the genuinely unusual part of this project, and none of them expose
your implementation. A public repo containing only method documents, with the app itself private, is a
stronger portfolio than the code would be — most people can show code; almost nobody can show a working
system for directing a model across 478 files.

**Ship the app publicly on Play.** A live listing is proof it works. The source staying closed is normal
and needs no explanation.

**Grant read access rather than going public.** GitHub lets you add a collaborator to a private repo for
free. An interviewer who asks to see it gets access for a week; you remove them afterwards.
