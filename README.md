# terraform-glusterfs-gcp

A Three-way replicated volume deployment on GCP.

The default setting of this configuration will create a Glusterfs cluster with 3 nodes and 3 bricks spread to each node with a default replica count of 3. In Glusterfs terms, it will be a [Three-way Replicated Volume](https://access.redhat.com/documentation/en-us/red_hat_gluster_storage/3.1/html/administration_guide/sect-creating_replicated_volumes#Creating_Three-way_Replicated_Volumes).

Before running `terraform apply`, please check the `main.tf` file and the local variables to adapt it to your needs (especially the storage disk type and size).

This deployment does not support scale-down and bricks removal at this moment.

# Adding more storage

There is 2 ways to scale the Glusterfs cluster up: 
  - adding more bricks by attaching more disks to the nodes
  - adding more nodes

When new bricks are added, the cluster will rebalance the files.

## Adding more bricks
To add more bricks, increase the `disk_per_node` local variable in the `main.tf`, add a new disk in the configuration (by uncommenting it), and attach it to the existing nodes.
Once applied, you can restart each node except the first one to trigger the disk formatting and mounting. Once they are all back up, restart the first node to add the new bricks into the existing volume.

## Adding more nodes
To add more nodes, simply increase the `node_count` local variable in the `main.tf` file and apply the configuration. After a short time and once all the nodes are up, restart the first node to add them as peers and create the new bricks.

Refer to the Terraform files for additional comments on each option.

# Networking
The glusterfs deployment will be isolated into its own network and will not be exposed over internet.
Network peering might be required with the default setup. The network configuration can be changed in the `network.tf` file.
