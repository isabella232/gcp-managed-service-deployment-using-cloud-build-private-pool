resource "google_cloudbuild_worker_pool" "pool" {
  project = var.project_id

  name     = "${google_compute_network.vpc.name}-pool-eu"
  location = "europe-west1"

  network_config {
    peered_network = google_compute_network.vpc.id
  }

  depends_on = [google_service_networking_connection.vpc_service_networking]
}

resource "google_sourcerepo_repository" "demo" {
  project = var.project_id

  name = "demo-${random_id.id.hex}"
}

resource "google_cloudbuild_trigger" "demo" {
  project = var.project_id

  name        = "${google_sourcerepo_repository.demo.name}-ci"
  description = "Example pipeline to transitively connect to GKE."

  trigger_template {
    project_id  = var.project_id
    repo_name   = google_sourcerepo_repository.demo.name
    branch_name = ".*"
  }

  filename = "cloudbuild.yaml"
}

resource "local_file" "demo_init_script" {
  filename = "${path.module}/demo/repo_init.sh"
  content = templatefile(
    "${path.module}/resources/repo_init.sh.tftpl",
    {
      project_id = var.project_id
      repo_name  = google_sourcerepo_repository.demo.name
  })
}

resource "local_file" "demo_trigger_script" {
  filename = "${path.module}/demo/repo_trigger.sh"
  content = templatefile(
    "${path.module}/resources/repo_trigger.sh.tftpl",
    {
      project_id = var.project_id
      repo_name  = google_sourcerepo_repository.demo.name
      worker_pool_location = google_cloudbuild_worker_pool.pool.location
  })
}

resource "local_file" "demo_cloudbuild_yaml" {
  filename = "${path.module}/demo/cloudbuild.yaml"
  content = templatefile(
    "${path.module}/resources/cloudbuild.yaml.tftpl",
    {
      project_id       = var.project_id
      cluster_name     = google_container_cluster.cluster1.name
      cluster_location = google_container_cluster.cluster1.location
      worker_pool_id   = google_cloudbuild_worker_pool.pool.id
  })
}