# Nix impure evaluation fails under Landlock

Minimal Linux reproducer using Landrun directly. No sandnix, repository modules,
or Nix daemon are involved in the sandboxed evaluation.

```sh
nix run github:adrian-gierakowski/nix-landrun-repro
# Or, from this checkout:
nix run .#repro
nix run .#control
```

The locked packages provide Nix 2.35.3 (reproducer) and 2.34.9 (control).
On 2.35.3 pure evaluation prints `2`, then impure evaluation exits nonzero:

```text
error: opening file "/": Permission denied
```

Both evaluations print `2` with 2.34.9. The expression is only `1 + 1`.

Run on Linux with Landlock enabled. Before invoking Nix, each runner queries the
Landlock ABI and exits with an explicit error if it is unavailable. It also
checks that opening `/` for directory enumeration fails with `EACCES` inside
the sandbox. Landrun's `--best-effort` permits kernels without its newest
features while retaining the filesystem restrictions required here. This
reproduces on Landlock ABI 7.

The sandbox allows the Nix store, `/proc`, `/dev/null`, and a private temporary
directory. It does not grant read access to `/`. Nix uses `dummy://`, an empty
temporary configuration directory and home, and no user configuration.
`--rox /nix/store` permits executing Nix and loading its libraries; `dummy://`
avoids accessing the local store database or daemon under `/nix/var/nix`.

Upstream commit
[7981f28017b7af317546749e25bddb412b3f4c52](https://github.com/NixOS/nix/commit/7981f28017b7af317546749e25bddb412b3f4c52)
changed `getFSSourceAccessor()` to initialize a descriptor-backed accessor for
`/`. Impure evaluator initialization calls it before evaluating the expression.
The new accessor opens `/` with `O_RDONLY`, requiring directory-read permission.

If already inside an affected sandbox, launch this flake with a Nix 2.34.9
client; the outer Nix command may otherwise fail before running the reproducer.

## Proposed fix

`nix-directory-opath.patch` changes directory accessor initialization to try
`O_PATH | O_DIRECTORY` first, retaining the existing handling for regular files
and symlinks. The same traversal-only helper opens the parent of a direct
symlink accessor, so that parent need not be readable either. A failed directory
open falls back to a readable open only for `ENOTDIR`. Directory enumeration
still opens a readable descriptor and therefore still requires read permission.

```sh
nix run .#patched
nix run .#verify
nix build .#nix-patched
nix build .#unit-tests
./result/bin/nix-util-tests --gtest_filter='FSSourceAccessorTest.*'
```

`patched` runs the same two expressions with the patched 2.35.3 client.
`verify` additionally checks permitted file reads, imports, directory listing,
and symlinks, and asserts that forbidden file reads, directory listings, and
symlinks to forbidden files remain denied.

The patch includes a Linux unit test constructing an accessor for an
execute-only directory. It checks readable descendants, direct symlink accessors
(including dangling links and loops), modification-time tracking, and denied enumeration.
It skips when the test user can bypass directory permissions (for example root).
