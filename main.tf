# resource "aws_key_pair" "myclikey" {
#   key_name = "myclikey"
#   public_key = file("./myclikey.pem")
# }

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = "10.0.0.0/24"
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = "10.0.0.0/27"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private_subnet" {
  vpc_id     = aws_vpc.wordpress_vpc.id
  cidr_block = "10.0.0.32/27"
}

resource "aws_eip" "eip" {
  vpc = true
}

resource "aws_internet_gateway" "igateway" {
  vpc_id = aws_vpc.wordpress_vpc.id
}

resource "aws_nat_gateway" "natgateway" {
  subnet_id     = aws_subnet.private_subnet.id
  allocation_id = aws_eip.eip.id
}

resource "aws_route_table" "publicRT" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igateway.id
  }
}

resource "aws_route_table" "privateRT" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.natgateway.id
  }
}

resource "aws_route_table_association" "publicRTAssoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.publicRT.id
}

resource "aws_route_table_association" "privateRTAssoc" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.privateRT.id
}

resource "aws_security_group" "wordpress_sec" {
  vpc_id = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all HTTP on 80"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all egress on any port"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow ssh ingress"
  }
}

resource "aws_security_group" "bastion_sec" {
  vpc_id = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow ssh ingress"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all egress on any port"
  }
}

resource "aws_security_group" "mysql_sec" {
  vpc_id = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow TCP on 3306"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all egress on any port"
  }
}

resource "aws_instance" "wordpress_instance" {
  instance_type          = "t2.micro"
  key_name               = var.aws_access_key
  ami                    = var.aws_wp_ami
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.wordpress_sec.id]
}

resource "aws_instance" "bastion_instance" {
  ami                 = var.aws_bastion_ami
  key_name            = var.aws_access_key
  instance_type       = "t2.micro"
  subnet_id           = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.bastion_sec.id]
}

resource "aws_instance" "mysql_instance" {
  ami             = var.aws_bastion_ami
  key_name        = var.aws_access_key
  instance_type   = "t2.micro"
  subnet_id       = aws_subnet.private_subnet.id
  vpc_security_group_ids = [aws_security_group.bastion_sec.id, aws_security_group.mysql_sec.id]
  user_data       = file("./mysqlinit.sh")
}


resource "null_resource" "bastion_provisioners" {
  connection {
    port        = 22
    password    = ""
    user        = "ec2-user"
    private_key = file("./myclikey.pem")
    host        = aws_instance.bastion_instance.public_ip
  }

  provisioner "file" {
    source      = "./myclikey.pem"
    destination = "/tmp/myclikey.pem"
  }
}

resource "null_resource" "wp_provisioners" {
  connection {
    port        = 22
    password    = ""
    user        = "ec2-user"
    private_key = file("./myclikey.pem")
    host        = aws_instance.wordpress_instance.public_ip
  }

  provisioner "file" {
    source      = "./myclikey.pem"
    destination = "/tmp/myclikey.pem"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo chmod 400 /tmp/myclikey.pem",
      "sudo yum update -y",
      "sudo yum install -y docker",
      "sudo systemctl enable docker && sudo systemctl restart docker",
      "sudo docker run -d -p 80:80 -e WORDPRESS_DB_HOST=${aws_instance.mysql_instance.private_ip} -e WORDPRESS_DB_PASSWORD=root -e WORDPRESS_DB_NAME=wordpressdb wordpress"
    ]
  }
}
