data "aws_instance" "nat_instance" {
  filter {
    name   = "tag:Name"
    values = ["nat_instance"]
  }

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

data "aws_eip" "nat_instance" {
  filter {
    name   = "tag:Name"
    values = ["nat_instance"]
  }
}

data "aws_instance" "k3s_server" {
  filter {
    name   = "tag:Name"
    values = ["k3s_server"]
  }
}

resource "null_resource" "nat_instance" {
  depends_on = [data.aws_instance.nat_instance, data.aws_eip.nat_instance]

  provisioner "remote-exec" {
    connection {
      host        = data.aws_eip.nat_instance.public_ip
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("~/.ssh/aws_jump_host.pem")
    }

    inline = [
      # setup NAT
      "sudo dnf install iptables-services -y",
      "sudo systemctl enable --now iptables",
      "echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.d/custom-ip-forwarding.conf",
      "sudo sysctl -p /etc/sysctl.d/custom-ip-forwarding.conf",
      "sudo /sbin/iptables -t nat -A POSTROUTING -o $(ip -br l | awk '$1 !~ /(lo|vir|wl)/ { print $1}') -j MASQUERADE",
      "sudo /sbin/iptables -F FORWARD",
      "sudo /sbin/iptables -F INPUT",
      "sudo service iptables save",

      # install nginx
      "sudo dnf install nginx -y",
      "sudo systemctl enable --now nginx",

      # install certbot for tls certificates
      "sudo dnf install certbot python3-certbot-nginx -y",

      # nginx config to proxy jenkins
      "cat <<EOF > jenkins-reverse-proxy.conf",
      "  location / {",
      "    proxy_pass http://${data.aws_instance.k3s_server.private_ip}:${var.jenkins.nodeport};",
      "    proxy_set_header Host \\$host;",
      "    proxy_set_header X-Real-IP \\$remote_addr;",
      "    proxy_set_header X-Forwarded-For \\$proxy_add_x_forwarded_for;",
      "    proxy_set_header X-Forwarded-Proto \\$scheme;",
      "    error_page 502 = @custom_502;",
      "  }",
      "  location @custom_502 {",
      "    default_type text/html;",
      "    return 502 \"<html><body><h1>Jenkins is loading ...</h1><em>Please wait and check back later ...</em></body></html>\";",
      "  }",
      "EOF",
      "sudo cp jenkins-reverse-proxy.conf /etc/nginx/default.d/jenkins-reverse-proxy.conf",
      "sudo sed -i 's/server_name  _;/server_name  ${var.domain} www.${var.domain};/' /etc/nginx/nginx.conf",

      # generate tls certificates with certbot
      "sudo certbot --nginx --agree-tos --register-unsafely-without-email -d ${var.domain} -d www.${var.domain}",
      "sudo nginx -t",
      "sudo systemctl reload nginx",
    ]
  }
}