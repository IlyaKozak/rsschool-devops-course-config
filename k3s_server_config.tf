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
    }

    # setup JENKINS in k3s cluster
    inline = [
      # install k3s
      "curl -sfL https://get.k3s.io | K3S_TOKEN=${var.k3s_token} sudo sh -s -",
      # prepare k3s kubeconfig to copy it locally
      "sudo cp -v /etc/rancher/k3s/k3s.yaml /home/ec2-user/config",
      "sudo chmod 666 /home/ec2-user/config",

      # install helm
      "curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3",
      "sudo chmod 700 get_helm.sh",
      "sudo ./get_helm.sh",

      # add jenkins repo
      "sudo helm repo add jenkins https://charts.jenkins.io",

      # add aws-ebs-csi-driver repo
      "sudo helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver",
      "sudo helm repo update",

      "until sudo kubectl get nodes | grep -q NAME; do",
      "sleep 10",
      "done",

      # install aws-ebs-csi-driver
      "sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm install aws-ebs-csi-driver --namespace kube-system aws-ebs-csi-driver/aws-ebs-csi-driver",

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
      "EOF",

      # create jenkins namespace
      "sudo kubectl create namespace jenkins",

      # create jenkins persistent volume claim
      "cat <<EOF | sudo kubectl apply -f -",
      "apiVersion: v1",
      "kind: PersistentVolumeClaim",
      "metadata:",
      "  name: ${var.jenkins.pvc}",
      "  namespace: jenkins",
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

      # install jenkins to k8s with pv dynamically provisioned with default ebs storage class and 
      # exposed with NodePort service on node port
      "sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm install jenkins jenkins/jenkins --namespace jenkins \\",
      "--set persistence.existingClaim=${var.jenkins.pvc} --set controller.serviceType=NodePort --set controller.nodePort=${var.jenkins.nodeport}",
    ]
  }
}