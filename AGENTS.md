# AGENTS.md

Guidance for AI coding agents working in this repository. Human-facing docs live in each chart's `README.md`.

## Keeping this file current

This file must stay accurate. Whenever a change affects anything described here, update `AGENTS.md` in the same commit. That includes adding, removing or renaming a chart, changing the build or release process, changing the Renovate setup, or adopting a new convention. If something here no longer matches the repository, fix this file rather than following the outdated text. Describe only how things are now. Do not add plans, wishlists or TODO items.

## Repository overview

This is a personal Helm chart repository, listed on Artifact Hub under the `artur9010` repository. It is published in two places:

- a classic Helm repository at `https://charts.motyka.pro`, served by GitHub Pages from the `gh-pages` branch;
- an OCI registry at `oci://ghcr.io/artur9010/charts/<chart>`, with charts signed by keyless cosign.

`master` branch:

```
charts/<name>/                  chart sources (one directory per chart)
ct.yaml                         chart-testing configuration
renovate.json                   Renovate configuration
.github/workflows/lint.yml      ct lint on pull requests
.github/workflows/release.yml   publishes changed charts on push to master
.github/workflows/renovate.yml  self-hosted Renovate, runs hourly
.github/workflows/renovate-changelog.yml  AI summary comment on Renovate PRs
.github/opencode/               opencode config and prompt for renovate-changelog
.github/scripts/chart-diff.sh   rendered and upstream subchart diffs for renovate-changelog
.github/scripts/release-notes.sh per-chart release notes and artifacthub.io/changes for release
```

`gh-pages` branch (written by CI, not edited on master):

```
<name>-<version>.tgz    packaged releases (immutable)
index.yaml              Helm repo index
index.html              static landing page
artifacthub-repo.yml    Artifact Hub repository metadata
CNAME                   charts.motyka.pro
.nojekyll
```

### Charts

| Chart | What it deploys | Notes |
|---|---|---|
| `cloudflared` | A Cloudflare Tunnel (`cloudflared`, DaemonSet or Deployment) plus a bundled `ingress-nginx` subchart with the class `nginx-cloudflared` | It has a dependency. `Chart.lock` is committed, but the downloaded `charts/*.tgz` is ignored by git and rebuilt in CI. It also holds `secrets.craftum.yaml`, a SOPS-encrypted (AWS KMS) file. |
| `renterd` | Sia `renterd`, split into bus, worker and autopilot StatefulSets | Needs an external MySQL. Its README has a `## Changelog` section. |
| `s3d` | Sia `s3d`, an S3-compatible gateway (single StatefulSet) | s3d reads `adminPassword` only from its config file, so a `config` init container merges `S3D_ADMIN_PASSWORD` from the Secret into an in-memory `emptyDir` copy of the ConfigMap. First-time `s3d login` is interactive, and `setupMode: true` runs `sleep infinity` so it can be done with `kubectl exec`. Access keys live in the s3d database and are managed with `s3d users` and `s3d keys`, not with values. Its README documents breaking upgrades. |

All charts use `apiVersion: v2` and `type: application`. They carry Artifact Hub annotations (`artifacthub.io/category`, `artifacthub.io/maintainers` and, where present, `artifacthub.io/links` and `artifacthub.io/screenshots`).

## Tooling and environment

- Helm 4 is the current target (verified with `helm` v4.3.1). Templates must stay compatible with Helm 3.
- The dev environment is NixOS. Run tools through `nix-shell`, for example `nix-shell -p kubernetes-helm --run '<cmd>'`. There is no Docker daemon.
- CI uses Helm v4.3.1 (`azure/setup-helm`) and chart-testing (`helm/chart-testing-action`).

## Validating changes

Run these for every chart you touch before committing:

```sh
nix-shell -p chart-testing kubernetes-helm yamllint yamale --run 'ct lint --config ct.yaml --charts charts/<name>'
helm template test charts/<name>                      # default values must render
helm template test charts/<name> -f my-values.yaml    # also exercise the code paths you changed
```

- `ct lint` runs `helm lint`, validates `Chart.yaml` against the chart schema, and runs yamllint on `Chart.yaml` and `values.yaml`. Use two spaces before inline `#` comments, no spaces inside `[ ]`, and end files with a newline.
- `ct lint` also requires the chart `version` to be higher than on `master`, through `check-version-increment`. Locally that check compares against your local `master`.
- Rendering must succeed with the default `values.yaml`. Toggle the flags your change affects (`ingress.enabled`, `persistence.enabled`, `createSecret`, `cloudflared.type: Deployment`, and so on) and render again.
- For `cloudflared`, run `helm dependency build charts/cloudflared` first, because the subchart archive is not committed.
- `.github/workflows/lint.yml` runs `ct lint --config ct.yaml` on pull requests that touch `charts/**`.
- Renovate authenticates as a GitHub App. `actions/create-github-app-token` creates the token from the `RENOVATE_APP_ID` and `RENOVATE_APP_PRIVATE_KEY` secrets. Do not switch it back to `GITHUB_TOKEN`: pull requests opened with `GITHUB_TOKEN` do not trigger other workflows, so lint and renovate-changelog would not run on Renovate PRs.

## Renovate PR summaries

- `.github/workflows/renovate-changelog.yml` posts an AI summary as a sticky comment (marker `<!-- renovate-changelog -->`) on every PR from a `renovate/` branch. It covers risk, breaking changes, impact on our chart, chart maintenance (version bump, `appVersion`), rendered manifest changes and upgrade steps.
- The comment is written by opencode (npm `opencode-ai`, pinned in `OPENCODE_VERSION`) using the free OpenCode Zen model `opencode/deepseek-v4.1-flash-free`. No API key or provider secret is needed. Free Zen models are offered for a limited time, so when the model disappears, pick another one from `opencode models` (IDs ending in `-free`) and update both `MODEL` in the workflow and `model` in `.github/opencode/opencode.json`.
- `.github/scripts/chart-diff.sh <base> <head> <out>` renders each changed chart at both revisions with default values and, for subchart bumps, pulls the old and new upstream subcharts with `helm pull` and diffs them. It runs locally too: `nix-shell -p kubernetes-helm yq-go --run '.github/scripts/chart-diff.sh <base> <head> <out>'`.
- The model's tools (read, `git`, read-only `ls`/`cat`/`head`/`tail`/`grep`/`diff`/…, Exa web search MCP; no `$` or `../`) are set in `.github/opencode/opencode.json`, and the output format in `.github/opencode/prompt.md`. It gets no GitHub token.
- Check denied tool calls with `gh run view <id> --log | grep -a "✗ "`. Re-run with `gh workflow run renovate-changelog.yml -f pr=<n>`. Locally, use `nix-shell -p opencode` (the npm package doesn't install on NixOS) and `opencode run --standalone`.

## Release workflow

Releases are built by CI. Do not package charts by hand or commit `.tgz` files to `master`.

1. Make the chart change.
2. Bump `version` in `charts/<name>/Chart.yaml` (SemVer: patch for fixes and dependency bumps, minor for new features, major for breaking value or resource changes). If the application version changed, update `appVersion` to match the image tag in `values.yaml` (without the digest).
3. For `renterd`, add an entry at the top of `## Changelog` in its README. Mark breaking changes in the heading and give old and new value examples, following the existing entries.
4. Merge or push to `master`. `.github/workflows/release.yml` then publishes the release:
   - `.github/scripts/release-notes.sh` lists the master commits (merged PRs and direct pushes) that touched `charts/<name>/` since the previous `<name>-*` tag. The list is written into the working-tree `Chart.yaml` as the `artifacthub.io/changes` annotation, so it ends up in the `.tgz` and `index.yaml` without being committed. Preview it locally with `nix-shell -p yq-go --run 'FORCE=1 .github/scripts/release-notes.sh <name> <out> [rev]'`;
   - `helm/chart-releaser-action` finds charts changed since the latest git tag;
   - it packages them, creates a GitHub Release and tag `<name>-<version>` for each one, and commits the `.tgz` and the updated `index.yaml` to `gh-pages` (`packages_with_index: true`);
   - each GitHub Release body is replaced with that chart's notes (`gh release edit`), instead of GitHub's repo-wide generated notes;
   - each new package is pushed to `oci://ghcr.io/artur9010/charts` and signed with `cosign sign` (keyless, GitHub OIDC). Versions already in GHCR are skipped.

Rules:

- Never modify, overwrite or delete an existing `<name>-<version>.tgz`, GitHub Release, tag or OCI tag. Always bump the version instead.
- Do not edit `gh-pages` by hand, except for `index.html`, `CNAME` and `artifacthub-repo.yml`, and only when asked. `index.html` is static and does not list versions.
- Every chart change merged to `master` must come with a version bump. chart-releaser keys releases by tag, so an unbumped change is either skipped or collides with an existing release.
- Release tags are created by CI. Do not create or move `<name>-<version>` tags manually.
- Do not add `artifacthub.io/changes` to `Chart.yaml` by hand. CI generates it from PR titles, so keep PR titles descriptive.
- Dependency repositories used by subcharts must be added with `helm repo add` in `release.yml` and listed in `chart-repos` in `ct.yaml`.

## Renovate

- Renovate runs hourly from `.github/workflows/renovate.yml` using `config:best-practices`. It opens one PR per update, with branch prefix `<chart>-` and a semantic commit `chore(<chart>): ...`.
- The `bumpVersions` rule in `renovate.json` bumps the patch part of `version` in the chart's `Chart.yaml` in the same PR, so merging a Renovate PR publishes a release. `bumpVersions` is experimental in Renovate.
- `appVersion` is not updated automatically. When Renovate bumps the main image, update `appVersion` in the PR before merging.
- Image tags are pinned as `tag@sha256:digest` (see `cloudflared` and `renterd` values). Keep that format so Renovate can update them, and never use floating tags such as `latest`.
- Subchart versions in `Chart.yaml` are exact pins that Renovate updates together with `Chart.lock`. Do not switch them to ranges.
- Chart versions are plain `X.Y.Z`, without pre-release or build suffixes.

## Chart conventions in this repository

Follow the existing patterns of the chart you are editing:

- Helpers live in `templates/_helpers.tpl` and are namespaced by chart: `<chart>.name`, `<chart>.fullname`, `<chart>.chart`, `<chart>.labels`, `<chart>.selectorLabels`.
- Every resource includes `{{- include "<chart>.labels" . | nindent 4 }}`. Selectors use only `<chart>.selectorLabels`, plus `app.kubernetes.io/component` where a chart has several workloads (renterd's bus, worker and autopilot).
- Pod templates carry `checksum/<name>` annotations computed with `include (print $.Template.BasePath "/<file>.yaml") . | sha256sum`, so pods restart when config changes. Add one for every ConfigMap or Secret a pod consumes.
- Application config is rendered into a ConfigMap and mounted with `subPath` (for example `/data/renterd.yml`). s3d is the exception: its ConfigMap is a template that its `config` init container completes into `/etc/s3d/s3d.yml`.
- Secrets are created by the user beforehand by default (`secretName`, `createSecret: false`). Chart-managed secrets are opt-in through `createSecret: true` and `secretContent`. Keep that default, because the secrets include wallet seeds.
- Pods default to `automountServiceAccountToken: false` and `enableServiceLinks: false`.
- Existing resource names are hardcoded in places (for example `s3d`, `renterd-bus`, `cloudflared`, `nginx-cloudflared`). Renaming them breaks upgrades and the documented setup instructions (cloudflared's tunnel default route points at `nginx-cloudflared-controller:80`). Rename only as a deliberate breaking change with a major version bump and a changelog entry.
- Values that users override per environment (`resources`, `nodeSelector`, `affinity`, `tolerations`, `topologySpreadConstraints`, `securityContext`, `podAnnotations`) default to empty and are rendered only when set.
- The READMEs keep the Artifact Hub badge and the netcup referral section. Do not remove them.

## Helm best practices to apply in new and changed code

These come from the official [Helm chart best practices guide](https://helm.sh/docs/chart_best_practices/), adapted to this repository.

### Chart.yaml

- Chart names follow DNS-1123: lowercase letters, digits and `-`, at most 63 characters. The directory name must equal `name`.
- `version` is SemVer 2. Bump it on every change that ships. `appVersion` is quoted.
- Provide `description`, `keywords`, `home`, `icon` (`helm lint` reports a missing icon) and Artifact Hub annotations for new charts.

### Values

- Use camelCase keys starting with a lowercase letter, with no dashes. Dashed keys come only from subchart names (`ingress-nginx`), which templates read with `index .Values "ingress-nginx" ...`.
- Quote strings in `values.yaml`, and use `| quote` when rendering string values into YAML, to avoid type coercion (`"true"`, `"0755"`, version-like strings).
- Prefer maps over lists of objects so values can be overridden with `--set`. Keep existing lists (for example `ingress.hosts`) for compatibility.
- Prefer flat values. When nesting, guard every level (`{{- with }}` or `{{- if }}`) so that missing parents do not cause nil-pointer errors.
- Document every value with a comment directly above it that starts with the key name, and keep commented examples in sync with the templates.
- Never put real secrets, seeds, tokens or passwords in `values.yaml`. Use obvious placeholders only.
- A `values.schema.json` (JSON Schema) is recommended for new charts and large value changes. If a chart has one, update it together with `values.yaml`.

### Templates

- Put one resource per file, named in kebab-case with the kind included (`statefulset-renterd-bus.yaml`, `pvc.yaml`). Use `.yaml` for manifests and `.tpl` for helpers only.
- Namespace every `define` with the chart name, because defined templates are global across subcharts.
- Indent with two spaces, never tabs. Write `{{ .Value }}`, with spaces inside the braces. Chomp whitespace with `{{-`/`-}}`, use `nindent` with `toYaml`, and avoid generating blank lines.
- Do not set `metadata.namespace` in templates. The namespace comes from `--namespace` / `.Release.Namespace`. Referencing `.Release.Namespace` inside a spec, as the NetworkPolicy does, is fine.
- Use `{{- /* ... */}}` template comments to document template logic. Do not use `#` YAML comments that contain template expressions that might fail.
- Use `required` for mandatory values, and `fail` for invalid combinations, with a clear message.
- Pod-level fields (`nodeSelector`, `affinity`, `tolerations`, `topologySpreadConstraints`, `securityContext`, `imagePullSecrets`) belong under the pod `spec`, not under a container. Check indentation when adding them.
- Render booleans that may be false with `{{ .Values.x | toString }}` or `{{ .Values.x }}`, not `default`, because `default` treats `false` as unset.

### Labels and selectors

- Recommended labels: `app.kubernetes.io/name`, `app.kubernetes.io/instance`, `app.kubernetes.io/managed-by`, `helm.sh/chart` (with `+` replaced by `_`), and optionally `app.kubernetes.io/version` and `app.kubernetes.io/component`.
- Selectors (`matchLabels`, Service `selector`) must use only stable labels (name, instance and component), never the version or the chart label. Selectors on existing workloads are immutable, so changing them is a breaking change.
- Use annotations for metadata that is not used for selection.

### Pods and images

- Split images into `image.repository`, `image.tag` and `image.pullPolicy` (default `IfNotPresent`). Pin tags, preferably with a digest.
- Provide readiness and liveness probes, and expose `resources` through values.
- Prefer secure defaults: no service account token, no service links, a non-root `securityContext` where the image supports it, and least-privilege RBAC if any is ever added.

### Dependencies

- Declare subcharts in `Chart.yaml` with `https://` repositories. Commit `Chart.lock`. The archive in `charts/` is ignored by git (`.gitignore`) and fetched in CI.
- Optional subcharts need a `condition: <subchart>.enabled`.
- Configure subcharts under their name key in the parent `values.yaml` (see `ingress-nginx:` in `cloudflared`).

### Packaging hygiene

- Keep `.helmignore` up to date. Files in the chart directory that are not part of the chart, such as `secrets.craftum.yaml`, are otherwise packaged into the public `.tgz`.

## Security

- Never commit plaintext secrets. `charts/cloudflared/secrets.craftum.yaml` is SOPS-encrypted. Do not decrypt it, print its values or replace it with plaintext.
- The `renterd` secrets contain the wallet seed, and the `s3d` secret contains the admin API password. The s3d recovery phrase is entered interactively during `s3d login` and is never stored by the chart. Do not change defaults in a way that would make the chart generate or store these in plain values without the user opting in.

## Commits and pull requests

- Release commits: `<chart> <version>`. Renovate commits: `chore(<chart>): update ...`.
- Keep a change to a single chart per commit where practical.
- Do not commit or push unless asked.
