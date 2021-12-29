terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "3.78.0"
    }
  }

  required_version = "~> 1.0"
}

# Except for node_count, almost all of the values can't be changed once deployed
# For now if you need more storage just increase the node_count
# After being increased, restart the first node to add the new member
locals {
  # node_count must be multiple of gfs_replica_count
  # if the node count is changed, a restart from the first node is required to cluster
  # (or executing the start script again)
  node_count    = 3
  
  machine_type  = "n1-standard-1"

  disk_type     = "pd-standard"
  disk_size     = 256
  # if increasing the number of disks per node, the attachments
  # should be defined in the resource below
  # and the instances restarted after apply (restart the first node last) - or the start script executed
  # see commented disk sections below. if you increase to 3 disk per node, uncomment it
  disk_per_node = 1
  node_domain   = "gfs.internal"

  # glusterfs vars
  # sharding cause some issues with a lock ownership when setting up the cluster
  # glusterfs Lock owner mismatch.
  gfs_shard_enabled             = false
  gfs_shard_block_size_mb       = 16
  # gfs replica count 2 can cause split brains
  # should be a multiple of node_count
  gfs_replica_count             = 3
  gfs_performance_cache_size_mb = 256
}

resource "random_string" "user" {
  length           = 10
  special          = false
  number           = false
}

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}

data "google_compute_zones" "available" {}

resource "google_compute_disk" "gluster_disk_brick_1_" {
  count = local.node_count
  name  = "gluster-${count.index+1}-brick-1"
  type  = local.disk_type
  zone  = data.google_compute_zones.available.names[count.index % length(data.google_compute_zones.available.names)]
  size  = local.disk_size
}
# Uncomment to add a new disk to existing nodes
# resource "google_compute_disk" "gluster_disk_brick_2_" {
#   count = local.node_count
#   name  = "gluster-${count.index+1}-brick-2"
#   type  = local.disk_type
#   zone  = data.google_compute_zones.available.names[count.index % length(data.google_compute_zones.available.names)]
#   size  = local.disk_size
# }

resource "google_compute_instance" "gluster_" {
  depends_on   = [google_compute_router_nat.glusterfs]

  count        = local.node_count
  name         = "gluster-${count.index+1}"
  machine_type = local.machine_type
  tags         = ["allow-ssh"]
  zone         = data.google_compute_zones.available.names[count.index % length(data.google_compute_zones.available.names)]

  allow_stopping_for_update = true

  network_interface {
    network     = google_compute_network.glusterfs.id
    subnetwork  = google_compute_subnetwork.glusterfs.id
  }

  boot_disk {
    auto_delete = true
    initialize_params {
      image = "debian-11-bullseye-v20211209"
      type  = local.disk_type
    }
  }

  attached_disk {
    source = google_compute_disk.gluster_disk_brick_1_[count.index].self_link
  }
  # Uncomment when adding a new disk to existing nodes 
  # attached_disk {
  #   source = google_compute_disk.gluster_disk_brick_2_[count.index].self_link
  # }

  service_account {
    scopes = ["cloud-platform"]
  }

  metadata = {
    ssh-keys = "${random_string.user.result}:${tls_private_key.ssh_key.public_key_openssh}"
    startup-script = templatefile("${path.module}/scripts/glusterfs_boot.sh", {
        node_count                    = local.node_count
        node_current                  = count.index + 1
        node_domain                   = local.node_domain
        disk_per_node                 = local.disk_per_node
        gfs_shard_enabled             = local.gfs_shard_enabled
        gfs_shard_block_size_mb       = local.gfs_shard_block_size_mb
        gfs_replica_count             = local.gfs_replica_count
        gfs_performance_cache_size_mb = local.gfs_performance_cache_size_mb
    })
  }
}