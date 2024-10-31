# prepare ssh and k3s configs on local machine for kubectl
resource "local_file" "ssh_kube_config" {
  count      = var.is_local_setup ? 1 : 0
  depends_on = [null_resource.k3s_server]

  filename = pathexpand("~/.ssh/config")
  content = templatefile("ssh_config.tpl", {
    bastion_ip    = data.aws_eip.nat_instance.public_ip
    k3s_server_ip = data.aws_instance.k3s_server.private_ip
    ssh_key_file  = var.private_key_path
  })

  # scp k3s config from k3s server to local machine
  provisioner "local-exec" {
    connection {
      type         = "ssh"
      user         = "ec2-user"
      host         = data.aws_instance.k3s_server.private_ip
      bastion_host = data.aws_eip.nat_instance.public_ip
      private_key  = var.private_key
      timeout      = "1m"
    }

    on_failure  = continue

    command     = "scp k3s_server:/home/ec2-user/config config"
    interpreter = ["bash", "-c"]
  }

  # update k3s config for kubectl
  provisioner "local-exec" {
    on_failure  = continue

    command     = "sed -i s/127.0.0.1/${data.aws_instance.k3s_server.private_ip}/ config; sed -i '6i \\ \\ \\ \\ proxy-url: socks5://localhost:1080' config"
    interpreter = ["bash", "-c"]
  }

  # move k3s config to ~/.kube folder
  provisioner "local-exec" {
    on_failure  = continue

    command     = "mv config ~/.kube/config; chmod 600 ~/.kube/config"
    interpreter = ["bash", "-c"]
  }
}