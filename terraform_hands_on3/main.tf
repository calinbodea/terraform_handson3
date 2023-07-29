# local variables
locals {
  public_subnets       = [aws_subnet.subnet["public_1a"].id, aws_subnet.subnet["public_1b"].id]
  public_instances_ids = aws_instance.instance.*.id
}


# create vpc 
resource "aws_vpc" "vpc" {
  cidr_block = var.cidr_block
  tags       = { Name = "${terraform.workspace}_vpc" }
}

# create subnets
resource "aws_subnet" "subnet" {
  for_each                = var.subnets
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = each.value[0]
  availability_zone       = each.value[1]
  map_public_ip_on_launch = startswith(each.key, "public") ? true : false
  tags = {
    Name = "${terraform.workspace}_${each.key}"
  }
}
# create internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags   = { Name = "${terraform.workspace}_igw" }
}

# create eip 

# create NAT gateway

# create public route table
resource "aws_route_table" "public_rtb" {
  vpc_id     = aws_vpc.vpc.id
  tags       = { Name = "${terraform.workspace}_public_rtb" }
  depends_on = [aws_internet_gateway.igw]
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

# associate public rtb with public subnets
resource "aws_route_table_association" "public_rtb_to_public_subnets" {
  count          = length(local.public_subnets)
  subnet_id      = local.public_subnets[count.index]
  route_table_id = aws_route_table.public_rtb.id
}

# create security group for the instances
resource "aws_security_group" "ec2_sg" {
  name   = "${terraform.workspace}-public"
  vpc_id = aws_vpc.vpc.id
  dynamic "ingress" {
    for_each = [22, 80]
    content {
      description = "allows inbound traffic on port: ${ingress.value}"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "TCP"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  egress {
    description = "allows outbound traffic on all ports "
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# data call for the ami
data "aws_ami" "amazon-linux-2" {
  most_recent = true
  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
}

# look up ssh key
data "aws_key_pair" "key_pair" {
  key_name = var.ssh_key_name
}

# create ec2 instances

resource "aws_instance" "instance" {
  count                  = length(local.public_subnets)
  ami                    = data.aws_ami.amazon-linux-2.id
  instance_type          = var.instance_type
  key_name               = data.aws_key_pair.key_pair.key_name
  subnet_id              = local.public_subnets[count.index]
  user_data              = file(var.user_data)
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  tags = {
    Name = "${terraform.workspace}_ec2_${local.public_subnets[count.index]}"
  }
}

# create target group
resource "aws_alb_target_group" "target-group" {
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id
  tags = {
    Name = "${terraform.workspace}-target-group"
  }
}

# associate public ec2 to target group
resource "aws_lb_target_group_attachment" "attachment" {
  count            = length(local.public_instances_ids)
  target_group_arn = aws_alb_target_group.target-group.arn
  target_id        = local.public_instances_ids[count.index]

}

# create security group for alb
resource "aws_security_group" "alb_sg" {
  name   = "${terraform.workspace}-alb-sec-group"
  vpc_id = aws_vpc.vpc.id

  dynamic "ingress" {
    for_each = [443, 80]
    content {
      description = "allows inbound traffic on port: ${ingress.value}"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "TCP"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  egress {
    description = "allows outbound traffic on all ports "
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# create acm SSL/TSL certificate
resource "aws_acm_certificate" "certificate" {
  domain_name       = "${terraform.workspace}.${data.aws_route53_zone.domain.name}"
  validation_method = "DNS"
  tags              = { Name = "${terraform.workspace}_certificate_${data.aws_route53_zone.domain.name}" }
}

# look up hosted name
data "aws_route53_zone" "domain" {
  name = "codepipelinehq.com"
}

# create route 53 records for the SSL?TSL certificate
resource "aws_route53_record" "domain_cert_dns_record" {
  name    = tolist(aws_acm_certificate.certificate.domain_validation_options)[0].resource_record_name
  records = [tolist(aws_acm_certificate.certificate.domain_validation_options)[0].resource_record_value]
  type    = tolist(aws_acm_certificate.certificate.domain_validation_options)[0].resource_record_type
  zone_id = data.aws_route53_zone.domain.zone_id
  ttl     = 60
}

# validate certificate
resource "aws_acm_certificate_validation" "domain_cert_validation" {
  certificate_arn         = aws_acm_certificate.certificate.arn
  validation_record_fqdns = [aws_route53_record.domain_cert_dns_record.fqdn]
}

# create the application load balancer
resource "aws_lb" "alb" {
  name               = "${terraform.workspace}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = local.public_subnets
  tags               = { Name = "${terraform.workspace}_alb" }
}

# create http listener

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# create https listener

resource "aws_lb_listener" "https_listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.certificate.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.target-group.arn
  }
}

# create DNS record
resource "aws_route53_record" "record" {
  zone_id = data.aws_route53_zone.domain.zone_id
  name    = "${terraform.workspace}.${data.aws_route53_zone.domain.name}"
  type    = "CNAME"
  ttl     = 60
  records = [aws_lb.alb.dns_name]
}
