# Google Managed Service Deployment Using Cloud Build Private Pools

This repository provides a [gateway](./gateway-solution/README.md)- and [proxy](./proxy-solution/README.md)-based solution to access transitively peered resources from your Cloud Build pipeline.

The Gateway solution exchanges custom routes with the Google service producer(s) peering (the `servicenetworking-googleapis-com`-peer) to transitively peer Cloud Build with the GKE peering. This solution doesn't require any configuration in the build pipeline.

The Proxy solution allows Cloud Build to proxy the GKE master nodes. This solution requires the build pipeline user to configure the proxy to access transitively peered resources.

A [VPN-based solution](https://cloud.google.com/architecture/accessing-private-gke-clusters-with-cloud-build-private-pools#creating_a_connection_between_your_two_networks) is available as part of the Cloud Build product documentation.