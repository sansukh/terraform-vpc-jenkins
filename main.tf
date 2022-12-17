 # Creating VPC here==============================================
 resource "aws_vpc" "Main" {                
   cidr_block       = var.main_vpc_cidr     # Defining the CIDR block use 10.0.0.0/24 for demo
   instance_tenancy = "default"
 }
 
 # Creating Internet Gateway============================================
 resource "aws_internet_gateway" "IGW" {    
    vpc_id =  aws_vpc.Main.id               # vpc_id will be generated after we create VPC
 }
 # Creating Public Subnets===========================================
 
 resource "aws_subnet" "publicsubnets" {   
   vpc_id =  aws_vpc.Main.id
   cidr_block = "${var.public_subnets}"        # CIDR block of public subnets
 }
 # Creating Private Subnets =============================================
                    
 resource "aws_subnet" "privatesubnets" {
   vpc_id =  aws_vpc.Main.id
   cidr_block = "${var.private_subnets}"          # CIDR block of private subnets
 }
 # Creating RT for Public Subnet=========================================
 
 resource "aws_route_table" "PublicRT" {    
    vpc_id =  aws_vpc.Main.id
         route {
    cidr_block = "0.0.0.0/0"               # Traffic from Public Subnet reaches Internet via Internet Gateway
    gateway_id = aws_internet_gateway.IGW.id
     }
 }
 # Creating RT for Private Subnet ====================================
 
 resource "aws_route_table" "PrivateRT" {    
   vpc_id = aws_vpc.Main.id
   route {
   cidr_block = "0.0.0.0/0"             # Traffic from Private Subnet reaches Internet via NAT Gateway
   nat_gateway_id = aws_nat_gateway.NATgw.id
   }
 }
 
 resource "aws_route_table_association" "PublicRTassociation" {
    subnet_id = aws_subnet.publicsubnets.id
    route_table_id = aws_route_table.PublicRT.id
 }
 
 resource "aws_route_table_association" "PrivateRTassociation" {
    subnet_id = aws_subnet.privatesubnets.id
    route_table_id = aws_route_table.PrivateRT.id
 }
# resource "aws_eip" "nateIP" {
#   vpc   = true
# }
# Creating the NAT Gateway using subnet_id and allocation_id
 resource "aws_nat_gateway" "NATgw" {
   connectivity_type = "private"
   subnet_id = aws_subnet.privatesubnets.id
 }

 # Configure Security Group
resource "aws_security_group" "Jenkins-SG" {
  name = "Jenkins SG"
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
# Add security group for EFS
resource "aws_security_group" "ingress-efs" {
  name   = "ingress-efs"
  vpc_id =  aws_vpc.Main.id

  ingress {

    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#Security group for ALB

resource "aws_security_group" "albSG" {
  name = "ALB-SG"

  # Allow inbound HTTP requests
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound requests
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_efs_file_system" "JenkinsEFS" {
  creation_token   = "Jenkins-EFS"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  encrypted        = "true"
  tags = {
    Name = "JenkinsHomeEFS"
  }
}

resource "aws_efs_mount_target" "efs-mt-jenkins" {
  count           = length(tolist(data.aws_subnet_ids.default.ids))
  file_system_id  = aws_efs_file_system.JenkinsEFS.id
  subnet_id       = element(tolist(data.aws_subnet_ids.default.ids), count.index)
  security_groups = [aws_security_group.ingress-efs.id]
}

output "efs_dns_name" {
  value = aws_efs_file_system.JenkinsEFS.dns_name
}

# Fetch the latest Ubuntu 18.04 version
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-18.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"]

}

# Create Jenkins server Launch configuration
resource "aws_launch_configuration" "jenkinslc" {
  name_prefix     = "aws_lc-"
  image_id        = data.aws_ami.ubuntu.id
  instance_type   = var.instance_type
  key_name        = var.ssh_key_name
  security_groups = [aws_security_group.Jenkins-SG.id]
  user_data       = <<-EOF
              #!/bin/bash
              sudo apt-get -y update
              sudo apt-get install -y unzip
              sudo apt-get install -y nfs-common
              sudo mkdir -p /var/lib/jenkins
              sudo adduser -m -d /var/lib/jenkins jenkins
              sudo groupadd jenkins
              sudo usermod -a -G jenkins jenkins
              sudo chown -R jenkins:jenkins /var/lib/jenkins
              while ! (sudo mount -t nfs4 -o vers=4.1 $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone).${aws_efs_file_system.JenkinsEFS.dns_name}:/ /var/lib/jenkins); do sleep 10; done
              # Edit fstab so EFS automatically loads on reboot
              while ! (echo ${aws_efs_file_system.JenkinsEFS.dns_name}:/ /var/lib/jenkins nfs defaults,vers=4.1 0 0 >> /etc/fstab) ; do sleep 10; done
              sudo apt-get -y install openjdk-11-jdk
              sudo wget -q -O - https://pkg.jenkins.io/debian-stable/jenkins.io.key | sudo apt-key add -
              echo "deb https://pkg.jenkins.io/debian-stable binary/" | sudo tee -a /etc/apt/sources.list
              sudo apt-get -y update
              sudo apt-get -y install jenkins
              EOF
}

# Create Autoscaling Group using the Launch Configuration jenkinslc
resource "aws_autoscaling_group" "jenkinsasg" {
  name                 = "jenkins_asg"
  launch_configuration = aws_launch_configuration.jenkinslc.name
  vpc_zone_identifier  = (tolist(data.aws_subnet_ids.default.ids))

  target_group_arns = [aws_lb_target_group.asg.arn]
  health_check_type = "ELB"
  min_size          = 1
  max_size          = 1

  tag {
    key                 = "Name"
    value               = "terraform-asg-jenkins"
    propagate_at_launch = true
  }

  # Create a new instance before deleting the old one
  lifecycle {
    create_before_destroy = true
  }
}

# Create an Application Load Balancer
resource "aws_lb" "jenkinsalb" {
  name               = "jenkins-alb"
  load_balancer_type = "application"
  internal           = false
  subnets            = data.aws_subnet_ids.default.ids
  security_groups    = [aws_security_group.albSG.id]

}
resource "aws_lb_target_group" "asg" {
  name     = "asg-TG"
  port     = var.jenkins_port
  protocol = "HTTP"
  vpc_id =  aws_vpc.Main.id

  # Configure Health Check for Target Group
  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "403"
    interval            = 15
    timeout             = 6
    healthy_threshold   = 3
    unhealthy_threshold = 10
  }
}

# Configure Listeners for ALB
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.jenkinsalb.arn
  port              = var.alb_port
  protocol          = "HTTP"

  # By default, return a simple 404 page
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}

# Provides Load balancer with a listener rule resource
resource "aws_lb_listener_rule" "asg" {
  # The ARN of the listener to which to attach the rule.
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  condition {
    # Optional - List of paths to match
    path_pattern {
      values = ["*"]
    }
  }

  action {
    # The type of routing action. 
    type             = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

# Output
output "alb_dns_name" {
  value       = aws_lb.jenkinsalb.dns_name
  description = "The domain name of the load balancer"
}
# # Creating instance
#  resource "aws_instance" "server" {
#   ami           = "ami-097a2df4ac947655f"
#   instance_type = "t2.micro"
#  # vpc_id =  aws_vpc.Main.id
#   subnet_id = aws_subnet.publicsubnets.id

#   tags = {
#     Name = "assignment_4"
#   }
# }


