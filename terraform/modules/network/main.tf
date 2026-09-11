resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
  }
}

#we are creating 3 subnets 1 for rds and its rds subgroups,1 for glue ENI,and 1 for for redshift i guess


resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-${var.environment}-private-${count.index + 1}"
  }
}


#create our own implicit routing table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-${var.environment}-private-rt"
  }
}

#associate our 3 subnet with that routing table

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

#s3 route that we are creating for our glue eni to reach outside the private subnet
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.private.id
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-s3-endpoint"
  }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.us-east-1.dynamodb"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.private.id
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-dynamodb-endpoint"
  }
}

#this is just the security group,we have not attached any ingress or egress rule till now
resource "aws_security_group" "glue" {
  name        = "${var.project_name}-${var.environment}-glue-sg"
  description = "Security group for AWS Glue ENIs"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-${var.environment}-glue-sg"
  }
}

#glue self referencing rule,glue eni needs permission to reference itself,
resource "aws_vpc_security_group_ingress_rule" "glue_self" {
  security_group_id = aws_security_group.glue.id

  referenced_security_group_id = aws_security_group.glue.id

  ip_protocol = "tcp"
  from_port   = 0
  to_port     = 65535

  description = "Allow Glue components to communicate with each other"
}
#the outbound rule for the glue,if a route exist i will not block the access 
resource "aws_vpc_security_group_egress_rule" "glue_all_outbound" {
  security_group_id = aws_security_group.glue.id

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"

  description = "Allow outbound traffic from Glue"
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-${var.environment}-rds-sg"
  description = "Security group for private MySQL RDS"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-sg"
  }
}
#glue wants to reach mysql,so we add the ingress rule to the rds sg 
resource "aws_vpc_security_group_ingress_rule" "rds_from_glue" {
  security_group_id = aws_security_group.rds.id

  referenced_security_group_id = aws_security_group.glue.id

  ip_protocol = "tcp"
  from_port   = 3306
  to_port     = 3306

  description = "Allow MySQL access from AWS Glue"
}
resource "aws_vpc_security_group_egress_rule" "rds_all_outbound" {
  security_group_id = aws_security_group.rds.id

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"

  description = "Allow outbound traffic from RDS"
}
/*
REDSHIFT NETWORKING CURRENTLY DISABLED
resource "aws_security_group" "redshift" {
  name        = "${var.project_name}-${var.environment}-redshift-sg"
  description = "Security group for Redshift Serverless"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-${var.environment}-redshift-sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "redshift_all_outbound" {
  security_group_id = aws_security_group.redshift.id

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"

  description = "Allow outbound traffic from Redshift"
}
resource "aws_vpc_security_group_ingress_rule" "redshift_from_local" {
  security_group_id = aws_security_group.redshift.id

  cidr_ipv4   = var.redshift_allowed_cidr
  ip_protocol = "tcp"
  from_port   = 5439
  to_port     = 5439

  description = "Allow Redshift access from local dbt client"
}

resource "aws_subnet" "redshift_public" {
  count = length(var.redshift_public_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.redshift_public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-${var.environment}-redshift-public-${count.index + 1}"
  }
}


resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-${var.environment}-igw"
  }
}

resource "aws_route_table" "redshift_public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-${var.environment}-redshift-public-rt"
  }
}

resource "aws_route" "redshift_internet" {
  route_table_id         = aws_route_table.redshift_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "redshift_public" {
  count = length(aws_subnet.redshift_public)

  subnet_id      = aws_subnet.redshift_public[count.index].id
  route_table_id = aws_route_table.redshift_public.id
}
*/


/*
At this exact stage, our network code represents:

VPC 10.0.0.0/16
│
├── Private subnet 1 10.0.1.0/24 ─┐
├── Private subnet 2 10.0.2.0/24 ─┼─→ Private Route Table
└── Private subnet 3 10.0.3.0/24 ─┘
                                      │
                                      └── 10.0.0.0/16 → local
                                          (AWS adds this automatically)



So Terraform creates:

VPC
10.0.0.0/16

├── subnet private[0]
│   10.0.1.0/24
│   us-east-1a
│
├── subnet private[1]
│   10.0.2.0/24
│   us-east-1b
│
└── subnet private[2]
    10.0.3.0/24
    us-east-1c
What is this?
*/