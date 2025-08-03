# cloudflared+ingress-nginx stack

Cloudflared with ingress-nginx helm chart included, make sure to have cert-manager installed before as it is required to run ingress-nginx.
This is a copy of my personal "chart" that I use myself, it's not great and not very "charty" but makes work done. Not all things are configurable but you're welcome to make pull requests.

## Requirements

- Cert-manager installed
- Cloudflare account with domain and cloudflared tunnel created. You must have an token.

## Install guide

- Create a tunnel in zero trust dashboard
- Set default response on tunnel to `nginx-cloudflared-controller:80`
- Set token in `.Values.token`, make sure to edit other values to meet your preferences.
- Now you can create an ingress with `nginx-cloudflared` class (you can change name in values). To route traffic to it create proxied CNAME record to `<tunnel id>.cfargotunnel.com`, you can find tunnel id in your browser URL bar when you try to edit an tunnel (`/networks/tunnels/cfd_tunnel/< ID HERE >/edit?tab=...`). You can also try to add external-dns, I haven't used it yet.