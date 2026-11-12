## What changes

<!-- What a user or an administrator will notice. One short paragraph or a few bullets. -->

## Checked

<!-- What you ran and what you tried by hand. -->

## Change scope

<!--
Required. Exactly one line, with one of these values:

  change_scope: revision   a fix or a change that keeps every client and server working together
  change_scope: minor      a new feature, or anything that changes how client and server talk

"major" is never merged: a new major version is a new repository named <name>_v<major>.
The version number is set in this branch by the release bot from this line. A check compares
it with what the change really does and fails if they differ.
-->

change_scope:
