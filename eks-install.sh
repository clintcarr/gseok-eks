#!/bin/bash

# EKS variables
CLUSTER_NAME="qsek8s"
REGION="ap-southeast-2"
NODES_MIN=3
NODES_MAX=3
ZONES="ap-southeast-2a,ap-southeast-2b,ap-southeast-2c"
FILE_SYSTEM_TOKEN="qsek8s"

#Create the cluster
eksctl create cluster --name $CLUSTER_NAME \
    --nodes-min=$NODES_MIN \
    --nodes-max=$NODES_MAX \
    --region=$REGION \
    --zones=$ZONES

kubectl create -f ./files/rbac-config.yaml

helm init --upgrade --service-account tiller --wait

# Get the IAM role associated to the NodeGroup
NODE_ROLE=$(aws iam list-roles | jq '.[] | .[] | .RoleName' --raw-output | grep nodegroup)

echo **Setting the NODE_ROLE to $NODE_ROLE**

# Use the Node role to attach the policy
echo **Setting IAM policy**
aws iam attach-role-policy --role-name $NODE_ROLE --policy-arn arn:aws:iam::aws:policy/AmazonElasticFileSystemReadOnlyAccess

# Create the file system
echo **Creating efs filesystem**
aws efs create-file-system --creation-token $FILE_SYSTEM_TOKEN --region $REGION

# Get the file system ID
FILE_SYSTEM_ID=$(aws efs describe-file-systems --region $REGION |  jq '.[] | .[] | .FileSystemId' --raw-output)
echo **Setting FILE_SYSTEM_ID to $FILE_SYSTEM_ID***
while [ "$STATE" != "available" ]; do echo $STATE; sleep 5s; STATE=$(aws efs describe-file-systems --region $REGION |  jq '.[] | .[] | .LifeCycleState' --raw-output); done
# Get the subnets associated to the cluster
SUBNETS=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION | jq '.[] | .resourcesVpcConfig |.subnetIds' --raw-output)
echo **The following SUBNETS are used $SUBNETS**
# Get the security group associated to the cluster
SEC_GROUP=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION | jq '.[] | .resourcesVpcConfig | .securityGroupIds' --raw-output | tr -d '[],"')
echo **The following Security Group is used $SEC_GROUP**

# Loop through the subnets and mount the file system
for i in $(echo $SUBNETS | tr -d '[],"'); 
do 
    aws efs create-mount-target --file-system-id $FILE_SYSTEM_ID \
        --subnet-id  $i \
        --security-group $SEC_GROUP \
        --region $REGION;
done

# Set the control plane and node group security groups to allow NFS between them
CONTROL_SEC_G=$(aws ec2 describe-security-groups --region $REGION --filters Name=group-name,Values=*ControlPlaneSecurityGroup* | jq '.[] | .[] | .GroupId' --raw-output)
NODEGROUP_SEC_G=$(aws ec2 describe-security-groups --region $REGION --filters Name=group-name,Values=*nodegroup* | jq '.[] | .[] | .GroupId' --raw-output)

# Allow NFS ingress
echo **Enabling NFS ingress**
aws ec2 authorize-security-group-ingress --group-id $CONTROL_SEC_G --protocol tcp --port 2049 --source-group $NODEGROUP_SEC_G --region $REGION
aws ec2 authorize-security-group-ingress --group-id $NODEGROUP_SEC_G --protocol tcp --port 2049 --source-group $CONTROL_SEC_G --region $REGION

# Install the efs-provisioner
echo **Installing EFS provisioner**
helm install --name efs stable/efs-provisioner \
        --set efsProvisioner.efsFileSystemId=$FILE_SYSTEM_ID,efsProvisioner.awsRegion=$REGION

# Add the qlik sense repo
echo **Adding Qlik stable repo**
helm repo add qlik https://qlik.bintray.com/stable

# # Install the pre-reqs
echo **Installing Qlik Sense init**
helm install --name qliksense-init qlik/qliksense-init

# # Install Qlik Sense
echo **Installing QSEoK**
helm upgrade --install qliksense qlik/qliksense -f ./files/values.yaml