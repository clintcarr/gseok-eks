# Qlik Sense Enterprise on Kubernetes - EKS
This repo deploys QSEoK in EKS using a basic shell script.

# Pre-requisites
1. eksctl (https://github.com/weaveworks/eksctl)
2. awscli (https://aws.amazon.com/cli/)
3. AWS account
4. AWS configured for awscli (https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html)

# What is created
1. VPC
2. 3+ Nodes (depending on variables)
3. IAM policy
4. Subnets
5. networks
6. NAT gateway
7. Load Balancer
8. EKS Cluster
9. Cloud Formation Template

# What needs to be done
1. Clean-up of this


