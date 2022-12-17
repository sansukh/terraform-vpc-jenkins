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
# Creating instance
 resource "aws_instance" "server" {
  ami           = "ami-097a2df4ac947655f"
  instance_type = "t2.micro"
 # vpc_id =  aws_vpc.Main.id
  subnet_id = aws_subnet.publicsubnets.id

  tags = {
    Name = "assignment_4"
  }
}
