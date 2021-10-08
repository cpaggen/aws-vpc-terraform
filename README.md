Simple AWS VPC and EC2 terraform
================================

Simple HCL code that creates a new VPC with 2 subnets (one per AZ).
Inside that VPC, a new route-table is created and a route to 0.0.0.0/0 pointing to a new IGW is added to that route-table. Both subnets get associated to the route table, and one free-tier EC2 instance is spun up per subnet with a public IP.


Input Variables
---------------

- `awsKey` - AWS API Key
- `awsSecret` - AWS API Secret

Outputs
-------

- `vpcId` - ID of new VPC
- `ec2-instance1-public-ip` - Public IP of instance 1
- `ec2-instance2-public-ip` - Public IP of instance 2

Authors
=======

cpaggen@gmail.com
