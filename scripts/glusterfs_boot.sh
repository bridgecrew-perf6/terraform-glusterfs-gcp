#!/bin/bash

# Install Glusterfs server
apt update && apt upgrade -y
apt install -y wget gnupg parted

wget -O - https://download.gluster.org/pub/gluster/glusterfs/9/rsa.pub | apt-key add -

DEBID=$(grep 'VERSION_ID=' /etc/os-release | cut -d '=' -f 2 | tr -d '"')
DEBVER=$(grep 'VERSION=' /etc/os-release | grep -Eo '[a-z]+')
DEBARCH=$(dpkg --print-architecture)
echo deb https://download.gluster.org/pub/gluster/glusterfs/LATEST/Debian/$DEBID/$DEBARCH/apt $DEBVER main > /etc/apt/sources.list.d/gluster.list

apt update
apt install -y glusterfs-server

# Format attached disk as xfs and make it as a glusterfs brick
for i in {1..${disk_per_node}}
  do
  if [[ ! -d /data/gv0/brick$i ]]
  then
      echo "[gv0-${node_current}] Creating partition for brick $i"

      # we pick the attached device drive letter, as sdb sdc sdd etc. based on the
      # number of disks attached (disk_per_node)
      diskchar=`printf "\x$(printf %x $((97+i)))"`

      device="/dev/sd$diskchar"

      parted $device mktable gpt
      parted $device mkpart primary xfs 0% 100%
      partprobe $device
      sleep 5
      mkfs.xfs -f -i size=512 "$device"1
      
      mkdir -p "/data/gv0/brick$i/"

      echo $device"1 /data/gv0/brick$i xfs defaults 1 2" >> /etc/fstab
      mount -a
  else
      echo "[gv0-${node_current}] Partition for brick $i already exists"
  fi
done

# Start the glusterfs daemon
glusterd

# First node will execute admin commands
if [ ${node_current} == 1 ]
then
  # This will peer new nodes to the cluster. we do it even if they are already paired 
  # To keep the logic as simple as possible
  for i in {2..${node_count}}
  do
      echo "[gv0-${node_current}] Peering $i.${node_domain}"
      until gluster peer probe $i.${node_domain}; do sleep 1; done
  done

  # The sleep here is necessary otherwise the volume will not be created on first run
  sleep 30

  # the order to declare the bricks in glusterfs must be
  # node 1 brick 1, node 2 brick 1, node 3 brick 1
  # node 1 brick 2, node 2 brick 2, node 3 brick 2
  # node 1 brick 3, node 2 brick 3, node 3 brick 3
  # etc. for HA setup (three-way replicated volume)
  BRICKLIST=""
  for d in {1..${disk_per_node}}
  do
      for i in {1..${node_count}}
      do
          BRICKLIST+="$i.${node_domain}:/data/gv0/brick$d/1 "
      done
  done

  # If the glusterfs volume was already created, we only do discovery/recovery operations
  if gluster volume status gv0
  then
      echo "[gv0-${node_current}] Volume already exists on primary, detecting new bricks"

      # We need to sleep to wait for this node to fully rejoin the cluster
      # If we dont, adding new bricks will fail
      sleep 30
      
      # This will list all the existing, declared bricks as lines node:/mount/point 
      existingBricks=`gluster volume status gv0 | egrep -o "[0-9]+.${node_domain}:.+/1"`
      # We then remove the existing bricks form our brick list, and add the new ones only
      # this will allow the cluster to scale up, and recover from failures
      newBricks=$BRICKLIST
      while IFS= read -r line; do
          newBricks=$${newBricks//$line/}
      done <<< "$existingBricks"

      if [[ -z "$${newBricks// }" ]]
      then
          echo "No new brick detected"
      else
          # The actual commands to add new bricks to an existing volume
          gluster volume add-brick gv0 replica ${gfs_replica_count} $newBricks
          # When adding new bricks, we want to rebalance the files on the cluster
          gluster volume rebalance gv0 start
      fi
  else
      # First time run (no volume detected) will create the initial volume
      echo "[gv0-${node_current}] Initializing volume"

      gluster volume create gv0 replica ${gfs_replica_count} $BRICKLIST

      # Sharding will spread data in the various bricks, enable it 
      # to improve performances if you are dealing with large files
      if [ ${gfs_shard_enabled} == true ]
      then
          echo "[gv0-${node_current}] Enabling sharding"
          gluster volume set gv0 features.shard enable
          gluster volume set gv0 features.shard-block-size ${gfs_shard_block_size_mb}MB
      fi


      gluster volume set gv0 performance.cache-size ${gfs_performance_cache_size_mb}MB

      # We finally start the initial volume, we need to do it only once
      gluster volume start gv0

      echo "[gv0-${node_current}] GlusterFS initialization done"
  fi
else
    echo "[gv0-${node_current}] Waiting for volume status on secondary"

    until gluster volume status gv0; do sleep 3; done
fi

# Just print the details of the volume, also to show that the node is healthy when it starts
gluster volume status gv0 detail
