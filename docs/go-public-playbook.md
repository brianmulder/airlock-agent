# Go-Public Playbook (Airlock)

This is a personal playbook for taking a local repo public on GitHub while keeping a private, complete
history for posterity.

Goals:

- Public repo: concise, readable commit history on `main` (a “diary” narrative).
- Private repo: full history preserved (all the messy iterations stay private).

## 0) Preconditions

- Working tree clean: `git status` shows nothing to commit.
- Decide the public history style:
  - **Diary**: chronological milestones, but squashed into ~5–8 commits.
  - (Alternative) Feature-themed: grouped by subsystem; fewer commits but less chronological.

## 1) Preserve the full local history (safety net)

Create a local branch and an anchor tag before rewriting anything:

```bash
git branch private/full-history
git tag private-prepublic-1
```

Notes:

- Do not push `private-prepublic-1` to the public remote.
- Keeping `private/full-history` local means you can always recover anything.

## 2) Build an abridged “diary” history (public candidate)

Create a working branch for the rewrite:

```bash
git branch public/diary main
git checkout public/diary
```

Rewrite history into a short diary using interactive rebase from the root:

```bash
git rebase -i --root
```

Typical “diary” approach:

- Keep a handful of milestone commits as `pick`.
- Mark everything else as `fixup` (or `squash`) under the nearest milestone.
- Optionally `reword` milestone messages to be clean and public-facing.

Target size: 5–8 commits.

## 3) Prove the public candidate snapshot is identical

Compare trees (strongest snapshot equality check):

```bash
git rev-parse private/full-history^{tree}
git rev-parse public/diary^{tree}
```

If the hashes match, the tracked file contents at the tips are identical.

Also useful:

```bash
git diff --name-status private/full-history..public/diary
```

Expected: no output.

## 4) Promote the public candidate to `main`

Point `main` at the abridged diary history:

```bash
git branch -f main public/diary
git checkout main
```

## 5) Local safety checks (pre-public)

Run the test suite:

```bash
AIRLOCK_OFFLINE=1 make test
```

Basic “secret-ish” grep sweep (tune patterns as needed):

```bash
git grep -nEI '(api[_-]?key|secret|token|password|passwd|BEGIN (RSA|OPENSSH)|xox[baprs]-|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})' -- .
```

Path/host leakage sweep (tune for your threat model):

```bash
git grep -nE '(/home/[^/]+/|C:\\\\Users\\\\|@MSI)' -- README.md docs stow scripts || true
```

Note: after rewriting, `git fsck` may show “dangling commits”; that’s normal until garbage collection.

## 6) Tag a public release

Create an annotated public tag:

```bash
git tag -a v0.1.0 -m "v0.1.0 (initial public release)"
```

## 7) Create GitHub repos (UI)

Create two repos on GitHub:

- `airlock` (PUBLIC)
- `airlock-private` (PRIVATE “posterity” archive)

For both: do NOT initialize with README / .gitignore / license (avoid merge noise).

## 8) Add remotes

Add a private remote for posterity:

```bash
git remote add posterity git@github.com:<you>/airlock-private.git
```

Add the public remote:

```bash
git remote add origin git@github.com:<you>/airlock.git
```

## 9) Push to the private repo (full history)

Make the private repo’s `main` point at the full history:

```bash
git push -u posterity private/full-history:main
```

Push the private anchor tag:

```bash
git push posterity private-prepublic-1
```

Optional: also push the public release tag to the private repo:

```bash
git push posterity v0.1.0
```

## 10) Push to the public repo (abridged history)

Push only `main` and the public tag:

```bash
git push -u origin main
git push origin v0.1.0
```

Avoid:

- `git push --tags` (it would also push `private-prepublic-1` unless you delete it or avoid it)

Optional guardrail: restrict what `git push origin` pushes by default:

```bash
git config remote.origin.push refs/heads/main:refs/heads/main
```

## 11) “Make-safe” on GitHub (recommended protections)

After the first push (so Actions/check names exist):

- Settings → Branches → Branch protection rule for `main`
  - Require status checks to pass (select the CI workflow job)
  - Require linear history (optional)
  - Block force pushes
  - Block deletions
  - (Optional) Include administrators
- Settings → Tags (or tag protection rules, if available)
  - Protect `v*`
- Settings → Actions
  - Ensure workflows are enabled (default is usually fine)

## 12) Post-push checklist

- Confirm Actions is green on `main`.
- Create a GitHub Release for `v0.1.0` (optional, but nice for a first public cut).
- Confirm no unintended refs exist on the public repo:
  - No `private/*` branches
  - No `private-prepublic-*` tags
