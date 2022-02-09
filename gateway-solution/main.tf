resource "random_id" "id" {
  byte_length = 2
}


# Transit gateway network appliance
module "transit_gateway" {
  source = "../modules/transit-gateway"

  project_id = var.project_id
  region     = "europe-west1"
  name       = "tgw-${random_id.id.hex}"

  # Allow google peered addresses to use the gateway.
  allowed_source_ranges = ["10.10.0.0/16", "10.20.0.0/16"]

  # Allow forwarding to the GKE master peering range
  accessible_ranges = {
    gke = {
      cidr = "10.20.0.0/24"
      priority = 1000
    }
  }

  vpc_project_id   = var.project_id
  vpc_network_name = google_compute_network.vpc.name
  vpc_subnet_name  = google_compute_subnetwork.vpc_transit.name
}

resource "google_compute_route" "gateway_routes" {
  for_each = var.accessible_ranges

  project    = local.vpc_project_id
  name       = "${var.vpc_network_name}-${var.name}-${each.key}"
  dest_range = each.value.cidr

  network      = var.vpc_network_name
  next_hop_ilb = google_compute_forwarding_rule.gateway.id
  priority     = each.value.priority
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

resource "google_compute_subnetwork" "vpc_transit" {
  project       = var.project_id
  network       = google_compute_network.vpc.id
  name          = "${google_compute_network.vpc.name}-transit"
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