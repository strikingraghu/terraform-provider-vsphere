# Testing Infrastructure

Here is where we keep the code of testing infrastructure (i.e. real vSphere cluster to run tests against).
This is intended to run on a TeamCity agent in AWS.

## Prerequisites

- Obtain API token for Packet.net and put it in the [relevant ENV variable](https://www.terraform.io/docs/providers/packet/#auth_token)
- Register and/or login to the [VMware portal](https://my.vmware.com/web/vmware/login)
- Download [VMware OVF Tool for Linux 64-bit](https://my.vmware.com/group/vmware/details?downloadGroup=OVFTOOL410&productId=353)
- Download [VMware vCenter Server Appliance](https://my.vmware.com/group/vmware/details?downloadGroup=VC67U1B&productId=742&rPId=31320)
- Upload both to an automation-friendly location (such as [S3](https://aws.amazon.com/s3/) or [Wasabi](https://wasabi.com/))
  - Make sure the location of the data is close to the chosen Packet.net facility
  	(the VCSA ISO has around *4GB*, so downloading would take a long time with a slow connection), e.g.
    - Wasabi's `eu-central-1`/Amsterdam & Packet's `ams1`/Amsterdam
    - AWS S3 `eu-central-1`/Frankfurt & Packet's `fra2`/Frankfurt
- Create curl-able URLs - see examples below

## How

### Terraform Apply

```sh
export TF_VAR_ovftool_url=$(aws --profile=vmware s3 presign s3://hc-vmware-eu-central-1/vmware-ovftool/VMware-ovftool-4.3.0-7948156-lin.x86_64.bundle)
export TF_VAR_vcsa_iso_url=$(aws --profile=vmware s3 presign s3://hc-vmware-eu-central-1/vmware-vsphere/VMware-VCSA-all-6.7.0-11726888.iso)
terraform apply -var=facility=fra2 -var=plan=c1.xlarge.x86
```

Use `output`s to set environment variables accordingly:

```
export VSPHERE_USER=$(terraform output vsphere_user)
export VSPHERE_PASSWORD=$(terraform output vsphere_password)
export VSPHERE_SERVER=$(terraform output vsphere_endpoint)
export VSPHERE_ESXI_HOST=$(terraform output esxi_host)
export VSPHERE_ESXI_HOST2=$(terraform output esxi_host)
export VSPHERE_ESXI_HOST3=$(terraform output esxi_host)
export VSPHERE_ESXI_HOST4=$(terraform output esxi_host)
export VSPHERE_ESXI_HOST5=$(terraform output esxi_host)
export VSPHERE_ESXI_HOST6=$(terraform output esxi_host)
export VSPHERE_ESXI_HOST7=$(terraform output esxi_host)
export VSPHERE_ESXI_USER=$(terraform output esxi_user)
export VSPHERE_DNS=$(terraform output dns_servers)
export VSPHERE_ESXI_PASSWORD=$(terraform output esxi_password)
export VSPHERE_ESXI_SSL_CERT_THUMBPRINT=$(terraform output esxi_ssl_cert_thumbprint)
export VSPHERE_ALLOW_UNVERIFIED_SSL=1
export VSPHERE_DATACENTER=$(terraform output datacenter_name)
export VSPHERE_TEST_ESXI=1
export VSPHERE_PERSIST_SESSION=1
export VSPHERE_CLUSTER=$(terraform output cluster_name1)
export VSPHERE_CLUSTER2=$(terraform output cluster_name2)
export VSPHERE_EMPTY_CLUSTER=$(terraform output cluster_name3)
export VSPHERE_RESOURCE_POOL=$(terraform output resource_pool_name)
```

### TODO

```sh
VSPHERE_DC_FOLDER=$(govc datacenter.info -json Datacenter | jq -r .Datacenters[0].Parent.Value)
VSPHERE_LICENSE

# Storage
VSPHERE_ADAPTER_TYPE
VSPHERE_DATASTORE
VSPHERE_DATASTORE2
VSPHERE_DS_VMFS_DISK0
VSPHERE_DS_VMFS_DISK1
VSPHERE_DS_VMFS_DISK2
VSPHERE_FOLDER_V0_PATH
VSPHERE_NAS_HOST
VSPHERE_NFS_PATH
VSPHERE_NFS_PATH2
VSPHERE_VMFS_EXPECTED
VSPHERE_VMFS_REGEXP

# Network
VSPHERE_HOST_NIC0
VSPHERE_HOST_NIC1
VSPHERE_IPV4_ADDRESS
VSPHERE_IPV4_GATEWAY
VSPHERE_IPV4_PREFIX
VSPHERE_NETWORK_LABEL
VSPHERE_NETWORK_LABEL_DHCP
VSPHERE_NETWORK_LABEL_PXE

# Other
VSPHERE_ISO_DATASTORE
VSPHERE_ISO_FILE
VSPHERE_REST_SESSION_PATH
VSPHERE_TEMPLATE
VSPHERE_TEMPLATE_COREOS
VSPHERE_TEMPLATE_ISO_TRANSPORT
VSPHERE_TEMPLATE_WINDOWS
VSPHERE_USE_LINKED_CLONE
VSPHERE_VIM_SESSION_PATH
VSPHERE_VM_V1_PATH
```

### Acceptance Tests

Then run acceptance tests from the root of this repository:

```
make testacc TEST=./vsphere
```
