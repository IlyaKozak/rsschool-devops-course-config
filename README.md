## RS School AWS DevOps Course - Configuration

**Project Structure:**

```
├── .github
│   └── workflows
│       └── k3s.yml                         <- github actions workflow
├── .gitignore
├── main.tf
├── nat_config.tf                           <- NAT/Nginx config
├── k3s_server_config.tf                    <- k3s server config
├── k3s_agent_config.tf                     <- k3s agent config
├── backend.tf                              <- backend configuration
├── variables.tf                            <- input variables
├── grafana-alert-rules-contact-points.yaml <- grafana contact points / alert rules
├── grafana-dashboard-model.json            <- grafana dashboard
└── ...
```

<details open>
<summary><strong>Task 9 - Alertmanager Configuration and Verification</strong></summary>

- SMTP is configured for Grafana to send emails via Amazon SES (Simple Email Service):
  - In AWS SES SMTP credentials are created: `user` and `password`
  - In AWS SES `from address` and `to address` `identities` are verified
  - [`host:port`, `user`, `password`, `from address`](https://github.com/IlyaKozak/rsschool-devops-course-config/blob/task-9-alertmanager/k3s_server_config.tf#L203-L206), [`to address`](https://github.com/IlyaKozak/rsschool-devops-course-config/blob/task-9-alertmanager/grafana-alert-rules-contact-points.yaml#L14) are provided during Grafana Helm installation
- `Contact Points` are configured:
  - [1 - ConfigMap yaml file is provided](https://github.com/IlyaKozak/rsschool-devops-course-config/blob/task-9-alertmanager/grafana-alert-rules-contact-points.yaml#L8-L16)
  - [2 - ConfigMap is created](https://github.com/IlyaKozak/rsschool-devops-course-config/blob/task-9-alertmanager/k3s_server_config.tf#L177-L181)
  - [3 - Grafana is installed with provided ConfigMap as `alerting.configMapName`](https://github.com/IlyaKozak/rsschool-devops-course-config/blob/task-9-alertmanager/k3s_server_config.tf#L209)
- `Alert Rules` are configured for:
  - [High CPU utilization](https://github.com/IlyaKozak/rsschool-devops-course-config/blob/task-9-alertmanager/grafana-alert-rules-contact-points.yaml#L86-L144) on any node of the cluster
  - [Lack of RAM capacity](https://github.com/IlyaKozak/rsschool-devops-course-config/blob/task-9-alertmanager/grafana-alert-rules-contact-points.yaml#L27-L85) on any node of the cluster
  - [Emails are configured](https://github.com/IlyaKozak/rsschool-devops-course-config/blob/task-9-alertmanager/grafana-alert-rules-contact-points.yaml#L143-L144) for `firing` events
- `Alerts` are verified with simulated CPU and memory `stress` on a Kubernetes node using `stress-ng`
  - `stress-ng` is installed: `sudo dnf install stress-ng -y`
  - `stress` is done: `stress-ng --vm 2 --vm-bytes 1300M --timeout 300s`

For more details please see PR: https://github.com/IlyaKozak/rsschool-devops-course-config/pull/4

</details>

<details>
<summary><strong>Task 8 - Grafana Installation and Dashboard Creation</strong></summary>

- [Grafana is installed using the Helm chart by Bitnami](https://github.com/IlyaKozak/rsschool-devops-course-config/blob/task-8-grafana/k3s_server_config.tf#L177-L194)
- [Grafana deployment in Kubernetes is automated with GitHub Actions CI/CD workflow](https://github.com/IlyaKozak/rsschool-devops-course-config/actions/runs/12221605611/job/34090864262#step:7:467)
- [New data source pointing to the existing Prometheus installation is added](https://github.com/IlyaKozak/rsschool-devops-course-config/blob/task-8-grafana/k3s_server_config.tf#L182-L188)
- [Grafana dashboard is created with with basic metrics visualized, such as CPU and memory utilization, storage usage](https://github.com/IlyaKozak/rsschool-devops-course-config/blob/task-8-grafana/grafana-dashboard-model.json)

For more details please see PR: https://github.com/IlyaKozak/rsschool-devops-course-config/pull/3

</details>

<details>
<summary><strong>Task 7 - Prometheus Deployment on K8s</strong></summary>

- Prometheus is installed and running on the K8s cluster
- Installed prometheus `node-exporter` and `kube-state-metrics` jobs (exporters). `node-exporter` is dynamically discovered. `kube-state-metrics` is setup as a static scrape target https://github.com/IlyaKozak/rsschool-devops-course-config/blob/task-7-prometheus-deploy/k3s_server_config.tf#L143-L146
- Deployment is automated with [GitHub Actions CI/CD pipeline is created](https://github.com/IlyaKozak/rsschool-devops-course-config/actions/runs/12102954505/job/33744594616#step:7:411) https://github.com/IlyaKozak/rsschool-devops-course-config/blob/task-7-prometheus-deploy/k3s_server_config.tf#L148-L158
- Metrics can be checked via Prometheus web interface locally with `port-forwarding`
- Prometheus is collecting essential cluster-specific metrics, such as nodes' memory usage (memory, disk, cpu, ...)

For more details please see PR: https://github.com/IlyaKozak/rsschool-devops-course-config/pull/2

</details>

<details>
<summary><strong>Task 4 - Jenkins Installation and Configuration</strong></summary>

- k3s kubernetes cluster is istalled within GitHub Actions workflow
- Jenkins installed with Helm within GitHub Actions workflow
- Jenkins uses EBS volume as persisten storage
- Jenkins is accessible via Internet from private network through Nginx reverse proxy in NAT instance
- Jenkins `user` is created with restricted permissions as security measure

For more details please see PR: https://github.com/IlyaKozak/rsschool-devops-course-config/pull/1

**Diagram:**  
![Diagram](tasks-images/task-4-diagram.png)

</details>

<hr />

### Infractructure

Infrastructure configuration provided in this repo (IaC) **https://github.com/IlyaKozak/rsschool-devops-course-infra**

**Usage:**

In GitHub repo for GitHub Actions workflow to run with `workflow_dispatch` ➤ automatically `terraform apply` configuration for k3s/jenkins/prometheus/grafana/alertmanager:

- Add secrets:
  - `AWS_ROLE_TO_ASSUME`
  - `TF_VAR_K3S_TOKEN`
  - `TF_VAR_PRIVATE_KEY`
  - `TF_VAR_SSL_CERT`
  - `TF_VAR_SSL_KEY`
  - `TF_VAR_GRAFANA_PASSWORD`
  - `TF_VAR_SMTP`=`{"host":"email-smtp.<region>.amazonaws.com:587", "user":"xxx", "password":"xxx", "from":"xxx@xxx.xxx", "to":"xxx@xxx.xxx"}`
- Add Environment Variables:
  - `AWS_REGION`
  - `TF_VAR_DOMAIN`
  - `TF_VAR_IS_LOCAL_SETUP`=`false`
  - `TF_VAR_PRIVATE_KEY_PATH`
