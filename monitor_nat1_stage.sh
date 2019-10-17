#!/bin/bash

LOGFILE="/tmp/monitor_nat.log"
Instance_ID="`curl -s http://169.254.169.254/latest/meta-data/instance-id`"

# Get NAT1 Information
NAT_MASTER_ID="`aws ec2 describe-instances --filters 'Name=tag:Name,Values=NAT1' --query "Reservations[*].Instances[*].{Instance:InstanceId}"  --output text`"
NAT_MASTER_PRIVATE_IP="`aws ec2 describe-instances --filters 'Name=tag:Name,Values=NAT1' --query "Reservations[*].Instances[*].{PrivateIP:PrivateIpAddress}"  --output text`"

# Get Private Route Table ID
Route_Table_ID="`aws ec2 describe-route-tables \
  --filters "Name=tag:Name,Values=private" \
  --query "RouteTables[*].{RouteTables:RouteTableId}" \
  --output text`"

# Get NAT VIP Information
NAT_EIP_Allocation_ID="`aws ec2 describe-addresses \
  --filters "Name=tag:Name,Values=Public NAT VIP" \
  --query "Addresses[*].AllocationId" \
  --output text`"

NAT_EIP_Association_ID="`aws ec2 describe-addresses \
  --filters "Name=tag:Name,Values=Public NAT VIP" \
  --query "Addresses[*].AssociationId" \
  --output text`"


# Healthy Check
Num_Pings=3
Ping_Timeout=1
Wait_Between_Pings=2
Wait_for_Instance_Stop=60
Wait_for_Instance_Start=300

while [ . ]; do
  # Check health of other NAT instance
  pingresult=`ping -c ${Num_Pings} -W ${Ping_Timeout} ${NAT_MASTER_PRIVATE_IP} | grep time= | wc -l`
  # Check to see if any of the health checks succeeded, if not
  if [ "${pingresult}" == "0" ]; then
    # Set HEALTHY variables to unhealthy (0)
    ROUTE_HEALTHY=0
    NAT_HEALTHY=0
    STOPPING_NAT=0
    while [ "${NAT_HEALTHY}" == "0" ]; do
      # NAT instance is unhealthy, loop while we try to fix it
      if [ "${ROUTE_HEALTHY}" == "0" ]; then
        # Associte NAT VIP of EC2 Instance
        echo "`date "+%F %H:%M:%S"` - Associate NAT VIP of EC2 Instance" >> ${LOGFILE}
        aws ec2 associate-address --allocation-id ${NAT_EIP_Allocation_ID} --instance-id ${Instance_ID}
        # Replace Private Route Table of EC2 Instance
        echo "`date "+%F %H:%M:%S"` - Other NAT heartbeat failed, Replace Routing." >> ${LOGFILE}
        aws ec2 replace-route --route-table-id ${Route_Table_ID} --destination-cidr-block 0.0.0.0/0 --instance-id ${Instance_ID}
	ROUTE_HEALTHY=1
      fi


      NAT_STATE="`aws ec2 describe-instances --instance-ids ${NAT_MASTER_ID} --query "Reservations[*].Instances[*].State.Name" --output text`"

      if [ "${NAT_STATE}" == "stopped" ]; then
    	echo "`date "+%F %H:%M:%S"` -- Other NAT instance stopped, starting it back up" >> ${LOGFILE}
        aws ec2 start-instances --instance-ids ${NAT_MASTER_ID}
	NAT_HEALTHY=1
        sleep $Wait_for_Instance_Start
      else
	if [ "$STOPPING_NAT" == "0" ]; then
    	  echo "`date "+%F %H:%M:%S"` -- Other NAT instance ${NAT_STATE}, attempting to stop for reboot" >> ${LOGFILE}
    aws ec2 stop-instances --instance-ids ${NAT_MASTER_ID}
	  STOPPING_NAT=1
	fi
        sleep $Wait_for_Instance_Stop
      fi
    done
  else
    sleep $Wait_Between_Pings
  fi
done
