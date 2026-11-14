# SpliceFS pull request rules

The rules every pull request of a SpliceFS repository must pass, and what happens when a
change reaches `main`. They live here once and every repository calls them.

## The rules

1. **Every change is a pull request into `main`**, from its own branch.
2. **The description states the scope of the change**, in exactly one line:

   ```
   change_scope: revision
   ```

   | Value | Meaning | Version |
   |---|---|---|
   | `revision` | a fix or a change that keeps every client and server working together | `X.Y.Z` becomes `X.Y.(Z+1)` |
   | `minor` | a new feature, or anything that changes how client and server talk | `X.Y.Z` becomes `X.(Y+1).0` |
   | `major` | never merged | a new major version is a new repository named `<name>_v<major>` |

   A missing or invalid line fails the check, whatever the tests say.
3. **The description says what a user would notice**, as a list under the heading
   `## Change log`:

   ```
   ## Change log

   - The server tells clients its version.
   ```

   A change with nothing for users has one entry that starts with `Internal:`. Nobody edits
   `CHANGELOG.md` by hand. When the section is missing or empty in a branch of the repository
   itself, an entry is drafted from the change by the Claude API and written into the
   description, where the author sees it and can change it. Without the key, and in a fork,
   a missing section fails the check.
4. **The release bot sets the version in the branch.** It reads the latest released version of
   `main` (its release tag, or the file `VERSION` if that is higher), raises it by the scope, and
   adds one commit that writes it to the file `VERSION` and writes the entries of the
   description into `CHANGELOG.md` under a heading for that version.
5. **A pull request always sits on the tip of `main`.** When `main` moves, the bot rebuilds every
   open pull request on the new tip and sets its version again; the checks run again.
6. **A pull request merges with one merge commit.** No fast-forward and no squash.
7. **Every merge is a release.** The merge is tagged `v<VERSION>`, which starts the release of
   that repository. One change, one version.

## Versions and compatibility

- With the same first number, a client works with every server whose second number is equal
  or higher. The third number never matters, barring a bug; a bug that affects it is fixed by
  raising the second number on both sides.
- So the server is released first: before a client with a higher second number goes out, a
  server with that second number is released, even when the server's code did not change.
- The server tells every client its version, and a client refuses a server that is too old
  with a message that names both versions. This holds from server 0.4.0 on.

## Using the rules in a repository

Two small workflow files and two settings.

`.github/workflows/rules.yml`:

```yaml
name: Rules
on:
  pull_request:
    types: [opened, edited, reopened, synchronize]
permissions:
  contents: read
jobs:
  rules:
    uses: SpliceFS/.github/.github/workflows/pull-request-rules-v1.yml@main
    secrets:
      bot-private-key: ${{ secrets.RELEASE_BOT_PRIVATE_KEY }}
      claude-api-key: ${{ secrets.CLAUDE_API_KEY }}
```

`.github/workflows/main.yml`:

```yaml
name: Main
on:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  main:
    uses: SpliceFS/.github/.github/workflows/main-moved-v1.yml@main
    secrets:
      bot-private-key: ${{ secrets.RELEASE_BOT_PRIVATE_KEY }}
```

Settings: the secret `RELEASE_BOT_PRIVATE_KEY` and the variable `RELEASE_BOT_APP_ID` (the
SpliceFS Release Bot), the secret `CLAUDE_API_KEY` if entries are to be drafted (it can be a
secret of the organization), and a rule on `main` that requires the checks `rules / Change scope`
and `rules / Version`, requires the branch to be up to date, and allows merge commits only.

## Versions of these processes

- Each process has its own number in its file name: `pull-request-rules-v1.yml` and
  `main-moved-v1.yml`.
- A change that would break the repositories that call a process is added as a new file with the
  next number, for example `pull-request-rules-v2.yml`. The old file stays until no repository
  calls it.
- A repository chooses the version by the file name in its `uses:` line.
- The scripts of a process live in `processes/<name>/v<number>/`, for example
  `processes/pull-request-rules/v1/`.

## What the bot cannot do

- **A pull request from a fork.** The bot cannot push there. The author sets `VERSION` by hand
  and the check verifies it.
- **A conflict.** A branch that cannot be rebuilt on the new `main` is left as it is, and the bot
  says so in a comment. Rebase it by hand and push.

## Working on the rules

```
make check   # table tests of the scripts, with throwaway git repositories
make lint    # shellcheck
```
