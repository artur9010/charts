# Unofficial Sia renterd helm chart

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/artur9010)](https://artifacthub.io/packages/search?repo=artur9010)

Helm chart for [Sia renterd software](https://sia.tech/software/renterd).

**This chart should be installed in a dedicated namespace due to hardcoded names**

## Helm repository

```
helm repo add artur9010 https://charts.motyka.pro
helm install renterd artur9010/renterd --version 1.1.1
```

## Requirements

- Kubernetes 1.28+ cluster, nodes should have at least 8GB of ram as renterd is memory hungry. It should work with older versions of k8s but I haven't tested it.
- Some kind of persistent storage (longhorn, ceph, aws-ebs etc.) and 50GB of available storage (mostly for blockchain copy). It's only required by `renterd-bus` pod which contains consensus (blockchain) copy and partial slabs. There is no support for hostPath, but [rancher local path provisioner](https://github.com/rancher/local-path-provisioner) should work fine

renterd can run with sqlite or mysql database, due to performance issues on sqlite one I decided to not include an option to use sqlite. This chart includes bitnami mysql chart which is enabled by default. If you already have mysql database, check the instructions below.

## Setup guide

Before you install this helm chart, create a secrets in destination namespace.

### Creating secret with seed and api passwords

Create an .txt file named secret.txt and containing:
```
RENTERD_SEED=12 words
RENTERD_API_PASSWORD=secure_api_password
RENTERD_BUS_API_PASSWORD=secure_api_password
RENTERD_WORKER_API_PASSWORD=secure_api_password
```

Seed: You can generate seed here: https://iancoleman.io/bip39/, make sure to select 12 words.
Password: API password, use the same value for all 3 of them.

Now run `kubectl create secret generic <secret name from values> -n <your namespace> --from-env-file=secret.txt`

### How to use external mysql database

If you already have a mysql databse - just disable built-in chart (`mysql.enabled` set to `false`) and create secret named `renterd-mysql` (you can change secret name in values, see `databaseSecretName`) inside renterd namespace.

Create an .txt file named mysql.txt and containing:
```
RENTERD_DB_URI=mysql.example.com:3306
RENTERD_DB_USER=renterd
RENTERD_DB_PASSWORD=hunter2
RENTERD_DB_NAME=renterd
RENTERD_DB_METRICS_NAME=renterd_metrics
```

Now run `kubectl create secret generic renterd-mysql -n <your namespace> --from-env-file=mysql.txt`

Additional requirements for external mysql database:
- `max_connections` a bit higher than default 151, 1024 works fine
- `log_bin_trust_function_creators` set to 1 (as long as your db user dosen't have SUPER privilage, see https://github.com/SiaFoundation/renterd/issues/910)

## CPU and memory requirements

Tested on Ryzen zen1 platform (Ryzen 5 2200G, 2400G) while uploading files via s3 api using rclone (--transfers 20)

```
➜  ~ kubectl top pod -n renterd-zen
NAME                                 CPU(cores)   MEMORY(bytes)   
mysql-0                              127m         2105Mi          
renterd-autopilot-859cb75986-hws2g   13m          12Mi            
renterd-bus-0                        902m         1118Mi          
renterd-worker-0                     319m         2755Mi          
renterd-worker-1                     119m         2254Mi          
renterd-worker-2                     887m         2125Mi          
renterd-worker-3                     267m         2655Mi          
renterd-worker-4                     131m         2388Mi  
```

## Looking for perfect server to run renterd? Check netcup

[![netcup](https://i.imgur.com/2Sjxas5.png)](https://www.netcup.eu/?ref=200705)

ARM servers are available from 7 eur per month. [Check netcup for more info.](https://www.netcup.eu/?ref=200705)

Use code `36nc16697741959` to get [5 EUR off](https://www.netcup.eu/bestellen/gutschein_einloesen.php?gutschein=36nc16697741959&ref=200705).

Looking for more [netcup coupons](https://netcup-coupons.com)? Check [netcup-coupons.com](https://netcup-coupons.com)

## Changelog

### 1.1.1
- Added a database readiness check to renterd-bus init container to make sure it won't start before db.
- Added missing labels to all objects

### 1.1.0
- Moved all contents of `.renterd` to main level of values.yaml

old
```
renterd:
  s3:
    enabled: true
```

new
```
s3:
  enabled: true
```

- Added an option to specify name of secret containing mysql credentials
- Added an option to specify securityContext of pods in values
- Updated `bitnami/mysql` chart to `9.23.0`

### 1.0.6
- Removed an option to specify external database credentials inside values.
- Renamed secret containing mysql credentials to `renterd-mysql`
- Changed default image from `1.0.5-zen` to `1.0.5` as most users will probably run renterd on mainnet.
- Added option to modify pod's `enableServiceLinks` and disabled it by default.
- Moved all configmaps to separate files

### 1.0.5
- Removed support for `VerticalPodAutoscaler`
- Upgraded `bitnami/mysql` chart to `9.22.0`
- Added option to specify `autopilot`, `worker` and `bus` settings inside values - `Values.renterd.{autopilot,workers,bus}.config`.
- Changed user inside renterd containers from root to unnamed one with id 1000.
- Changed autopilot to Deployment as it is stateless.

### 1.0.4
- Changed default image to `renterd:1.0.5-zen`
- Removed option to specify wallet seed and passwords in values.
- Added an option to specify name of secret containing seed and password

### 1.0.3
- Removed renterd.s3.keys from values as keypairs can now be managed inside webUI.
- mysql: changed default authentication plugin from `mysql_native_password` to `caching_sha2_password` due to massive spam in container logs, see https://github.com/bitnami/charts/issues/18606

## Sia Zen testnet automatic faucet claimer

This helm chart has built-in automatic faucet claimer for Sia Zen testnet, you can enable it in `autofaucet` section in values. You can claim up to 5000 ZenSC per day.

## Ingress

Tested with k3s default traefik.

You need two subdomains for renterd api's and s3 gateway.
There are API subpaths
```
main domain:
/ -> svc/renterd-bus
/api/worker -> svc/renterd-worker
/api/autopilot -> svc/renterd-autopilot

s3 domain:
/ -> svc/renterd-worker
```

Example configuration (with cert-manager annotation to automate certificate issuing):
```yaml
ingress:
  enabled: true
  className: "traefik"
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
  hosts:
    - host: renterd.example.com
      paths:
        - path: /
          pathType: ImplementationSpecific
          svcName: renterd-bus
          svcPort: 9980
        - path: /api/worker
          pathType: ImplementationSpecific
          svcName: renterd-worker
          svcPort: 9980
        - path: /api/autopilot
          pathType: ImplementationSpecific
          svcName: renterd-autopilot
          svcPort: 9980
    - host: s3.example.com
      paths:
        - path: /
          pathType: ImplementationSpecific
          svcName: renterd-worker
          svcPort: 8080
  tls:
    - secretName: ingress-tls
      hosts:
        - renterd.example.com
        - s3.example.com
```

## Values

See `values.yaml` file.