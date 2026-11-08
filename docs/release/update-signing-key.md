# Update signing keys

Every update is signed with an Ed25519 key. Nera installs an update only when its signature matches a public key
built into the app (`NeraUpdatePublicKey`, [ADR-0011](../adr/0011-updates.md)) **and** the new app is signed by the
same Apple Developer ID team with the same bundle ID. Two independent gates: a stolen update key alone can't ship an
update, and neither can a stolen Developer ID certificate alone.

## Custody

- **Two keys.** Builds accept a current key and a standby key. Releases are signed with the current key; the standby
  is never used until a rotation, so the current key can be replaced without stranding anyone.
- **Where they live.** Only in the maintainer's macOS Keychain and in the release environment's secrets. Never in
  the repository, issues or chats.
- **Offline backup.** Both keys are kept in an AES-256 encrypted disk image on offline storage, created and verified
  by `scripts/release/backup-update-keys.sh` (it checks each key against the public keys built into the app);
  `restore-update-keys.sh` restores them.

## Rotation (when the current key is lost or may have leaked)

1. Sign releases with the standby key.
2. Generate a new standby (`swift scripts/release/sign-update.swift generate-keys`) and build it into the app next to
   the new current key.
3. Ship a build; from then on the old key is no longer accepted.
4. If the old key leaked: pull any update it signed from the feed (`scripts/release/make-appcast.py --remove`) and say
   so in the release notes.

## Accepted risk

One maintainer holds the keys. Mitigations: the two independent gates above, offline backup, rotation without
stranding installs.
