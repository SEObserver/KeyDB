# SEObserver KeyDB distribution

This repository is a downstream distribution prepared by SEObserver for its
own infrastructure. It is not affiliated with or endorsed by Snap Inc. No
general support, release cadence, SLA or compatibility commitment is provided.

## Base and versioning

The downstream branch `seobserver/6.3` starts from the exact upstream tag
`v6.3.3` (`3909d51337c90f1068a180a031b3b217ff5d28b6`). SEObserver releases use
annotated tags named `v6.3.3-seobserver.N`. `KEYDB_REAL_VERSION` remains
`6.3.3` to preserve protocol, RDB and replication compatibility.

KeyDB 6.3.4 is deliberately not the base. Both SEObserver front servers
previously observed immediate `SIGILL` exits (code 132) with that image and
generated roughly 500 GB of core dumps. Later clean tests on the same CPU model
did not reproduce the crash, so no root cause was established. Data,
configuration, timing and a silently replaced image remain possible factors.
The related upstream report is
[Snapchat/KeyDB#802](https://github.com/Snapchat/KeyDB/issues/802).

## Included fixes

The distribution keeps changes small and individually traceable:

| Area | Fixes |
| --- | --- |
| Active replication | Ignore the `INVALID_EXPIRE` sentinel in `MVCCRESTORE` |
| Lua sandbox | CVE-2022-24735, CVE-2022-24736, CVE-2025-46818 |
| Lua runtime | CVE-2024-31449, CVE-2024-46981, CVE-2025-46817, CVE-2025-46819, CVE-2025-49844 |
| Pattern matching | CVE-2022-36021, CVE-2024-31228 |
| Persistence | CVE-2026-25243, CVE-2026-63639 |
| HyperLogLog | CVE-2025-32023 |
| TLS | CVE-2026-56684 |
| Authentication | CVE-2025-21605 |
| Networking | CVE-2023-45145, CVE-2025-48367 |
| Build portability | Resolve the sorted-set iterator name collision with recent GCC versions (merged KeyDB PR #706) |

The KeyDB-origin fixes come from PRs
[#706](https://github.com/Snapchat/KeyDB/pull/706),
[#906](https://github.com/Snapchat/KeyDB/pull/906),
[#908](https://github.com/Snapchat/KeyDB/pull/908) and an independently
repaired adaptation of [#918](https://github.com/Snapchat/KeyDB/pull/918).
The head of PR #918 is not used because it contains a duplicate declaration
and misses lexer token initialization.

[PR #896](https://github.com/Snapchat/KeyDB/pull/896) was evaluated and
intentionally excluded. Its current unreviewed head can schedule a live master
client for asynchronous freeing during an RDB restart; the Linux AMD64 TLS
PSYNC2 differential reproduced corrupted replication state followed by a
`SIGSEGV`.

Security backports taken from Valkey retain their upstream commit identifiers
in the Git commit messages. The principal sources are:

- `89772ed827209c3dca376644498a235ef3edf692` and
  `955a7a9f2a2a3c57ba835a4db770efbc370ff816` for Lua isolation;
- `20f5199d96baf0c64bd4e7d042b6274c4e773bcb` for HyperLogLog;
- `14371b40c6408f9b030f44a5feff4fefac24977c` for stream NACK loading;
- `ff7455faff9adcb64a31a4a1fb8d7e57d2dfb1d1` for TLS pending clients;
- `f09f5f59727f5968c878310267dd07528e8ec17b` for pre-auth replies;
- `cb10d9d78f35945b667e46967b3980e89954d73b` for transient accept errors.

The following reviewed CVEs do not apply to the KeyDB 6.3.3 code paths:
CVE-2023-41056, CVE-2024-31227, CVE-2024-51741, CVE-2025-27151,
CVE-2025-67733, CVE-2026-21863, CVE-2026-23479 and CVE-2026-23631.

## Qualification

The release target is Linux AMD64 with TLS. Both jemalloc and libc builds are
compiled. The focused suite covers:

- active-active replication, reconnects and the persistent-expiry invariant;
- Lua sandboxing, cached-script isolation and caller ACL enforcement;
- malformed RESTORE/RDB payloads, duplicate stream NACKs and HyperLogLog;
- TLS pending-client cleanup;
- authentication and output-buffer limits;
- TCP, TLS, Unix-socket and cluster accept paths.

The upstream main, cluster, Sentinel, module and TLS suites must pass on a
native Linux AMD64 runner before a release tag is created. Docker Desktop on
Apple Silicon is useful for compilation and ordinary behavior tests, but is
not an acceptable substitute for this gate.

The high-volume subkey-expiry test keeps its original writes and assertion but
suppresses replies that it never consumes, avoiding TLS output backpressure on
slow runners. Failed-run server logs are dumped by CI.

Three malformed-RDB tests intentionally request allocations near `SIZE_MAX`.
Under AMD64 Rosetta, the emulator terminates the process with `SIGTRAP` instead
of returning `ENOMEM`; the same tests pass under native Linux ARM64 and are
kept unchanged. They must be judged only on a native AMD64 runner.

Flash/RocksDB support is not part of the qualified SEObserver build.
macOS is not part of the release qualification gate.
The optional network MOTD is disabled in qualified builds.

## Operational notes

The CVE-2025-21605 guard bounds unauthenticated output growth by disconnecting
a client on its first dynamic reply-list allocation. KeyDB has a 16 KiB static
client buffer and allocates dynamic replies in blocks of roughly 16 KiB, so the
real per-connection peak is higher than the logical 1 KiB threshold. Once a
connection has authenticated successfully, including before `RESET`, the
normal configured client-output limit applies.

Production promotion remains a separate decision. Publishing a source tag does
not authorize a deployment or a KeyDB failover.

The original BSD-3-Clause license and notices remain in `COPYING`.
