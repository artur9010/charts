# AGENTS.md

Guidance for AI coding agents working in this repository. Human-facing docs live in each chart's `README.md`.

## Keeping this file current

This file must stay accurate. Whenever a change affects anything described here, update `AGENTS.md` in the same commit. That includes adding, removing or renaming a chart, changing the build or release process, changing the Renovate setup, or adopting a new convention. If something here no longer matches the repository, fix this file rather than following the outdated text. Describe only how things are now. Do not add plans, wishlists or TODO items.

## Repository overview

This is a personal Helm chart repository published at `https://charts.motyka.pro` (GitHub Pages, served from `docs/`) and listed on Artifact Hub under the `artur9010` repository.

```
charts/<name>/            chart sources (one directory per chart)
docs/                     published Helm repository (GitHub Pages root)
  <name>-<version>.tgz    packaged releases (immutable, committed)
  index.yaml              Helm repo index (generated)
  index.html              landing page (generated)
  artifacthub-repo.yml    Artifact Hub repository metadata
  CNAME                   charts.motyka.pro
build.sh                  packages new chart versions and regenerates docs/index.*
scripts/bump-chart-version.sh   bumps the patch part of a chart's `version`
renovate.json             Renovate configuration
.github/workflows/renovate.yml  self-hosted Renovate, runs hourly
```

### Charts

| Chart | What it deploys | Notes |
|---|---|---|
| `cloudflared` | A Cloudflare Tunnel (`cloudflared`, DaemonSet or Deployment) plus a bundled `ingress-nginx` subchart with the class `nginx-cloudflared` | It has a dependency, so `Chart.lock` and the vendored `charts/ingress-nginx-*.tgz` are committed. It also holds `secrets.craftum.yaml`, a SOPS-encrypted (AWS KMS) file. |
| `renterd` | Sia `renterd`, split into bus, worker and autopilot StatefulSets | Needs an external MySQL. Its README has a `## Changelog` section. |
| `s3d` | Sia `s3d`, an S3-compatible gateway (single StatefulSet) | Its `appVersion` and image tag are a git commit SHA, not a SemVer version. |

All charts use `apiVersion: v2` and `type: application`. They carry Artifact Hub annotations (`artifacthub.io/category`, `artifacthub.io/maintainers` and, where present, `artifacthub.io/links` and `artifacthub.io/screenshots`).

## Tooling and environment

- Helm 4 is the current target (verified with `helm` v4.3.1). Templates must stay compatible with Helm 3.
- The dev environment is NixOS. Run tools through `nix-shell`, for example `nix-shell -p kubernetes-helm --run '<cmd>'`. There is no Docker daemon.
- `build.sh` requires `helm` on `PATH`.

## Validating changes

Run these for every chart you touch before committing:

```sh
helm lint --strict charts/<name>
helm template test charts/<name>                      # default values must render
helm template test charts/<name> -f my-values.yaml    # also exercise the code paths you changed
```

- Rendering must succeed with the default `values.yaml`. Toggle the flags your change affects (`ingress.enabled`, `persistence.enabled`, `createSecret`, `cloudflared.type: Deployment`, and so on) and render again.
- For `cloudflared`, run `helm dependency build charts/cloudflared` first if the vendored subchart is missing.
- There is no CI lint or test job. Local validation is the only gate.

## Release workflow

Each released chart version is a `.tgz` committed to `docs/`. Released packages are immutable.

1. Make the chart change.
2. Bump `version` in `charts/<name>/Chart.yaml` (SemVer: patch for fixes and dependency bumps, minor for new features, major for breaking value or resource changes). If the application version changed, update `appVersion` to match the image tag in `values.yaml` (without the digest).
3. For `renterd`, add an entry at the top of `## Changelog` in its README. Mark breaking changes in the heading and give old and new value examples, following the existing entries.
4. Run `bash build.sh` from the repo root. It packages every chart whose `docs/<name>-<version>.tgz` does not exist yet, merges `docs/index.yaml`, rewrites the URLs and regenerates `docs/index.html`.
5. Commit the chart sources and the generated `docs/` files together. Release commits are titled `<chart> <version>`, for example `s3d 1.0.1`.

Rules:

- Never modify, overwrite or delete an existing `docs/*.tgz`. Always bump the version instead.
- Do not hand-edit `docs/index.yaml` or `docs/index.html`. Change `build.sh` instead.
- Keep `docs/CNAME` and `docs/artifacthub-repo.yml` as they are unless asked.

## Renovate

- Renovate runs hourly from `.github/workflows/renovate.yml` using `config:best-practices`. It opens one PR per update, with branch prefix `<chart>-` and a semantic commit `chore(<chart>): ...`.
- `renovate.json` declares `postUpgradeTasks` (`scripts/bump-chart-version.sh <chart>`, then `build.sh`), but in practice Renovate PRs change only the dependency line (for example `values.yaml` or the subchart version). The workflow does not allow post-upgrade commands, and `fileFilters` covers only `charts/*/*`. After merging Renovate PRs, the maintainer makes a release commit (`<chart> <version>`) that bumps `version`/`appVersion` and runs `build.sh`. Follow the release workflow above for that commit.
- Image tags are pinned as `tag@sha256:digest` (see `cloudflared` and `renterd` values). Keep that format so Renovate can update them, and never use floating tags such as `latest`.
- Subchart versions in `Chart.yaml` are exact pins that Renovate updates. Do not switch them to ranges. When a dependency version changes, refresh `Chart.lock` and the vendored archive with `helm dependency update`.
- `bump-chart-version.sh` only handles plain `X.Y.Z` versions. Do not give charts pre-release or build suffixes.

## Chart conventions in this repository

Follow the existing patterns of the chart you are editing:

- Helpers live in `templates/_helpers.tpl` and are namespaced by chart: `<chart>.name`, `<chart>.fullname`, `<chart>.chart`, `<chart>.labels`, `<chart>.selectorLabels`.
- Every resource includes `{{- include "<chart>.labels" . | nindent 4 }}`. Selectors use only `<chart>.selectorLabels`, plus `app.kubernetes.io/component` where a chart has several workloads (renterd's bus, worker and autopilot).
- Pod templates carry `checksum/<name>` annotations computed with `include (print $.Template.BasePath "/<file>.yaml") . | sha256sum`, so pods restart when config changes. Add one for every ConfigMap or Secret a pod consumes.
- Application config is rendered into a ConfigMap and mounted with `subPath` (for example `/data/renterd.yml` or `/data/s3d.yml`).
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

- Declare subcharts in `Chart.yaml` with `https://` repositories. Commit `Chart.lock` and the archive in `charts/`, because `build.sh` runs `helm dep up` before packaging.
- Optional subcharts need a `condition: <subchart>.enabled`.
- Configure subcharts under their name key in the parent `values.yaml` (see `ingress-nginx:` in `cloudflared`).

### Packaging hygiene

- Keep `.helmignore` up to date. Files in the chart directory that are not part of the chart, such as `secrets.craftum.yaml`, are otherwise packaged into the public `.tgz`.

## Security

- Never commit plaintext secrets. `charts/cloudflared/secrets.craftum.yaml` is SOPS-encrypted. Do not decrypt it, print its values or replace it with plaintext.
- The `renterd` and `s3d` secrets contain wallet seed or recovery phrases. Do not change defaults in a way that would make the chart generate or store them in plain values without the user opting in.

## Commits and pull requests

- Release commits: `<chart> <version>`. Renovate commits: `chore(<chart>): update ...`.
- Keep a change to a single chart per commit where practical, including its generated `docs/` artifacts.
- Do not commit or push unless asked.
