# Unofficial Sia renterd helm chart

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/artur9010)](https://artifacthub.io/packages/search?repo=artur9010)

Helm chart for [Sia renterd software](https://sia.tech/software/renterd).

## Helm repository

```
helm repo add artur9010 https://charts.motyka.pro
helm install renterd artur9010/renterd --version 1.0.4
```

## Requirements

- Kubernetes 1.28+ cluster, nodes should have at least 16GB of ram as renterd is memory hungry. It should work with older versions of k8s but I haven't tested it.
- Some kind of persistent storage solution (longhorn, ceph, aws-ebs etc.) and 50GB of available storage (mostly for blockchain copy). It's only required by `renterd-bus` pod which contains consensus (blockchain) copy and partial slabs. There is no support for hostPath, but [rancher local path provisioner](https://github.com/rancher/local-path-provisioner) should work fine
- (Optional) VerticalPodAutoscaler, [there is a nice chart for it](https://artifacthub.io/packages/helm/cowboysysop/vertical-pod-autoscaler)

renterd can run with sqlite or mysql database, due to performance issues on sqlite one I decided to not include an option to use sqlite. This chart includes bitnami mysql chart that you can enable by setting `mysql.enabled` to `true`. If you already have a mysql databse - create two databases (eq. `renterd` and `renterd_metrics`) and grant all privileges on them to renterd user. Provide credentials to external database in section `mysqlExternal` in values

```yaml
mysqlExternal:
  address: "mysql.example.com:3306"
  username: "renterd"
  password: "renterd123"
  database: "renterd"
  databaseMetrics: "renterd_metrics"
```

Additional requirements for external mysql database:
- `max_connections` a bit higher than default 151, 1024 works fine
- `log_bin_trust_function_creators` set to 1 (as long as your db user dosen't have SUPER privilage, see https://github.com/SiaFoundation/renterd/issues/910)

And while it's not a requirement, please increase innodb_buffer_pool_size from default 128MB, 4G should be ok for 16GB node. I've tested it with those params and it works fine for me, those are also a defaults if you enable built-in mysql chart (Values.mysql.primary.configuration)
```
[mysqld]
innodb_buffer_pool_size=4G
```
## Changes

### 1.0.4
- Changed default image to `renterd:1.0.5-zen`
- Removed option to specify wallet seed and passwords in values.
- Added an option to specify name of secret containing 

### 1.0.3
- Removed renterd.s3.keys from values as keypairs can now be managed inside webUI.
- mysql: changed default authentication plugin from `mysql_native_password` to `caching_sha2_password` due to massive spam in container logs, see https://github.com/bitnami/charts/issues/18606

## Creating secret

Create an .txt file named secret.txt and containing:
```
RENTERD_SEED=24 words
RENTERD_API_PASSWORD=secure_api_password
RENTERD_BUS_API_PASSWORD=secure_api_password
RENTERD_WORKER_API_PASSWORD=secure_api_password
```

Seed: You can generate seed here: https://iancoleman.io/bip39/, make sure to select 24 words.
Password: API password, use the same value for all 3 of them.

Now run `kubectl create secret generic <secret name from values> -n <your namespace> --from-env-file=secret.txt`

## CPU and memory requirements
Tested on Ryzen zen1 platform (Ryzen 5 2200G, 2400G), while uploading files to s3 api via rclone, max 4 uploads at once. As database gets bigger it will probably require more memory, renterd holds uploaded data in memory.
```
NAME                  CPU(cores)   MEMORY(bytes)
mysql-0               52m          875Mi
renterd-autopilot-0   8m           10Mi
renterd-bus-0         538m         112Mi
renterd-worker-0      215m         3314Mi
renterd-worker-1      196m         3415Mi
renterd-worker-2      1447m        1867Mi
```

## Looking for perfect server to run renterd? Check netcup

[![netcup](https://i.imgur.com/2Sjxas5.png)](https://www.netcup.eu/?ref=200705)

ARM servers are available from 7 eur per month. [Check netcup for more info.](https://www.netcup.eu/?ref=200705)

Use code `36nc16697741959` to get [5 EUR off](https://www.netcup.eu/bestellen/gutschein_einloesen.php?gutschein=36nc16697741959&ref=200705).

## [Experimental] VerticalPodAutoscaler support

This helm chart supports VerticalPodAutoscaler, it can be enabled by setting `renterd.{bus,autopilot,worker}.vpa.enabled` to `true` in values.

## Testnet automatic faucet claimer

This helm chart has built-in automatic faucet claimer for Sia Zen testnet, you can enable it in `autofaucet` section in values. You can claim up to 5000 SC per day.

Example:
```yaml
autofaucet:
  enabled: true
  address: "68bf48e81536f2221f3809aa9d1c89c1c869a17c6f186a088e49fd2605e4bfaaa24f26e4c42c"
  amount: "1000000000000000000000000000" # 1000 SC
  cron: "0 */4 * * *"
  restartPolicy: Never
```

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

See values.yaml file.