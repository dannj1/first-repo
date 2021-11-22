#!/bin/bash
ssh_sg=sg-00738fdcb3e687b25
default_sg=sg-0623896a1ef7c1f5c
mnhttp_sg=sg-0eb44f4a46bd469da
amz_linux_ami=ami-02e136e904f3da870

aws ec2 run-instances --image-id $amz_linux_ami  --count 1 --instance-type t2.micro --key-name mainkey \
--region us-east-1 --security-group-ids $ssh_sg $default_sg $http_sg \
--user-data file://~/project/userdatascript.txt \
--tag-specifications 'ResourceType=instance,Tags=[{Key=Name, Value=myec2v1}]'

instance_id=` aws ec2 describe-instances --query Reservations[*].Instances[*].InstanceId \
              --filter Name=tag:Name,Values=myec2v1 --output text | cut -c 1- `

sleep 60
aws ec2 create-image --instance-id $instance_id --name "myAMIv1" --description "AMI for Project"   
sleep 180    

ami_id=` aws ec2 describe-images --filters "Name=name, Values=myAMIv1" --query 'Images[*].[ImageId]' \
                                  --output text `

aws ec2 run-instances --image-id $ami_id --count 1 --instance-type t2.micro --key-name mainkey \
--region us-east-1 --security-group-ids $ssh_sg $default_sg $http_sg \
--tag-specifications 'ResourceType=instance,Tags=[{Key=Name, Value=nginxec2}]'

sleep 15
nginx_ec2_ip=` aws ec2 describe-instances --query "Reservations[*].Instances[*].PublicIpAddress" \
                                            --filter Name=tag:Name,Values=nginxec2 --output text `

ssh -i ~/mainkey.pem ec2-user@$nginx_ec2_ip -y 'bash -s' << 'ENDSSH'
    cd /usr/share/nginx/html
    cat index.html
    ls
    image="alexabuy.jpg"
    if [[ $image == *"alexabuy"* ]]; then
        echo "Content is there!"
    else
        echo "It's not there"
    fi


ENDSSH

aws ec2 copy-image --source-image-id $ami_id --source-region us-east-1 \
                   --region us-east-2 --name "CopiedNGINXAmi"

copied_ami_id=` aws ec2 describe-images --filters "Name=name, Values=CopiedNGINXAmi" \
                --query 'Images[*].[ImageId]' --output text --region us-east-2`

aws ec2 run-instances --image-id $copied_ami_id --count 1 --instance-type t2.micro --key-name mainkey \
                      --region us-east-2 --security-group-ids sg-01c6943dae22b63ff sg-d3798d99 sg-0e93190e3bd4d50e9

ssh -i ~/mainkey.pem ec2-user@$nginx_ec2_ip -y 'bash -s' << 'ENDSSH'
    free -m > mem_text.txt 
    cat mem_text.txt
    sudo init 0
ENDSSH
sleep 60

scale_id=`aws ec2 describe-instances --query Reservations[*].Instances[*].InstanceId | jq .[-1] \
                   | cut -c 4-22 `

aws ec2 modify-instance-attribute \
    --instance-id $scale_id \
    --instance-type "{\"Value\": \"m1.small\"}"

aws ec2 start-instances --instance-ids $scale_id
sleep 60

scale_ip=` aws ec2 describe-instances --query "Reservations[*].Instances[*].PublicIpAddress" \
                                            --filter Name=tag:Name,Values=nginxec2 --output text `

ssh -i ~/mainkey.pem ec2-user@$scale_ip -y 'bash -s' << 'ENDSSH'
    free -m > mem_text.txt
    cat mem_text.txt
ENDSSH