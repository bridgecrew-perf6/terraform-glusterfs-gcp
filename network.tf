
resource "google_compute_network" "glusterfs" {
  name                    = "glusterfs"
  auto_create_subnetworks = "false"
}

resource "google_compute_subnetwork" "glusterfs" {
  name          = "glusterfs-subnet"
  network       = google_compute_network.glusterfs.name
  ip_cidr_range = "12.1.0.0/16"
}

resource "google_compute_router" "glusterfs" {
  name    = "glusterfs"
  network = google_compute_network.glusterfs.id

  bgp {
    asn = 64514
  }
}

resource "google_compute_router_nat" "glusterfs" {
  name                               = "glusterfs"
  router                             = google_compute_router.glusterfs.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

resource "google_compute_firewall" "glusterfs-ssh" {
  name    = "glusterfs-firewall-ssh-allow"
  network = google_compute_network.glusterfs.name

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["22", "111", "24007", "24009-24108", "38465", "38466", "38468", "38469", "49152-49251"]
  }

  allow {
    protocol = "udp"
    ports    = ["111", "963"]
  }
}

resource "google_dns_managed_zone" "glusterfs" {
  name     = "glusterfs"
  dns_name = "${local.node_domain}."

  visibility = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.glusterfs.id
    }
  }
}

resource "google_dns_record_set" "glusterfs-" {
  count = local.node_count
  name  = "${count.index+1}.${google_dns_managed_zone.glusterfs.dns_name}"
  type  = "A"
  ttl   = 300

  managed_zone = google_dns_managed_zone.glusterfs.name

  rrdatas = [google_compute_instance.gluster_[count.index].network_interface.0.network_ip]
}