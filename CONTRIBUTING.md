# Contributing

Keep public maintenance work concise and traceable.

## Issues

Describe the observable problem and the desired outcome. Do not turn the issue
into an implementation diary or a record of discarded approaches.

## Branches

For work linked to an issue, use GitHub's issue-branch format:
`<issue-number>-<short-kebab-case-title>`, for example
`3-retain-valid-idle-dock`. Link the branch to the issue when GitHub offers
that option.

## Pull requests

Summarize the final implementation, the reason for durable design choices and
the validation performed. Mention only material limitations that still affect
users. Do not narrate the sequence of attempts, superseded fixes or work that
was considered but not included. Git commits provide the development sequence.
Link the issue and use a closing keyword when the pull request fully resolves
it.

Repository-maintained text and commit messages must be in English. Follow the
scope, reference-file and validation rules in [AGENTS.md](AGENTS.md), including
the prohibition on publishing extracted X4 game files.

## Documentation

Document the current behavior, compatibility contract, durable architectural
decisions and outstanding validation boundaries. Investigation chronology,
discarded attempts and commit-by-commit narratives belong only in Git history,
not in maintained documentation, issue descriptions or pull-request summaries.
