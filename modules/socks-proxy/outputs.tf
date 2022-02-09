output "ip_address" {
    description = "IP address of proxy load balancer"
    value = google_compute_address.proxy.address
}