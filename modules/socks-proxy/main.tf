locals {
  vpc_project_id = coalesce(var.vpc_project_id, var.project_id)
}

resource "google_service_account" "proxy" {
  project      = var.project_id
  account_id   = var.name
  display_name = "Proxy service account"
}


resource "google_compute_instance_template" "proxy" {
  project = var.project_id
  region  = var.region

  name = var.name
  tags = ["socks-proxy", var.name]

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
    email  = google_service_account.proxy.email
    scopes = ["cloud-platform"]
  }
}

resource "google_compute_region_instance_group_manager" "proxy" {
  project = var.project_id
  region  = var.region
  name    = "${var.name}-mig"

  base_instance_name = var.name

  version {
    instance_template = google_compute_instance_template.proxy.id
  }

  named_port {
    name = "socks"
    port = 1080
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.proxy_http.id
    initial_delay_sec = 90
  }
}

resource "google_compute_region_autoscaler" "proxy" {
  project = var.project_id
  region  = var.region
  name    = "${var.name}-autoscaler"

  target = google_compute_region_instance_group_manager.proxy.id

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


resource "google_compute_region_backend_service" "proxy_tcp" {
  project = var.project_id
  region  = var.region
  name    = "${var.name}-tcp-service"

  protocol = "TCP"
  load_balancing_scheme           = "INTERNAL"
  connection_draining_timeout_sec = 10

  health_checks = [ google_compute_health_check.proxy_probe.id ]

  backend {
    group = google_compute_region_instance_group_manager.proxy.instance_group
  }
}


resource "google_compute_region_backend_service" "proxy_udp" {
  project = var.project_id
  region  = var.region
  name    = "${var.name}-udp-service"

  protocol = "UDP"
  load_balancing_scheme           = "INTERNAL"

  health_checks = [ google_compute_health_check.proxy_probe.id ]

  backend {
    group = google_compute_region_instance_group_manager.proxy.instance_group
  }
}

resource "google_compute_address" "proxy" {
  project = var.project_id
  name    = var.name
  region  = var.region

  address_type = "INTERNAL"
  purpose      = "SHARED_LOADBALANCER_VIP"
  subnetwork   = "projects/${local.vpc_project_id}/regions/${var.region}/subnetworks/${var.vpc_subnet_name}"
}

resource "google_compute_forwarding_rule" "proxy_tcp" {
  project = var.project_id
  name    = "${var.name}-tcp"
  region  = var.region

  ip_address            = google_compute_address.proxy.address
  ip_protocol           = "TCP"
  ports                 = ["1080"]
  load_balancing_scheme = "INTERNAL"
  allow_global_access   = true

  network    = "projects/${local.vpc_project_id}/global/networks/${var.vpc_network_name}"
  subnetwork = "projects/${local.vpc_project_id}/regions/${var.region}/subnetworks/${var.vpc_subnet_name}"

  backend_service = google_compute_region_backend_service.proxy_tcp.id
}

resource "google_compute_forwarding_rule" "proxy_udp" {
  project = var.project_id
  name    = "${var.name}-udp"
  region  = var.region

  ip_address            = google_compute_address.proxy.address
  ip_protocol           = "UDP"
  ports                 = ["1080"]
  load_balancing_scheme = "INTERNAL"
  allow_global_access   = true

  network    = "projects/${local.vpc_project_id}/global/networks/${var.vpc_network_name}"
  subnetwork = "projects/${local.vpc_project_id}/regions/${var.region}/subnetworks/${var.vpc_subnet_name}"

  backend_service = google_compute_region_backend_service.proxy_udp.id
}


resource "google_compute_health_check" "proxy_http" {
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

resource "google_compute_health_check" "proxy_probe" {
  project             = var.project_id
  name               = "${var.name}-probe"

  tcp_health_check {
    port = 1080
  }
}


resource "google_compute_firewall" "proxy_health_check" {
  project = local.vpc_project_id
  name    = "${var.vpc_network_name}-${var.name}-health-check"
  network = var.vpc_network_name

  direction     = "INGRESS"
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = [var.name]

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }
}

resource "google_compute_firewall" "proxy_internal" {
  project = local.vpc_project_id
  name    = "${var.vpc_network_name}-${var.name}-internal"
  network = var.vpc_network_name

  direction     = "INGRESS"
  source_ranges = var.allowed_source_ranges
  target_tags   = [var.name]

  allow {
    protocol = "tcp"
    ports    = ["1080"]
  }

  allow {
    protocol = "udp"
    ports    = ["1080"]
  }
}