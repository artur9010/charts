# Basic Sia renterd helm chart

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/artur9010)](https://artifacthub.io/packages/search?repo=artur9010)

Simple helm chart containing [Sia renterd software](https://sia.tech/software/renterd).

## Helm repository

```
helm repo add artur9010 https://charts.motyka.pro
helm install renterd artur9010/renterd --version 1.0.1
```

## Requirements

- Kubernetes 1.28+ cluster, nodes should have at least 8GB of ram.
- Some kind of persistent storage solution (longhorn, ceph, aws-ebs etc.). It's only required by `renterd-bus` pod which contains consensus (blockchain) copy and partial slabs. There is no support for hostPath for now.
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

## Looking for perfect server to run renterd? Check netcup

[![netcup](https://i.imgur.com/2Sjxas5.png)](https://www.netcup.eu/?ref=IHREKUNDENNUMMER)

ARM servers are available from 7 eur per month. [Check netcup for more info.](https://www.netcup.eu/?ref=IHREKUNDENNUMMER)

Use code `36nc16697741959` to get [5 EUR off](https://www.netcup.eu/bestellen/gutschein_einloesen.php?gutschein=36nc16697741959&ref=IHREKUNDENNUMMER).

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
          svcPort: 9880
        - path: /api/worker
          pathType: ImplementationSpecific
          svcName: renterd-worker
          svcPort: 9880
        - path: /api/autopilot
          pathType: ImplementationSpecific
          svcName: renterd-autopilot
          svcPort: 9880
    - host: s3.example.com
      paths:
        - path: /
          pathType: ImplementationSpecific
          svcName: renterd-worker
          svcPort: 7070
  tls:
    - secretName: ingress-tls
      hosts:
        - renterd.example.com
        - s3.example.com
```

## Cloudflared tunnel

It also should work fine with cloudflared tunnel, just make sure to point /api/worker and /api/autopilot to renterd-worker and renterd-autopilot services, all other traffic should go to renterd-bus.

All traffic from s3 domain should go to `renterd-worker:7070`

## Values

See values.yaml file.