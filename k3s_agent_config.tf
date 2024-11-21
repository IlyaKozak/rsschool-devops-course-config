# data "aws_instance" "k3s_agent" {
#   filter {
#     name   = "tag:Name"
#     values = ["k3s_agent"]
#   }

#   filter {
#     name   = "instance-state-name"
#     values = ["running"]
#   }
# }

# resource "null_resource" "k3s_agent" {
#   depends_on = [null_resource.k3s_server]

#   provisioner "remote-exec" {
#     connection {
#       type         = "ssh"
#       user         = "ec2-user"
#       host         = data.aws_instance.k3s_agent.private_ip
#       bastion_host = data.aws_eip.nat_instance.public_ip
#       private_key  = var.private_key
#       timeout      = "1m"
#     }

#     inline = [
#       # install k3s and connect to k3s cluster
#       "curl -sfL https://get.k3s.io | sudo K3S_URL=https://${data.aws_instance.k3s_server.private_ip}:6443 K3S_TOKEN=${var.k3s_token} sh -s -",
#     ]
#   }
# }