output vpc_id {
    value = aws_vpc.Main.id
}

output subnetpublic_id {
    value = aws_subnet.publicsubnets.id
}

output privatesubnets {
    value = aws_subnet.privatesubnets.id
}

output igw_id {
    value = aws_internet_gateway.IGW.id
}

output PublicRT_id {
    value = aws_route_table.PublicRT.id
}
output PrivateRT_id {
    value = aws_route_table.PrivateRT.id
}
output "instance_id" {
    value = aws_instance.server.id
}
