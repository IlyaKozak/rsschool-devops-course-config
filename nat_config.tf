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

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

resource "null_resource" "nat_instance" {
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ec2-user"
      host        = data.aws_eip.nat_instance.public_ip
      private_key = var.private_key
      timeout     = "1m"
    }

    inline = [
      # configure NAT
      "sudo dnf install iptables-services -qy",
      "sudo systemctl enable --now iptables",
      "echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.d/custom-ip-forwarding.conf",
      "sudo sysctl -p /etc/sysctl.d/custom-ip-forwarding.conf",
      "sudo /sbin/iptables -t nat -A POSTROUTING -o $(ip -br l | awk '$1 !~ /(lo|vir|wl)/ { print $1}') -j MASQUERADE",
      "sudo /sbin/iptables -F FORWARD",
      "sudo /sbin/iptables -F INPUT",
      "sudo service iptables save",

      # install nginx
      "sudo dnf install nginx nginx-mod-stream -qy",
      "sudo systemctl enable --now nginx",

      # move ssl certificate and key to /etc/ssl/certs/ folder
      "echo \"${var.ssl_cert}\" | sudo tee /etc/ssl/certs/domain.cert.pem",
      "echo \"${var.ssl_key}\" | sudo tee /etc/ssl/certs/private.key.pem",

      # nginx config to forward traffik to traefik
      "cat <<EOF > nginx.conf",
      "include /usr/share/nginx/modules/*.conf;",
      "events {",
      "    worker_connections 1024;",
      "}",
      "stream {",
      "    upstream traefik_http_backend {",
      "        server ${data.aws_instance.k3s_server.private_ip}:${var.traefik_nodeport};",
      "    }",
      "    server {",
      "        listen 443 ssl;",
      "        proxy_pass traefik_http_backend;",
      "        proxy_protocol on;",
      "        ssl_certificate /etc/ssl/certs/domain.cert.pem;",
      "        ssl_certificate_key /etc/ssl/certs/private.key.pem;",
      "    }",
      "}",
      "EOF",

      "sudo mv nginx.conf /etc/nginx/nginx.conf",
      "sudo nginx -t",
      "sudo systemctl reload nginx",
    ]
  }
}