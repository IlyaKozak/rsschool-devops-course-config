data "aws_ebs_volume" "jenkins_volume" {
  filter {
    name   = "tag:Name"
    values = ["jenkins"]
  }
}

locals {
  grafana_dashboard_json = file("grafana-dashboard-model.json")
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

      # add prometheus-community repo
      "sudo helm repo add prometheus-community https://prometheus-community.github.io/helm-charts",

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

      # install prometheus node-exporter to k8s
      "sudo -E helm upgrade --install -n node-exporter --create-namespace node-exporter prometheus-community/prometheus-node-exporter",
      # install prometheus kube-state-metrics to k8s
      "sudo -E helm upgrade --install -n kube-state-metrics --create-namespace kube-state-metrics prometheus-community/kube-state-metrics",

      # install prometheus to k8s
      "sudo -E helm upgrade --install -n prometheus --create-namespace prometheus oci://registry-1.docker.io/bitnamicharts/prometheus \\",
      # with node-exporter dynamic service discovery
      "--set server.extraScrapeConfigs[0].job_name=node-exporter \\",
      "--set server.extraScrapeConfigs[0].kubernetes_sd_configs[0].role=endpoints \\",
      "--set server.extraScrapeConfigs[0].relabel_configs[0].source_labels[0]=__meta_kubernetes_service_name \\",
      "--set server.extraScrapeConfigs[0].relabel_configs[0].regex=node-exporter-prometheus-node-exporter \\",
      "--set server.extraScrapeConfigs[0].relabel_configs[0].action=keep \\",
      # with kube-state-metrics static scrape target
      "--set server.extraScrapeConfigs[1].job_name=kube-state-metrics \\",
      "--set server.extraScrapeConfigs[1].static_configs[0].targets[0]=kube-state-metrics.kube-state-metrics.svc.cluster.local:8080",

      # grafana namespace
      "sudo kubectl create namespace grafana",

      # grafana secret
      "sudo kubectl create secret generic -n grafana grafana-admin-secret \\",
      "--from-literal=admin=admin \\",
      "--from-literal=password=${var.grafana_password}",

      # download grafana dashboard
      "sudo curl -o /tmp/grafana-dashboard-model.json ${var.grafana.dashboard_url}",
      # create configmap for grafana dashboard
      "sudo kubectl create configmap grafana-dashboard-model --from-file=/tmp/grafana-dashboard-model.json -n grafana",

      # download grafana alert rules and contact points config
      "sudo curl -o /tmp/alert_rules_contact_points.yaml ${var.grafana.alert_rules_contact_points_url}",
      "sudo sed -i 's/xxx@xxx.xxx/${var.smtp.to}/g' /tmp/alert_rules_contact_points.yaml",
      # create configmap for grafana alert rules and contact points
      "sudo kubectl apply -f /tmp/alert_rules_contact_points.yaml",

      # install grafana to k8s
      "sudo -E helm upgrade --install -n grafana --create-namespace grafana oci://registry-1.docker.io/bitnamicharts/grafana \\",
      "--set ingress.enabled=true \\",
      "--set ingress.hostname=grafana.${var.domain} \\",
      "--set ingress.annotations.\"traefik\\.ingress\\.kubernetes\\.io/router\\.entrypoints\"=web \\",
      # prometheus data source
      "--set datasources.secretDefinition.apiVersion=1 \\",
      "--set datasources.secretDefinition.datasources[0].name=Prometheus \\",
      "--set datasources.secretDefinition.datasources[0].type=prometheus \\",
      "--set datasources.secretDefinition.datasources[0].url=http://prometheus-server.prometheus.svc.cluster.local \\",
      "--set datasources.secretDefinition.datasources[0].access=proxy \\",
      "--set datasources.secretDefinition.datasources[0].isDefault=true \\",
      # grafana secret
      "--set admin.existingSecret=grafana-admin-secret \\",
      # grafana dashboard setup
      "--set dashboardsProvider.enabled=true \\",
      "--set dashboardsConfigMaps[0].configMapName=grafana-dashboard-model \\",
      "--set dashboardsConfigMaps[0].fileName=grafana-dashboard-model.json \\",
      # grafana smtp
      "--set smtp.enabled=true \\",
      "--set smtp.host=${var.smtp.host} \\",
      "--set smtp.user=${var.smtp.user} \\",
      "--set smtp.password=${var.smtp.password} \\",
      "--set smtp.fromAddress=${var.smtp.from} \\",
      "--set smtp.fromName=\"Grafana Alerts\" \\",
      "--set smtp.skipVerify=true \\",
      "--set alerting.configMapName=grafana-contact-points-alert-rules",
    ]
  }
}