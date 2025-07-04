# Unofficial Sia renterd Helm Chart

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/artur9010)](https://artifacthub.io/packages/search?repo=artur9010)
![Kubernetes 1.30+](https://img.shields.io/badge/Kubernetes-1.30%2B-blue)

Helm chart for [Sia renterd software](https://sia.tech/software/renterd).

**This chart should be installed in a dedicated namespace.**

**This chart is still work in progress, may not be perfect but it work**

**Always check changelog at the bottom of this README before updating.**

## Helm repository

```
helm repo add artur9010 https://charts.motyka.pro
helm install renterd artur9010/renterd
```

## Requirements

- Kubernetes 1.30+ cluster. It should work with older versions of k8s but I haven't tested it.
- Some kind of persistent storage (longhorn, ceph, aws-ebs etc.) and 100GB of available storage (mostly for blockchain copy). It's only required by `renterd-bus` pod which contains consensus (blockchain) copy and partial slabs. There is no support for hostPath, but [rancher local path provisioner](https://github.com/rancher/local-path-provisioner) should work fine

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

**Seed:** You can generate seed here: https://iancoleman.io/bip39/, make sure to select 12 words.

**Password:** API and WebUI password, use the same value for all 3 of them.

Now run `kubectl create secret generic <secret name from values> -n <your namespace> --from-env-file=secret.txt`

### How to use external mysql database

If you already have a mysql databse - just disable built-in chart (`mysql.enabled` set to `false`) and create secret named [here you should put `databaseSecretName` from values] inside renterd namespace.

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

If running mysql with replication, renterd dosen't have any option to define read replicas - use [proxysql](https://proxysql.com/).

## CPU and memory requirements

Tested on Ryzen zen1 platform (Ryzen 5 2200G, 2400G) while uploading files via s3 api using rclone (--transfers 8), running on renterd 8d50d3c

```
NAME                                 CPU(cores)   MEMORY(bytes)   
mysql-0                              162m         1585Mi          
renterd-autopilot-74b89897d6-pd7j5   5m           11Mi            
renterd-bus-0                        110m         123Mi           
renterd-worker-0                     452m         513Mi           
renterd-worker-1                     236m         383Mi           
renterd-worker-2                     419m         312Mi    
```

## Looking for perfect server to run renterd? Check netcup

[![netcup](https://i.imgur.com/2Sjxas5.png)](https://brzu.ch/renterd-netcup)

ARM servers are available from 7 eur per month. [Check netcup for more info.](https://brzu.ch/renterd-netcup)

Use code `36nc17460389834` to get [5 EUR off](https://brzu.ch/renterd-netcup).

Looking for more [netcup coupons](https://netcup-coupons.com)? Check [netcup-coupons.com](https://netcup-coupons.com)

## Ingress

Example configuration (with cert-manager annotation to automate certificate issuing):

```yaml
ingresses:
  - name: "renterd"
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

You can also specify multiple ingresses here, for example if you want to S3 be available from internet (traefik) but keep webui and api's behind Tailscale ingress.

```yaml
ingresses:
  - name: "renterd-tailscale"
    className: "tailscale"
    hosts:
      - host: renterd
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
    tls:       
      - secretName: renterd-tailscale-tls
        hosts:
          - renterd
  - name: "renterd"
    className: "traefik"
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt
    hosts:
      - host: renterd-s3.example.com
        paths:
          - path: /
            pathType: ImplementationSpecific
            svcName: renterd-worker
            svcPort: 8080
    tls:
      - secretName: ingress-tls
        hosts:
          - renterd-s3.example.com
```

If using nginx make sure to set those annotations:

```
nginx.ingress.kubernetes.io/proxy-body-size: '0'
nginx.ingress.kubernetes.io/ssl-redirect: 'false'
```

First one disables limit for body size, second disables https redirect which for some reason broke rclone uploads(???)

## Values

See `values.yaml` file.

## Other?

This chart:
- disables logging inside renterd, you already have all of this on stdout so why duplicate it?

## Changelog

### 1.3.11
- Upgraded mysql chart to `13.0.2`, also reduced max_connections and buffer size.
- For those of you who use secret management that can be used with helm values, I added option to specify secret values for renterd seed/api password and database credentials in values.yaml

### 1.3.10
- Upgraded renterd to `2.4.0`

### 1.3.9
- Upgraded renterd to `2.3.2`

### 1.3.8
- Upgraded renterd to `2.3.0`

### 1.3.7
- Upgraded renterd to `2.2.1`

### 1.3.6
- Upgraded renterd to `2.2.0`

### 1.3.5
- Upgraded renterd to `2.1.0-beta.1`

### 1.3.4
- Upgraded renterd to `2.0.1`

### 1.3.3
- Upgraded renterd to `2.0.0`
- Upgraded mysql chart to `12.2.2`

### 1.3.2
- Upgraded renterd to `2.0.0-beta.4`

### 1.3.1
- Upgraded renterd to `2.0.0-beta.3`

### 1.3.0
** Breaking changes, see below**
- Moved PVC from template inside renterd-bus statefulset to standalone PersistentVolumeClaim, as only one bus is allowed to be running and volumeClaimTemplates does not update PVC's after changing the template it would make it easier to manage PVC params using gitops tools like ArgoCD. If you are already were using renterd chart older than 1.3.0, make sure to set `storage.name` to `renterd-bus-data-renterd-bus-0` to keep compatibility. Also as renterd requires some kind of storage to work regardless of slab-packing or used database solution, it is no longer allowed to disable creation of PVC. This might be changed in future, but i don't think it will be.

### 1.2.13
- Upgraded renterd to `2.0.0-beta.2`
- Removed `managementContainer` as it is no longer needed.
- Upgraded mysql chart to `12.2.1`

### 1.2.12
- Upgraded renterd to `1.1.0`

### 1.2.11
**If you are upgrading from 1.2.10 or older, make sure to delete `consensus.db`. It is not compatible with current beta**
![Discord notice](https://i.imgur.com/1Uzo36t.png)

- Upgraded renterd to `1.1.0-beta.6`.
- Upgraded `bitnami/mysql` chart to `12.0.1`. You might need to delete mysql statefulset before upgrading (see https://artifacthub.io/packages/helm/bitnami/mysql#to-12-0-0)

### 1.2.10
- Added an option to add a sidecar container with ubuntu to renterd-bus pod to make checking renterd files a bit easier.
- Upgraded renterd to `1.1.0-beta.5`. You might need to change ports, check 1.2.7 below.
- Removed default securityContext from values, if you were using old default 1000:1000 you will need to restore that.
- Added an option to disable volume creation for bus - see `bus.volume.enabled` in values.

### 1.2.9
- Removed CronJob for automatic faucet claim as it is not working for more than 2 months.
- Upgraded `bitnami/mysql` chart to `11.1.17`

### 1.2.8
- Added an env with worker id to autopilot pods to make it compatible with latest dev releases.

### 1.2.7
** If you are running renterd on test network - you will need to set proper service ports in values, 9880 for http, 7070 for s3. If running dev builds built after 12/08/2024 - you don't need to care about it as all images now are running on default ports 9980 and 8080. **

- Removed custom entrypoint due to issues with current dev builds

### 1.2.6
- Upgraded `bitnami/mysql` chart to `11.1.14`
- Added an option to specify network name (https://github.com/SiaFoundation/renterd/pull/1423)

### 1.2.5
- Added an option to use sqlite backend, just leave database secret name empty and disable built-in mysql.
- Disabled built-in mysql chart by default, to enable it set `mysql.enalbed` to true.
- Upgraded renterd to 1.0.8

### 1.2.4
- Added an option to disable autopilot if not needed (eq. you have some custom solution to form contracts) - `autopilot.enabled` (default: `true`)
- Changed default image from `renterd:1.0.8-beta.1` to `renterd:1.0.8-beta.2`

### 1.2.3
- Removed unneeded envvar from autopilot - `RENTERD_WORKER_EXTERNAL_ADDR`
- Updated `bitnami/mysql` chart from `11.1.2` to `11.1.7`
- Updated `RENTERD_WORKER_EXTERNAL_ADDR` env to use cluster domain names instead of IPs
- Set `publishNotReadyAddresses` on `renterd-worker` service due to [https://github.com/SiaFoundation/renterd/issues/1368](https://github.com/SiaFoundation/renterd/issues/1368)

### 1.2.2
- Quick fix for 1.0.8-beta1 compatibility (missing path in `RENTERD_WORKER_EXTERNAL_ADDR`)

### 1.2.1
- Changed wait-for image from `ghcr.io/patrickdappollonio/wait-for:v1.0.0` to `artur9010/wait-for:v1.0.0` due to lack of arm64 compatibility.
- Changed default image from `renterd:1.0.7` to `renterd:1.0.8-beta.1`
- Added support for `RENTERD_WORKER_EXTERNAL_ADDR` (required now in clustered setups)

### 1.2.0
**There are breaking changes, read before updating**
- Upgraded `bitnami/mysql` chart to `11.1.2`, mysql was updated to 8.4 and mysql_native_password authentication was disabled by default. Before upgrading please migrate renterd user password hashing to `caching_sha2_password` - see https://stackoverflow.com/questions/76851219/how-to-migrate-mysql-authentication-from-mysql-native-password-to-caching-sha2-p
- Renamed `CronJob/faucet-claimer` to `CronJob/renterd-testnet-faucet-claim`
- Disabled renterd logfile (`ConfigMap/renterd`, see entrypoint) and removed temporary volumes for storing them from workers and autopilot.
- Moved `innodb_buffer_pool_size` from mysql config to command line arguments provided to mysql server and removed whole custom mysql config from default values.
- Reworked whole ingress setup in values, it now allows to setup multiple ingresses for some of you who might want to do that (eq. if you need to use two ingressclasses to allow access to webui only from VPN). See "Ingress" section inside README for new structure.

### 1.1.4
- Updated default image from `renterd:1.0.6` to `renterd:1.0.7`

### 1.1.3
- Upgraded `bitnami/mysql` chart to `10.1.1`. If you customized mysql settings in values - check changelog before updating - https://artifacthub.io/packages/helm/bitnami/mysql

### 1.1.2
- Updated default image from `renterd:1.0.5` to `renterd:1.0.6`

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