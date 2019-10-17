#!/bin/bash

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
export PATH=$PATH
export AWS_DEFAULT_REGION="`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/[[:lower:]]$//g'`"

# Setting AWS Configure
if [ -d "$HOME/.aws" ]; then
  echo "`date "+%F %H:%M:%S"` - $HOME/.aws is exists"
else
  echo "`date "+%F %H:%M:%S"` - Create $HOME/.aws"
  aws configure set role_arn ${ROLE_ARN}
  aws configure set credential_source Ec2InstanceMetadata
  aws configure set region ${AWS_DEFAULT_REGION}
  aws configure set output table
fi

# Get NAT Instance Information
Instance_ID="`curl -s http://169.254.169.254/latest/meta-data/instance-id`"
Route_Table_ID="`aws ec2 describe-route-tables \
  --filters "Name=tag:Name,Values=Private Route" \
  --query "RouteTables[*].{RouteTables:RouteTableId}" \
  --output text`"

NAT_EIP_Allocation_ID="`aws ec2 describe-addresses \
  --filters "Name=tag:Name,Values=Public NAT VIP" \
  --query "Addresses[*].AllocationId" \
  --output text`"

NAT_EIP_Association_ID="`aws ec2 describe-addresses \
  --filters "Name=tag:Name,Values=Public NAT VIP" \
  --query "Addresses[*].AssociationId" \
  --output text`"

SourceDestCheck="`aws ec2 describe-network-interfaces \
  --filters "Name=attachment.instance-id,Values=${Instance_ID}" \
  --query "NetworkInterfaces[*].{DescribeNetworkInterfaces:SourceDestCheck}" \
  --output text`"

# Check NAT EIP Exists
NAT_EIP_STATUS="`aws ec2 describe-addresses --filters "Name=allocation-id,Values=${NAT_EIP_Allocation_ID}" | wc -l | sed 's/ //g'`"

if [ "${NAT_EIP_STATUS}" == "3" ]; then
  echo "`date "+%F %H:%M:%S"` - NAT EIP not exists"
  echo "`date "+%F %H:%M:%S"` - NAT_EIP_Allocation_ID=${NAT_EIP_Allocation_ID}"
  exit 2
fi

# Check Private Route Table Exists
ROUTE_TABLE_STATUS="`aws ec2 describe-route-tables --filters "Name=route-table-id,Values=${Route_Table_ID}" | wc -l | sed 's/ //g'`"

if [ "${ROUTE_TABLE_STATUS}" == "3" ]; then
  echo "`date "+%F %H:%M:%S"` - Route Table not exists"
  echo "`date "+%F %H:%M:%S"` - Route_Table_ID=${Route_Table_ID}"
  exit 2
fi

# Disable Network SourceDestCheck
if [ "${SourceDestCheck}" == "True" ]; then
  echo "`date "+%F %H:%M:%S"` - Disable Network SourceDestCheck false"
  aws ec2 modify-instance-attribute --instance-id ${Instance_ID} --source-dest-check "{\"Value\": false}" --region ${AWS_DEFAULT_REGION}
fi

# Disassocite NAT VIP of EC2 Instance
if [ -n "${NAT_EIP_Association_ID}" ]; then
  echo "`date "+%F %H:%M:%S"` - Disassociate NAT VIP of EC2 Instance"
  aws ec2 disassociate-address --association-id ${NAT_EIP_Association_ID}
fi

# Associte NAT VIP of EC2 Instance
echo "`date "+%F %H:%M:%S"` - Associate NAT VIP of EC2 Instance"
aws ec2 associate-address --allocation-id ${NAT_EIP_Allocation_ID} --instance-id ${Instance_ID}

# Replace Private Route Table of EC2 Instance
echo "`date "+%F %H:%M:%S"` - Replace Routing"
aws ec2 replace-route --route-table-id ${Route_Table_ID} --destination-cidr-block 0.0.0.0/0 --instance-id ${Instance_ID}

echo "`date "+%F %H:%M:%S"` - Done"
