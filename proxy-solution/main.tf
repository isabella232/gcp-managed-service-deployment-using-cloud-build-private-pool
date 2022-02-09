resource "random_id" "id" {
  byte_length = 2
}


# Socks proxy instance group
module "socks_proxy" {
  source = "../modules/socks-proxy"

  project_id = var.project_id
  region     = "europe-west1"
  name       = "proxy-${random_id.id.hex}"

  # Allow google peered addresses to use the proxy.
  allowed_source_ranges = ["10.10.0.0/16", "10.20.0.0/16"]

  vpc_project_id   = var.project_id
  vpc_network_name = google_compute_network.vpc.name
  vpc_subnet_name  = google_compute_subnetwork.vpc_proxy.name
}


# Networking
# 10.0.0.0/16   => VPC subnets
# 10.10.0.0/16  => (Google) Service networking peerings
# 10.20.0.0/24  => GKE master subnets (16x /28)
# 10.20.16.0/20 => GKE services subnets (16x /24)
# 10.20.64.0/18 => GKE pods subnets (16x /22)
resource "google_compute_network" "vpc" {
  project = var.project_id
  name    = "vpc-${random_id.id.hex}"

  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "vpc_proxy" {
  project       = var.project_id
  network       = google_compute_network.vpc.id
  name          = "${google_compute_network.vpc.name}-proxy"
  region        = "europe-west1"
  ip_cidr_range = "10.0.0.0/24"

  private_ip_google_access = true
}

resource "google_compute_subnetwork" "vpc_kubernetes_nodes" {
  project       = var.project_id
  network       = google_compute_network.vpc.id
  name          = "${google_compute_network.vpc.name}-kubernetes-nodes"
  region        = "europe-west1"
  ip_cidr_range = "10.0.1.0/24"
  secondary_ip_range = [
    {
      ip_cidr_range = "10.20.16.0/24"
      range_name    = "cluster1-services"
    },
    {
      ip_cidr_range = "10.20.64.0/22"
      range_name    = "cluster1-pods"
    },
  ]

  private_ip_google_access = true
}

# Reserved addresses for private service networking
resource "google_service_networking_connection" "vpc_service_networking" {
  network = google_compute_network.vpc.id

  service = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [
    google_compute_global_address.vpc_service_networking_a.name,
  ]
}

resource "google_compute_global_address" "vpc_service_networking_a" {
  project = var.project_id
  network = google_compute_network.vpc.id

  name        = "service-networking-a"
  description = "Reserved for google-based service networking connections"

  address_type  = "INTERNAL"
  address       = "10.10.0.0"
  prefix_length = 20
  purpose       = "VPC_PEERING"
}

# Enable custom route export for the google service-networking peers
resource "google_compute_network_peering_routes_config" "vpc_service_networking" {
  project = var.project_id
  network = google_compute_network.vpc.name
  peering = "servicenetworking-googleapis-com"

  import_custom_routes = false
  export_custom_routes = true

  depends_on = [google_service_networking_connection.vpc_service_networking]
}


# Firewalls
resource "google_compute_firewall" "kubernetes_cluster1_internal" {
  project = var.project_id
  name    = "${google_compute_network.vpc.name}-cluster1-internal"
  network = google_compute_network.vpc.id

  direction = "EGRESS"
  destination_ranges = [
    google_container_cluster.cluster1.private_cluster_config[0].master_ipv4_cidr_block,
    google_compute_subnetwork.vpc_kubernetes_nodes.ip_cidr_range,
    { for range in google_compute_subnetwork.vpc_kubernetes_nodes.secondary_ip_range : range.range_name => range.ip_cidr_range }[google_container_cluster.cluster1.ip_allocation_policy[0].cluster_secondary_range_name],
  ]
  target_tags = ["cluster1-node"]

  allow { protocol = "all" }
}


# NAT gateway
resource "google_compute_router" "nat" {
  project = var.project_id
  region  = "europe-west1"
  name    = "${google_compute_network.vpc.name}-nat"
  network = google_compute_network.vpc.name
}

resource "google_compute_router_nat" "nat_config" {
  project                            = var.project_id
  region                             = "europe-west1"
  router                             = google_compute_router.nat.name
  name                               = "${google_compute_network.vpc.name}-nat-euw1"
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                     = google_compute_subnetwork.vpc_proxy.name
    secondary_ip_range_names = []
    source_ip_ranges_to_nat = [
      "PRIMARY_IP_RANGE",
    ]
  }
}

resource "google_compute_route" "proxy_internet_egress" {
  project    = var.project_id
  name       = "${google_compute_network.vpc.name}-proxy-internet-egress"
  dest_range = "0.0.0.0/0"

  network          = google_compute_network.vpc.name
  next_hop_gateway = "default-internet-gateway"
  priority         = 1000

  tags = [
    "socks-proxy",
  ]
}
