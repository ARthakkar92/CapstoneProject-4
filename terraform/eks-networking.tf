# eks-networking.tf
# Extends the existing VPC with a secondary CIDR block for EKS,
# since the original 10.0.0.0/24 (built for Jenkins only) is too small.

locals {
  eks_cluster_name = "${var.project_name}-eks"
}

resource "aws_vpc_ipv4_cidr_block_association" "eks_secondary" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.1.0.0/16"
}

# --- Public subnets (for load balancers / NAT gateway) ---
resource "aws_subnet" "eks_public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.1.0.0/20"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  depends_on              = [aws_vpc_ipv4_cidr_block_association.eks_secondary]

  tags = {
    Name                                        = "${var.project_name}-eks-public-a"
    "kubernetes.io/cluster/${local.eks_cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }
}

resource "aws_subnet" "eks_public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.1.16.0/20"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true
  depends_on              = [aws_vpc_ipv4_cidr_block_association.eks_secondary]

  tags = {
    Name                                        = "${var.project_name}-eks-public-b"
    "kubernetes.io/cluster/${local.eks_cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }
}

# --- Private subnets (for EKS worker nodes) ---
resource "aws_subnet" "eks_private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.1.32.0/20"
  availability_zone = "${var.aws_region}a"
  depends_on        = [aws_vpc_ipv4_cidr_block_association.eks_secondary]

  tags = {
    Name                                        = "${var.project_name}-eks-private-a"
    "kubernetes.io/cluster/${local.eks_cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}

resource "aws_subnet" "eks_private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.1.48.0/20"
  availability_zone = "${var.aws_region}b"
  depends_on        = [aws_vpc_ipv4_cidr_block_association.eks_secondary]

  tags = {
    Name                                        = "${var.project_name}-eks-private-b"
    "kubernetes.io/cluster/${local.eks_cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}

# --- NAT Gateway (lets private subnets reach the internet) ---
resource "aws_eip" "eks_nat" {
  domain = "vpc"
  tags   = { Name = "${var.project_name}-eks-nat-eip" }
}

resource "aws_nat_gateway" "eks_nat" {
  allocation_id = aws_eip.eks_nat.id
  subnet_id     = aws_subnet.eks_public_a.id
  tags          = { Name = "${var.project_name}-eks-nat" }

  depends_on = [aws_internet_gateway.main]
}

# --- Route tables ---
resource "aws_route_table" "eks_public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.project_name}-eks-public-rt" }
}

resource "aws_route_table" "eks_private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.eks_nat.id
  }
  tags = { Name = "${var.project_name}-eks-private-rt" }
}

resource "aws_route_table_association" "eks_public_a" {
  subnet_id      = aws_subnet.eks_public_a.id
  route_table_id = aws_route_table.eks_public.id
}

resource "aws_route_table_association" "eks_public_b" {
  subnet_id      = aws_subnet.eks_public_b.id
  route_table_id = aws_route_table.eks_public.id
}

resource "aws_route_table_association" "eks_private_a" {
  subnet_id      = aws_subnet.eks_private_a.id
  route_table_id = aws_route_table.eks_private.id
}

resource "aws_route_table_association" "eks_private_b" {
  subnet_id      = aws_subnet.eks_private_b.id
  route_table_id = aws_route_table.eks_private.id
}
