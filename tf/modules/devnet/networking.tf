
resource "aws_vpc" "devnet" {
  cidr_block       = var.devnet_vpc_block
  instance_tenancy = "default"

  tags = {
    Name        = "devnet"
    Provisioner = data.aws_caller_identity.provisioner.account_id
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.devnet.id

  tags = {
    Name        = "igw"
    Provisioner = data.aws_caller_identity.provisioner.account_id
  }
}


resource "aws_subnet" "devnet_public" {
  vpc_id                  = aws_vpc.devnet.id
  count                   = length(var.zones)
  availability_zone       = element(var.zones, count.index)
  cidr_block              = element(var.devnet_public_subnet, count.index)
  map_public_ip_on_launch = true

  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name        = "public-subnet"
    Provisioner = data.aws_caller_identity.provisioner.account_id
  }
}


resource "aws_route_table" "devnet_public" {
  vpc_id = aws_vpc.devnet.id

  tags = {
    Name        = "public_route_table"
    Provisioner = data.aws_caller_identity.provisioner.account_id
  }
}

# Route for Internet Gateway
resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.devnet_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# Route table associations
resource "aws_route_table_association" "public" {
  count          = length(var.zones)
  subnet_id      = element(aws_subnet.devnet_public, count.index).id
  route_table_id = aws_route_table.devnet_public.id
}

