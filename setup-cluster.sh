#!/bin/bash

set -e

function cleanup {
  echo "Something went wrong. Cleaning everything up"
  if [ -z "$IMAGE_ID" ]; then
     glance image-delete --name=$IMAGE_NAME
  fi
  if [ -z "$CLUSTER_TEMPLATE_ID" ]; then
     sahara cluster-template-delete --name=$CLUSTER_TEMPLATE_NAME
  fi
  if [ -z "$MASTER_GROUP_ID" ]; then
     sahara node-group-template-delete --name=$MASTER_NODE_NAME
  fi
  if [ -z "$WORKER_GROUP_ID" ]; then
     sahara node-group-template-delete --name=$WORKER_NODE_NAME
  fi
}

trap cleanup 0

source setup-env.sh

IMAGE_NAME="sahara-kilo-vanilla-2.6-ubuntu-14.04.qcow2"
IMAGE_URL="http://sahara-files.mirantis.com/images/upstream/kilo/$IMAGE_NAME"


# Setup image
wget -nc $IMAGE_URL
IMAGE_ID=`glance image-create --name=$IMAGE_NAME --disk-format=qcow2 --container-format=bare < ./$IMAGE_NAME | awk '/id/ {print $4}'`

sahara image-register --id $IMAGE_ID --username $OS_USERNAME

echo "VAI CARAI CRIA AS TAGS!"
sleep 30

# FIXME: calling curl due a bug in python-saharaclient
AUTH_TOKEN=`keystone token-get | awk '/ id/ {print $4}'`
TENANT_ID=`keystone token-get | awk '/tenant_id/ {print $4}'`
# curl -si -H "X-Auth-Token:$AUTH_TOKEN" -d image-tags.json $OS_DATA_PROCESSING_URL/$TENANT_ID/images/$IMAGE_ID/tag

# Setup cluster
MASTER_NODE_NAME="test-master-node"
WORKER_NODE_NAME="test-worker-node"

sed -e "s/placeholder_name/$MASTER_NODE_NAME/" \
    ng_master_template_create.json_template > ng_master_template_create.json
sed -e "s/placeholder_name/$WORKER_NODE_NAME/" \
    ng_worker_template_create.json_template > ng_worker_template_create.json

MASTER_GROUP_ID=`sahara node-group-template-create --json ng_master_template_create.json | awk '/ id/ {print $4}'`
WORKER_GROUP_ID=`sahara node-group-template-create --json ng_worker_template_create.json | awk '/ id/ {print $4}'`

CLUSTER_TEMPLATE_NAME="test-cluster-template"

sed -e "s/placeholder_master_group_id/$MASTER_GROUP_ID/" \
    -e "s/placeholder_name/$CLUSTER_TEMPLATE_NAME/" \
    -e "s/placeholder_worker_group_id/$WORKER_GROUP_ID/"  \
    cluster_template_create.json_template > cluster_template_create.json

CLUSTER_TEMPLATE_ID=`sahara cluster-template-create --json cluster_template_create.json | awk '/ id/ {print $4}'`

# Generate keypair
KEYPAIR_NAME="cluster_keypair"
KEYPAIR_PATH="/tmp/$KEYPAIR_NAME"

if [ ! -f $KEYPAIR_PATH ]; then
  ssh-keygen -f $KEYPAIR_PATH -t rsa -N ""
  nova keypair-add $KEYPAIR_NAME --pub-key "$KEYPAIR_PATH".pub
fi

# Launch cluster
sed -e "s/placeholder_cluster_template_id/$CLUSTER_TEMPLATE_ID/" \
    -e "s/placeholder_keypair_name/$KEYPAIR_NAME/" \
    -e "s/placeholder_image_id/$IMAGE_ID/" \
    cluster_create.json_template > cluster_create.json

# sahara cluster-create --json cluster_create.json
