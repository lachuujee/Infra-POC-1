############################################
# Availability Zones (fallback to first 2)
############################################
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # If azs provided, assume at least two; else take first two from region
  az0 = var.azs != null ? var.azs[0] : data.aws_availability_zones.available.names[0]
  az1 = var.azs != null ? var.azs[1] : data.aws_availability_zones.available.names[1]
}

############################################
# Addressing choice: IPAM > CIDR > default
############################################
locals {
  use_ipam    = var.ipam_pool_id != null
  cidr_final  = var.cidr_block != null ? var.cidr_block : "10.0.0.0/16"
  netmask_len = var.vpc_netmask_length != null ? var.vpc_netmask_length : 16
}

############################################
# VPC: IPAM if provided; else CIDR/default
############################################
resource "aws_vpc" "this" {
  ipv4_ipam_pool_id   = local.use_ipam ? var.ipam_pool_id : null
  ipv4_netmask_length = local.use_ipam ? local.netmask_len : null
  cidr_block          = local.use_ipam ? null : local.cidr_final

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-vpc"
    Service = "VPC"
  })
}

############################################
# CIDR planning
# - 6 private /23 subnets (≈512 IPs)
# - 2 public /28 subnets (≈16 IPs)
############################################
locals {
  private_cidrs = [
    cidrsubnet(aws_vpc.this.cidr_block, 3, 0),
    cidrsubnet(aws_vpc.this.cidr_block, 3, 1),
    cidrsubnet(aws_vpc.this.cidr_block, 3, 2),
    cidrsubnet(aws_vpc.this.cidr_block, 3, 3),
    cidrsubnet(aws_vpc.this.cidr_block, 3, 4),
    cidrsubnet(aws_vpc.this.cidr_block, 3, 5)
  ]

  public_parent = cidrsubnet(aws_vpc.this.cidr_block, 4, 15) # a /24 at the end
  public_cidrs  = [
    cidrsubnet(local.public_parent, 4, 0), # /28
    cidrsubnet(local.public_parent, 4, 1)  # /28
  ]

  private_def = {
    "app-a" = { cidr = local.private_cidrs[0], az = local.az0, role = "app" }
    "app-b" = { cidr = local.private_cidrs[1], az = local.az1, role = "app" }
    "api-a" = { cidr = local.private_cidrs[2], az = local.az0, role = "api" }
    "api-b" = { cidr = local.private_cidrs[3], az = local.az1, role = "api" }
    "db-a"  = { cidr = local.private_cidrs[4], az = local.az0, role = "db"  }
    "db-b"  = { cidr = local.private_cidrs[5], az = local.az1, role = "db"  }
  }
}

############################################
# Internet Gateway
############################################
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-igw"
    Service = "InternetGateway"
  })
}

############################################
# Public subnets (2) — /28
############################################
resource "aws_subnet" "public" {
  for_each = {
    "a" = { cidr = local.public_cidrs[0], az = local.az0 }
    "b" = { cidr = local.public_cidrs[1], az = local.az1 }
  }

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-public-${each.key}"
    Service = "SubnetPublic"
  })
}

############################################
# EIP + NAT (1 NAT in public-a)
############################################
resource "aws_eip" "nat" {
  domain = "vpc"
  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-nat-eip"
    Service = "NATGateway"
  })
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public["a"].id
  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-nat"
    Service = "NATGateway"
  })
}

############################################
# Route tables
############################################
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-rtb-public"
    Service = "RouteTablePublic"
  })

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_assoc" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.this.id
  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-rtb-private-app"
    Service = "RouteTablePrivate"
  })
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

resource "aws_route_table" "private_api" {
  vpc_id = aws_vpc.this.id
  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-rtb-private-api"
    Service = "RouteTablePrivate"
  })
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.this.id
  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-rtb-private-db"
    Service = "RouteTablePrivate"
  })
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

############################################
# Private subnets (6) — /23 + associations
############################################
resource "aws_subnet" "private" {
  for_each = local.private_def

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-private-${each.value.role}-${substr(each.key, -1, 1)}"
    Role    = upper(each.value.role)
    Service = "SubnetPrivate"
  })
}

locals {
  rtb_by_role = {
    app = aws_route_table.private_app.id
    api = aws_route_table.private_api.id
    db  = aws_route_table.private_db.id
  }
}

resource "aws_route_table_association" "private_assoc" {
  for_each       = local.private_def
  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = local.rtb_by_role[each.value.role]
}

############################################
# NACL: inbound 443 only, outbound all
############################################
resource "aws_network_acl" "vpc_acl" {
  vpc_id = aws_vpc.this.id
  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-nacl"
    Service = "NACL"
  })
}

resource "aws_network_acl_rule" "ingress_https" {
  network_acl_id = aws_network_acl.vpc_acl.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "egress_all" {
  network_acl_id = aws_network_acl.vpc_acl.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 0
  to_port        = 0
}

resource "aws_network_acl_association" "assoc_public" {
  for_each       = aws_subnet.public
  network_acl_id = aws_network_acl.vpc_acl.id
  subnet_id      = each.value.id
}

resource "aws_network_acl_association" "assoc_private" {
  for_each       = aws_subnet.private
  network_acl_id = aws_network_acl.vpc_acl.id
  subnet_id      = each.value.id
}

############################################
# Flow Logs: role, policy, log group, flow log
############################################
data "aws_iam_policy_document" "flowlogs_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flowlogs_role" {
  name               = "${local.name_prefix}-vpc-flowlogs-role"
  assume_role_policy = data.aws_iam_policy_document.flowlogs_trust.json
  tags               = merge(local.common_tags, { Service = "FlowLogs" })
}

data "aws_iam_policy_document" "flowlogs_policy" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "flowlogs_role_policy" {
  name   = "${local.name_prefix}-vpc-flowlogs-policy"
  role   = aws_iam_role.flowlogs_role.id
  policy = data.aws_iam_policy_document.flowlogs_policy.json
}

resource "aws_cloudwatch_log_group" "flowlogs" {
  name              = "/vpc/flowlogs/${local.name_prefix}"
  retention_in_days = var.flow_logs_retention_days
  tags              = merge(local.common_tags, { Service = "FlowLogs" })
}

resource "aws_flow_log" "vpc" {
  vpc_id               = aws_vpc.this.id
  log_destination_type = "cloud-watch-logs"
  log_group_name       = aws_cloudwatch_log_group.flowlogs.name
  iam_role_arn         = aws_iam_role.flowlogs_role.arn
  traffic_type         = "ALL"
  tags                 = merge(local.common_tags, { Service = "FlowLogs" })
}
