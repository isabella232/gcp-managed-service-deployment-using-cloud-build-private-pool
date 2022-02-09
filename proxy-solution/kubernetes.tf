resource "google_service_account" "kubernetes_cluster1" {
  project      = var.project_id
  account_id   = "gke-cluster1"
  display_name = "GKE Cluster1 Service Account"
}

resource "google_container_cluster" "cluster1" {
  project  = var.project_id
  name     = "cluster1"
  location = "europe-west1-d"

  remove_default_node_pool = true
  initial_node_count       = 1

  networking_mode = "VPC_NATIVE"
  network         = google_compute_network.vpc.self_link
  subnetwork      = google_compute_subnetwork.vpc_kubernetes_nodes.self_link

  ip_allocation_policy {
    services_secondary_range_name = "cluster1-services"
    cluster_secondary_range_name  = "cluster1-pods"
  }

  private_cluster_config {
    enable_private_endpoint = true
    enable_private_nodes    = true
    master_ipv4_cidr_block  = "10.20.0.0/28"

    master_global_access_config {
      enabled = true
    }
  }

  master_authorized_networks_config {
    cidr_blocks {
      display_name = "vpc"
      cidr_block   = "10.0.0.0/16"
    }
  }

  depends_on = [
    google_compute_network_peering_routes_config.vpc_service_networking
  ]
}

resource "google_container_node_pool" "cluster1_node1" {
  project    = var.project_id
  location   = "europe-west1-d"
  cluster    = google_container_cluster.cluster1.name
  name       = "cluster1-node1"
  node_count = 1

  max_pods_per_node = 32

  node_config {
    machine_type = "e2-medium"
    disk_type    = "pd-ssd"

    tags = ["cluster1-node"]

    service_account = google_service_account.kubernetes_cluster1.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}