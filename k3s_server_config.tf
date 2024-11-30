data "aws_ebs_volume" "jenkins_volume" {
  filter {
    name   = "tag:Name"
    values = ["jenkins"]
  }
}

resource "null_resource" "k3s_server" {
  depends_on = [null_resource.nat_instance]

  provisioner "remote-exec" {
    connection {
      type         = "ssh"
      user         = "ec2-user"
      host         = data.aws_instance.k3s_server.private_ip
      bastion_host = data.aws_eip.nat_instance.public_ip
      private_key  = var.private_key
      timeout      = "1m"
    }
    # setup jenkins in k3s cluster with traefik ingresss
    inline = [
      # install k3s
      "curl -sfL https://get.k3s.io | sudo K3S_TOKEN=${var.k3s_token} sh -s -",
      # prepare k3s kubeconfig to copy it locally
      "sudo cp -v /etc/rancher/k3s/k3s.yaml /home/ec2-user/config",
      "sudo chmod 666 /home/ec2-user/config",

      # install helm
      "curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3",
      "sudo chmod 700 get_helm.sh",
      "sudo ./get_helm.sh",

      # configure traefik nodeports
      # https://docs.k3s.io/helm#customizing-packaged-components-with-helmchartconfig
      "sudo tee /var/lib/rancher/k3s/server/manifests/traefik-config.yaml > /dev/null <<EOF",
      "apiVersion: helm.cattle.io/v1",
      "kind: HelmChartConfig",
      "metadata:",
      "  name: traefik",
      "  namespace: kube-system",
      "spec:",
      "  valuesContent: |-",
      "    ports:",
      "      web:",
      "        nodePort: ${var.traefik_nodeport}",
      "        forwardedHeaders:",
      "          trustedIPs: [${data.aws_eip.nat_instance.public_ip}]",
      "          insecure: true",
      "        proxyProtocol:",
      "          trustedIPs: [${data.aws_eip.nat_instance.public_ip}]",
      "          insecure: true",
      "EOF",

      # add jenkins repo
      "sudo helm repo add jenkins https://charts.jenkins.io",

      # add bitnami repo
      "sudo helm repo add bitnami https://charts.bitnami.com/bitnami",

      # add aws-ebs-csi-driver repo
      "sudo helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver",

      # add sonarqube repo
      "sudo helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube",

      "sudo helm repo update",

      "until sudo kubectl get nodes | grep -q NAME; do",
      "sleep 10",
      "done",

      "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml",
      # install aws-ebs-csi-driver
      "sudo -E helm install aws-ebs-csi-driver --namespace kube-system aws-ebs-csi-driver/aws-ebs-csi-driver",

      # create jenkins persistent volume
      "cat <<EOF | sudo kubectl apply -f -",
      "apiVersion: v1",
      "kind: PersistentVolume",
      "metadata:",
      "  name: ${var.jenkins.pv}",
      "spec:",
      "  accessModes:",
      "  - ReadWriteOnce",
      "  capacity:",
      "    storage: ${var.jenkins.volume_size}",
      "  csi:",
      "    driver: ebs.csi.aws.com",
      "    volumeHandle: ${data.aws_ebs_volume.jenkins_volume.id}",
      "  nodeAffinity:",
      "    required:",
      "      nodeSelectorTerms:",
      "        - matchExpressions:",
      "            - key: topology.kubernetes.io/zone",
      "              operator: In",
      "              values:",
      "                - ${var.aws_az}",
      "EOF",

      # create jenkins namespace
      "sudo kubectl create namespace ${var.jenkins.namespace}",

      # create jenkins persistent volume claim
      "cat <<EOF | sudo kubectl apply -f -",
      "apiVersion: v1",
      "kind: PersistentVolumeClaim",
      "metadata:",
      "  name: ${var.jenkins.pvc}",
      "  namespace: ${var.jenkins.namespace}",
      "spec:",
      "  storageClassName: ''",
      "  volumeName: ${var.jenkins.pv}",
      "  accessModes:",
      "    - ReadWriteOnce",
      "  resources:",
      "    requests:",
      "      storage: ${var.jenkins.volume_size}",
      "EOF",

      # create ebs storage class for dynamic persistent volumes provisioning
      "cat <<EOF | sudo kubectl apply -f -",
      "apiVersion: storage.k8s.io/v1",
      "kind: StorageClass",
      "metadata:",
      "  name: ebs-sc",
      "provisioner: ebs.csi.aws.com",
      "volumeBindingMode: WaitForFirstConsumer",
      "EOF",

      # jenkins kubernetes plugin cluster access with RBAC
      # https://github.com/helm/charts/issues/1092
      "sudo kubectl create clusterrolebinding permissive-binding --clusterrole=cluster-admin --user=admin \\",
      "--user=kubelet --group=system:serviceaccounts",

      # install jenkins to k8s with pv statically provisioned ebs volume and expose it via traefik ingress
      "sudo -E helm upgrade --install -n jenkins jenkins jenkins/jenkins \\",
      "--set controller.ingress.enabled=true \\",
      "--set controller.ingress.hostName=jenkins.${var.domain} \\",
      "--set controller.ingress.annotations.\"traefik\\.ingress\\.kubernetes\\.io/router\\.entrypoints\"=web \\",
      "--set persistence.existingClaim=${var.jenkins.pvc} \\",
      "--set rbac.readSecrets=true",

      # install prometheus to k8s and expose it via traefik ingress
      "sudo -E helm upgrade --install -n prometheus --create-namespace prometheus oci://registry-1.docker.io/bitnamicharts/prometheus \\",
      "--set server.ingress.enabled=true \\",
      "--set server.ingress.hostname=prometheus.${var.domain} \\",
      "--set server.ingress.annotations.\"traefik\\.ingress\\.kubernetes\\.io/router\\.entrypoints\"=web \\",
    ]
  }
}