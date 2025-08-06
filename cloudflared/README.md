# cloudflared+ingress-nginx stack

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/artur9010)](https://artifacthub.io/packages/search?repo=artur9010)
![Kubernetes 1.30+](https://img.shields.io/badge/Kubernetes-1.30%2B-blue)

Cloudflared with ingress-nginx helm chart included, make sure to have cert-manager installed before as it is required to run ingress-nginx.
By default it runs as DaemonSet, cloudflare tunnels are limited to 25 connected clients so if you have bigger cluster just make sure to change type to Deployment in `.Values.cloudflared.type`
Values are also preconfigured to make ingress-nginx work fine in this setup, feel free to modify them to meet your requirements, those were fine for me.

## Requirements

- Cert-manager installed
- Cloudflare account with domain and cloudflared tunnel created. You must have an token.

## Quick start aka setup guide

- Create a tunnel in zero trust dashboard
- Set default response on tunnel to `nginx-cloudflared-controller:80`
- Set token in `.Values.token`, make sure to edit other values to meet your preferences.
- Now you can create an ingress with `nginx-cloudflared` class (you can change name in values). To route traffic to it create proxied CNAME record to `<tunnel id>.cfargotunnel.com`, you can find tunnel id in your browser URL bar when you try to edit an tunnel (`/networks/tunnels/cfd_tunnel/< ID HERE >/edit?tab=...`). You can also try to add external-dns, I haven't used it yet.

## Values

Check `values.yaml` for available values.

## Looking for perfect Linux server? Check netcup

[![netcup](https://i.imgur.com/2Sjxas5.png)](https://brzu.ch/cloudflared-netcup)

ARM servers are available from 7 eur per month. [Check netcup for more info.](https://brzu.ch/cloudflared-netcup)

Use code `36nc17460389834` to get [5 EUR off](https://brzu.ch/cloudflared-netcup).

Looking for more [netcup coupons](https://netcup-coupons.com)? Check [netcup-coupons.com](https://netcup-coupons.com)
