#!/usr/bin/env bash

# This expects "jq" and the aws CLI to be installed. 

dt=$(date +%Y%m%d%H%M%S)
log_dir=create.${dt}.d

mkdir ${log_dir}

# Using the 172.28.128.16/28
# Allowing SSH and HTTPS in. 
# Network address 172.28.128.16
# Router is at .17
# DNS is at .18. 


# Create a vpc

echo "create VPC"
aws ec2 create-vpc  --cidr-block 172.28.128.0/24 2>&1 >> ${log_dir}/create-vpc
vpc_id=$(cat ${log_dir}/create-vpc | jq -r '.Vpc.VpcId') # -r removes the quotes.

echo "create SUBNET"
aws ec2 create-subnet --vpc-id ${vpc_id} --cidr-block 172.28.128.128/25 2>&1 >> ${log_dir}/create_subnet
sn_id=$(cat  ${log_dir}/create_subnet | jq -r '.Subnet.SubnetId')

echo "create GATEWAY"
aws ec2 create-internet-gateway 2>&1 >>  ${log_dir}/create-internet-gateway
IG_ID=$(cat ${log_dir}/create-internet-gateway | jq -r ".InternetGateway.InternetGatewayId")
echo "Gateway ID: ${IG_ID}"

echo "attach the gateway"

aws ec2 attach-internet-gateway --internet-gateway ${IG_ID} --vpc-id ${vpc_id}

echo "create security groups"
# Create me a security group associated with that VPC:
#
aws ec2 create-security-group --description 'For Gorrilla test'\
    --group-name 'GorillaLogicSG'\
    --vpc-id ${vpc_id} 2>&1 >>  ${log_dir}/create-security-group

sg_id=$(cat ${log_dir}/create-security-group | jq -r '.GroupId')

echo "Set up ingress ${sg_id}"
# SSH: 
aws ec2 authorize-security-group-ingress --group-id ${sg_id} --protocol tcp --port 22 --cidr 184.96.0.0/16  2>&1 >> ${log_dir}/authorize-security-group-ingress
    # Centurylink likes to reallocate IPs sometimes.
echo "ssh"
# HTTPS:
echo "https"
aws ec2 authorize-security-group-ingress --group-id ${sg_id} --protocol tcp --port 443 --cidr 0.0.0.0/0 2>&1 >>  ${log_dir}/authorize-security-group-ingress
echo "http"
aws ec2 authorize-security-group-ingress --group-id ${sg_id} --protocol tcp --port 80 --cidr 0.0.0.0/0 2>&1 >>   ${log_dir}/authorize-security-group-ingress
echo "create_route_table"

aws ec2 create-route-table --vpc-id ${vpc_id} 2>&1 >>  ${log_dir}/create-route-table

rt_id=$(cat ${log_dir}/create-route-table  | jq -r '.RouteTable.RouteTableId')
echo "create route--route table id: ${rt_id}"
aws ec2 create-route --route-table-id ${rt_id} --destination-cidr-block 0.0.0.0/0 --gateway-id ${IG_ID} 2>&1 >>  ${log_dir}/create_route_table2

echo "associate route:"
aws ec2 associate-route-table --subnet-id ${sn_id} --route-table-id ${rt_id} 2>&1  >>  ${log_dir}/associate_route_table

# ami-007e9fbe81cfbf4fa is 200~ami-ubuntu-18.04-1.16.2-00-1571834140

echo "Create One Instance:" 
aws ec2 run-instances --image-id ami-007e9fbe81cfbf4fa --count 1 --instance-type t2.micro --key-name GorillaTest --security-group-ids ${sg_id} --subnet-id ${sn_id} --associate-public-ip-address 2>&1 | tee -a  ${log_dir}/run_instances

i_id=$(cat ${log_dir}/run_instances | jq -r '.Instances | .[0].InstanceId')

done=1

while [[ ${done} -eq 1 ]];
do
    echo "Waiting 10 seconds to try to get the public IP."
    sleep 10
    aws ec2 describe-instances --instance-ids ${i_id} > ${log_dir}/public_ip_check
    public_ip=$(cat ${log_dir}/public_ip_check |  jq -r '.Reservations | .[0].Instances | .[0].PublicIpAddress')
    echo "Access via $public_ip"
    if [[ ${public_ip} != 'null' ]];
    then
        done=0
    fi
done

echo "Waiting for Instance Status to be 'ok' Go get \${DRINK_OF_CHOICE}"
sleep 30
status=''
while ![ ${status} == 'ok' ];
do
    status=$(aws ec2 describe-instance-status --instance-id ${i_id} | jq -r '.InstanceStatuses | .[0].InstanceStatus.Status')
    echo "Status: $status "
    sleep 10
done
echo ''

echo "Starting SSH configurations: Instance ID: ${i_id}, IP=${public_ip}"

ssh_log=${dt}.ssh_log

ssh -o StrictHostKeyChecking=accept-new -i GorillaTest.pem ubuntu@${public_ip} "hostname" | tee -a ${ssh_log}
ssh -i GorillaTest.pem ubuntu@${public_ip} "sleep 10; sudo apt update 2>&1 " | tee -a ${ssh_log}
ssh -i GorillaTest.pem ubuntu@${public_ip} sudo apt -y upgrade 2>&1 | tee -a ${ssh_log}
ssh -i GorillaTest.pem ubuntu@${public_ip} git clone https://github.com/petrocc/application.git 2>&1 | tee -a ${ssh_log}
ssh -i GorillaTest.pem ubuntu@${public_ip} git clone https://github.com/petrocc/GorillaTest.git 2>&1 | tee -a ${ssh_log}
ssh -i GorillaTest.pem ubuntu@${public_ip} "sudo wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.35.1/install.sh | bash 2>&1" | tee -a ${ssh_log}
ssh -i GorillaTest.pem ubuntu@${public_ip} "nvm install 6" 2>&1 | tee -a ${ssh_log}

echo -e "Instance ID=${i_id}\nIP=${public_ip}" | tee last_instance
