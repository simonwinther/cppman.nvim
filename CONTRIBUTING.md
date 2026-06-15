# Contributing

## Commit messages

This project uses [Conventional Commits](https://www.conventionalcommits.org/)
and [Release Please](https://github.com/googleapis/release-please) to automate
versioning and the changelog.

Format:

```
<type>(<scope>): <subject>
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`.

- Subject in imperative mood, max 50 chars, no trailing period.
- `feat` triggers a minor bump, `fix` a patch bump. A `!` after the
  type/scope (or a `BREAKING CHANGE:` footer) triggers a major bump.

## Linking issues

Reference issues from feature commits with a `Refs:` trailer — **not** a
closing keyword:

```
feat(viewer): add configurable border

Refs: #74
```

Multiple issues are fine:

```
fix(cache): avoid stale cppman page rendering

Refs: #80, #81
```

Why `Refs:` and not `Closes:`? A closing keyword in a commit on `master`
closes the issue the moment that commit lands, which is before the change is
actually released. We want issues to close when the release ships.

The release workflow handles the conversion: it collects every `Refs: #NN`
since the last tag and rewrites them as `Closes #NN` inside the Release Please
PR body (between `<!-- release-please-auto-closes:start -->` markers). When you
merge that release PR, GitHub closes the referenced issues.

If you put the `Refs:` line only in a pull request description, that works too —
the workflow also scans the bodies of PRs merged since the last release.

A `commit-msg` hook rejects closing keywords locally so a stray `Closes #NN`
can't reach `master`. Enable it once per clone:

```
git config core.hooksPath .githooks
```

The `commit-lint` workflow enforces the same rule on pull requests.

## Merge method

Merge or rebase feature PRs so commit bodies (and their `Refs:` trailers) are
preserved. If you squash, keep the `Refs:` line in the squash commit body or in
the PR description; otherwise the link is lost.
