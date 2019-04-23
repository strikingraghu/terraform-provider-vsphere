variable "plan" {
  default = "c1.xlarge.x86"
}

variable "esxi_version" {
  default = "6.5"

}

variable "govc_version" {
  default = "v0.20.0"
  description = "Version of govc (see https://github.com/vmware/govmomi/releases)"
}

variable "facility" {
  default = "ams1"
}

variable "dns_servers" {
  type = "list"
  default = ["8.8.8.8", "8.8.4.4"]
}

variable "ovftool_url" {
  description = "URL from which to download ovftool"
}
variable "vcsa_iso_url" {
  description = "URL from which to download VCSA ISO"
}

locals {
  esxi_ssl_cert_thumbprint_path = "ssl_cert_thumbprint.txt"
  vcsa_domain_name = "vsphere.local"
  govc_url = "https://github.com/vmware/govmomi/releases/download/${var.govc_version}/govc_linux_amd64.gz"
  datacenter_name = "TfDatacenter"
  cluster1_name = "TfCluster1"
  cluster2_name = "TfCluster2"
  cluster3_name = "TfCluster3"
  resource_pool_name = "TfPool"
}

provider "packet" {
}

resource "packet_project" "test" {
  name = "Terraform Acc Test vSphere"
}

data "packet_operating_system" "helper" {
  name             = "CentOS"
  distro           = "centos"
  version          = "7"
  provisionable_on = "t1.small.x86"
}

data "local_file" "esxi_thumbprint" {
  filename   = "${path.module}/${local.esxi_ssl_cert_thumbprint_path}"
  depends_on = ["packet_device.esxi"]
}

resource "random_string" "password" {
  length           = 16
  special          = true
  min_lower        = 1
  min_numeric      = 1
  min_upper        = 1
  min_special      = 1
  override_special = "@_"
}

data "template_file" "vcsa" {
  template = "${file("vcsa-template.json")}"
  vars = {
    esxi_host                = "${packet_device.esxi.access_public_ipv4}"
    esxi_username            = "root"
    esxi_password            = "${packet_device.esxi.root_password}"
    esxi_ssl_cert_thumbprint = "${chomp(data.local_file.esxi_thumbprint.content)}"
    ipv4_address             = "${cidrhost(format("%s/%s", packet_device.esxi.network.0.gateway, packet_device.esxi.public_ipv4_subnet_size), 3)}"
    ipv4_prefix              = "${packet_device.esxi.public_ipv4_subnet_size}"
    ipv4_gateway             = "${packet_device.esxi.network.0.gateway}"
    network_name             = "${cidrhost(format("%s/%s", packet_device.esxi.network.0.gateway, packet_device.esxi.public_ipv4_subnet_size), 3)}"
    domain_name              = "${local.vcsa_domain_name}"
    os_password              = "${random_string.password.result}"
    sso_password             = "${random_string.password.result}"
    dns_servers              = "\"${join("\",\"", var.dns_servers)}\""
  }
}

resource "local_file" "vcsa" {
  content  = "${data.template_file.vcsa.rendered}"
  filename = "${path.module}/template.json"
}

resource "tls_private_key" "test" {
  algorithm = "RSA"
}

resource "packet_project_ssh_key" "test" {
  name       = "tf-acc-test"
  public_key = "${tls_private_key.test.public_key_openssh}"
  project_id = "${packet_project.test.id}"
}


resource "packet_device" "helper" {
  hostname            = "tf-acc-vmware-helper"
  plan                = "t1.small.x86"
  facilities          = ["${var.facility}"]
  operating_system    = "${data.packet_operating_system.helper.id}"
  billing_cycle       = "hourly"
  project_id          = "${packet_project.test.id}"
  project_ssh_key_ids = ["${packet_project_ssh_key.test.id}"]

  provisioner "file" {
    connection {
      type        = "ssh"
      host        = "${self.access_public_ipv4}"
      user        = "root"
      private_key = "${tls_private_key.test.private_key_pem}"
      agent       = false
    }

    source      = "./install-vcsa.sh"
    destination = "/tmp/install-vcsa.sh"
  }

  provisioner "file" {
    connection {
      type        = "ssh"
      host        = "${self.access_public_ipv4}"
      user        = "root"
      private_key = "${tls_private_key.test.private_key_pem}"
      agent       = false
    }

    source      = "${local_file.vcsa.filename}"
    destination = "/tmp/vcsa-template.json"
  }

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      host        = "${self.access_public_ipv4}"
      user        = "root"
      private_key = "${tls_private_key.test.private_key_pem}"
      agent       = false
    }

    inline = [
      <<SCRIPT
set -e
export OVFTOOL_URL="${var.ovftool_url}"
export VCSA_ISO_URL="${var.vcsa_iso_url}"
export VCSA_TPL_PATH=/tmp/vcsa-template.json

echo "Installing vCenter Server Appliance..."
chmod a+x /tmp/install-vcsa.sh
/tmp/install-vcsa.sh

echo "Installing govc..."
curl -f -L ${local.govc_url} -o /tmp/govc_linux_amd64.gz
gunzip /tmp/govc_linux_amd64.gz
mv /tmp/govc_linux_amd64 ./govc
chmod a+x ./govc
./govc version

echo "Attempting to login via govc..."
export GOVC_USERNAME="Administrator@${local.vcsa_domain_name}"
export GOVC_PASSWORD="${random_string.password.result}"
export GOVC_URL=${cidrhost(format("%s/%s", packet_device.esxi.network.0.gateway, packet_device.esxi.public_ipv4_subnet_size), 3)}
export GOVC_INSECURE=1
./govc about

echo "Creating datacenter..."
./govc datacenter.create ${local.datacenter_name}

echo "Adding ESXi as host to the datacenter..."
./govc host.add -hostname ${packet_device.esxi.access_public_ipv4} -username root -password "${packet_device.esxi.root_password}" -thumbprint ${chomp(data.local_file.esxi_thumbprint.content)}

echo "Creating clusters..."
./govc cluster.create ${local.cluster1_name}
./govc cluster.create ${local.cluster2_name}
./govc cluster.create ${local.cluster3_name}

echo "Creating resource pool..."
./govc pool.create /${local.datacenter_name}/host/${packet_device.esxi.access_public_ipv4}/Resources/${local.resource_pool_name}
SCRIPT
    ]
  }
}

resource "packet_vlan" "mgmt" {
  description = "vsphere-mgmt"
  facility    = "${var.facility}"
  project_id  = "${packet_project.test.id}"
}
resource "packet_port_vlan_attachment" "mgmt" {
  device_id = "${packet_device.esxi.id}"
  vlan_vnid = "${packet_vlan.mgmt.vxlan}"
  port_name = "eth1"
}

resource "packet_vlan" "nested-mgmt" {
  description = "vsphere-nested-mgmt"
  facility    = "${var.facility}"
  project_id  = "${packet_project.test.id}"
}
resource "packet_port_vlan_attachment" "nested-mgmt" {
  device_id = "${packet_device.esxi.id}"
  vlan_vnid = "${packet_vlan.nested-mgmt.vxlan}"
  port_name = "eth0"
}

resource "packet_vlan" "public1" {
  description = "vsphere-public1"
  facility    = "${var.facility}"
  project_id  = "${packet_project.test.id}"
}
resource "packet_port_vlan_attachment" "public1" {
  device_id = "${packet_device.esxi.id}"
  vlan_vnid = "${packet_vlan.public1.vxlan}"
  port_name = "eth0"
}
resource "packet_vlan" "public2" {
  description = "vsphere-public2"
  facility    = "${var.facility}"
  project_id  = "${packet_project.test.id}"
}
resource "packet_port_vlan_attachment" "public2" {
  device_id = "${packet_device.esxi.id}"
  vlan_vnid = "${packet_vlan.public2.vxlan}"
  port_name = "eth0"
}
resource "packet_vlan" "public3" {
  description = "vsphere-public3"
  facility    = "${var.facility}"
  project_id  = "${packet_project.test.id}"
}
resource "packet_port_vlan_attachment" "public3" {
  device_id = "${packet_device.esxi.id}"
  vlan_vnid = "${packet_vlan.public3.vxlan}"
  port_name = "eth0"
}
resource "packet_vlan" "nsxt-public" {
  description = "vsphere-nsxt-public"
  facility    = "${var.facility}"
  project_id  = "${packet_project.test.id}"
}
resource "packet_port_vlan_attachment" "nsxt-public" {
  device_id = "${packet_device.esxi.id}"
  vlan_vnid = "${packet_vlan.nsxt-public.vxlan}"
  port_name = "eth0"
}

data "packet_operating_system" "esxi" {
  name = "VMware ESXi"
  distro = "vmware"
  version = "${var.esxi_version}"
  provisionable_on = "${var.plan}"
}

resource "packet_device" "esxi" {
  hostname = "tf-acc-vmware-esxi"
  plan = "${var.plan}"
  facilities = ["${var.facility}"]
  operating_system = "${data.packet_operating_system.esxi.id}"
  billing_cycle = "hourly"
  project_id = "${packet_project.test.id}"
  project_ssh_key_ids = ["${packet_project_ssh_key.test.id}"]
  network_type = "layer2-individual"

  provisioner "remote-exec" {
    connection {
      type = "ssh"
      host = "${self.access_public_ipv4}"
      user = "root"
      private_key = "${tls_private_key.test.private_key_pem}"
      agent = false
      timeout = "10m"
    }

    inline = [
      "openssl x509 -in /etc/vmware/ssl/rui.crt -fingerprint -sha1 -noout | awk -F= '{print $2}' > /tmp/ssl-rui-thumbprint.txt"
    ]
  }

  provisioner "local-exec" {
    environment = {
      SSH_PRIV_KEY = "${tls_private_key.test.private_key_pem}"
      FROM = "root@${self.access_public_ipv4}:/tmp/ssl-rui-thumbprint.txt"
      TO = "${local.esxi_ssl_cert_thumbprint_path}"
    }
    command = "./scp.sh"
  }
}

output "esxi_host" {
  value = "${packet_device.esxi.access_public_ipv4}"
}

output "esxi_user" {
  value = "root"
}

output "esxi_password" {
  value = "${packet_device.esxi.root_password}"
}

output "esxi_ssl_cert_thumbprint" {
  value = "${chomp(data.local_file.esxi_thumbprint.content)}"
}

output "vsphere_endpoint" {
  value = "${cidrhost(format("%s/%s", packet_device.esxi.network.0.gateway, packet_device.esxi.public_ipv4_subnet_size), 3)}"
}

output "vsphere_user" {
  value = "Administrator@${local.vcsa_domain_name}"
}

output "vsphere_password" {
  value = "${random_string.password.result}"
}

output "dns_servers" {
  value = "${join(",", var.dns_servers)}"
}

output "datacenter_name" {
  value = "${local.datacenter_name}"
}

output "cluster1_name" {
  value = "${local.cluster1_name}"
}

output "cluster2_name" {
  value = "${local.cluster2_name}"
}

output "cluster3_name" {
  value = "${local.cluster3_name}"
}

output "resource_pool_name" {
  value = "${local.resource_pool_name}"
}
