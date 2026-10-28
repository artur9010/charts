# Unofficial Sia s3d Helm Chart

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/artur9010)](https://artifacthub.io/packages/search?repo=artur9010)

Helm chart for [Sia s3d software](https://github.com/SiaFoundation/s3d).

## Helm repository

```
helm repo add artur9010 https://charts.motyka.pro
helm install s3d artur9010/s3d
```

Or from the OCI registry:

```
helm install s3d oci://ghcr.io/artur9010/charts/s3d --version <version>
```

## First installation

s3d keeps its app key, users, access keys and object metadata in a SQLite database in `/data`, so keep `persistence.enabled: true` (the default).

1. Create the Secret with the admin API password (or set `createSecret: true` and `secretContent.S3D_ADMIN_PASSWORD`):

   ```
   kubectl create secret generic s3d --from-literal=S3D_ADMIN_PASSWORD="$(openssl rand -base64 32)"
   ```

2. Install the chart with `setupMode: true`. The pod then runs `sleep infinity` instead of s3d.
3. Register s3d with the Sia indexer. It asks for the indexer URL (default `https://sia.storage`) and your 12-word recovery phrase, or generates a new one if you leave it blank. Then it prints a URL where you approve the connection:

   ```
   kubectl exec -it s3d-0 -- s3d login
   ```

4. Upgrade the release with `setupMode: false`. s3d now starts.
5. Create a user and an S3 access key. The key pair is generated when both flags are omitted, and the secret key is printed only once:

   ```
   kubectl exec s3d-0 -- s3d users create <username>
   kubectl exec s3d-0 -- s3d keys create [--access-key <id> --secret-key <secret>] <username>
   ```

`kubectl exec s3d-0 -- s3d status` shows the upload pipeline, and `s3d keys list` / `s3d users list` show existing credentials.

## Upgrading from 1.x to 2.0.0 (breaking)

Chart 2.0.0 moves from s3d `bf33bf3` to s3d `0.2.1`. That version cannot open a database created by `bf33bf3`, so you have to start with an empty `/data` volume and go through [First installation](#first-installation) again.

Value changes:

- `sia.keyPairs` is removed. Create access keys with `s3d users create` and `s3d keys create`.
- `sia.indexerURL` is removed. The indexer URL is set during `s3d login`.
- `secretContent.S3D_RECOVERY_PHRASE` and the `S3D_RECOVERY_PHRASE` Secret key are no longer used. The phrase is entered during `s3d login`.
- New: the Secret must contain `S3D_ADMIN_PASSWORD`.
- New: `setupMode`, `apiHTTPSAddress`, `adminAddress`, `sia.diskUsageLimit`, `sia.uploadThreads`, `sia.dataShards`, `sia.parityShards`, `service.s3.httpsPort`.
- `persistence.enabled` now defaults to `true`.
- `apiAddress` now defaults to `":8000"` and is actually applied. Before, the image's `-api.s3 :8000` overrode it.
- `nodeSelector`, `affinity`, `tolerations` and `topologySpreadConstraints` are now rendered on the pod spec. Before, they were wrongly placed on the container.

Old:

```yaml
secretContent:
  S3D_RECOVERY_PHRASE: "..."
sia:
  indexerURL: "https://sia.storage"
  keyPairs:
    - accessKey: "..."
      secretKey: "..."
```

New:

```yaml
secretContent:
  S3D_ADMIN_PASSWORD: "..."
sia:
  diskUsageLimit: 6442450944
```

## Looking for perfect server to run renterd? Check netcup

[![netcup](https://i.imgur.com/2Sjxas5.png)](https://brzu.ch/renterd-netcup)

ARM servers are available from 7 eur per month. [Check netcup for more info.](https://brzu.ch/renterd-netcup)

Use code `36nc17460389834` to get [5 EUR off](https://brzu.ch/renterd-netcup).

Looking for more [netcup coupons](https://netcup-coupons.com)? Check [netcup-coupons.com](https://netcup-coupons.com)

## Values

Open this page on artifacthub and click Values on sidebar.