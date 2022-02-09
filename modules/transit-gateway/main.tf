locals {
  vpc_project_id = coalesce(var.vpc_project_id, var.project_id)
}

resource "google_service_account" "gateway" {
  project      = var.project_id
  account_id   = var.name
  display_name = "Transit gateway service account"
}


resource "google_compute_instance_template" "gateway" {
  project = var.project_id
  region  = var.region

  name           = var.name
  can_ip_forward = true
  tags           = [ "transit-gw", var.name ]

  machine_type = "e2-micro" # Use a larger machine for higher throughput per instance.

  metadata_startup_script = file("${path.module}/resources/startup_script.sh")

  disk {
    source_image = "debian-cloud/debian-10"
    boot         = true
    disk_size_gb = 10
    disk_type    = "pd-standard"

    auto_delete = true
  }

  network_interface {
    subnetwork_project = local.vpc_project_id
    subnetwork         = "https://www.googleapis.com/compute/v1/projects/${local.vpc_project_id}/regions/${var.region}/subnetworks/${var.vpc_subnet_name}"
  }

  service_account {
    email  = google_service_account.gateway.email
    scopes = ["cloud-platform"]
  }
}

resource "google_compute_region_instance_group_manager" "gateway" {
  project = var.project_id
  region  = var.region
  name    = "${var.name}-mig"

  base_instance_name = var.name

  version {
    instance_template = google_compute_instance_template.gateway.id
  }

  named_port {
    name = "https"
    port = 443
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.gateway.id
    initial_delay_sec = 300
  }
}

resource "google_compute_region_autoscaler" "gateway" {
  project = var.project_id
  region  = var.region
  name    = "${var.name}-autoscaler"

  target = google_compute_region_instance_group_manager.gateway.id

  autoscaling_policy {
    min_replicas    = 1
    max_replicas    = 3
    cooldown_period = 60

    metric {
      name   = "compute.googleapis.com/instance/network/sent_bytes_count"
      type   = "DELTA_PER_MINUTE"
      target = 500 * 1000 * 1000 # Egress above 500 MB for last minute
    }
  }
}


resource "google_compute_region_backend_service" "gateway" {
  project = var.project_id
  region  = var.region
  name    = "${var.name}-service"

  load_balancing_scheme           = "INTERNAL"
  connection_draining_timeout_sec = 10

  health_checks = [google_compute_health_check.gateway.id]

  backend {
    group = google_compute_region_instance_group_manager.gateway.instance_group
  }
}

resource "google_compute_forwarding_rule" "gateway" {
  project = var.project_id
  name    = var.name
  region  = var.region

  ip_protocol           = "TCP"
  load_balancing_scheme = "INTERNAL"
  all_ports             = true
  allow_global_access   = true

  network    = "projects/${local.vpc_project_id}/global/networks/${var.vpc_network_name}"
  subnetwork = "projects/${local.vpc_project_id}/regions/${var.region}/subnetworks/${var.vpc_subnet_name}"

  backend_service = google_compute_region_backend_service.gateway.id
}


resource "google_compute_health_check" "gateway" {
  project             = var.project_id
  name                = "${var.name}-health-check"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    request_path = "/health.html"
    port         = "8080"
  }
}


resource "google_compute_firewall" "gateway_health_check" {
  project = local.vpc_project_id
  name    = "${var.vpc_network_name}-${var.name}-health-check"
  network = var.vpc_network_name

  direction     = "INGRESS"
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = [ var.name ]

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }
}

resource "google_compute_firewall" "gateway_internal" {
  project = local.vpc_project_id
  name    = "${var.vpc_network_name}-${var.name}-internal"
  network = var.vpc_network_name

  direction     = "INGRESS"
  source_ranges = var.allowed_source_ranges
  target_tags   = [ var.name ]

  allow { protocol = "all" }
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