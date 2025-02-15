packer {
  required_plugins {
    proxmox = {
      version = "= 1.2.1"
      source  = "github.com/hashicorp/proxmox"
    }
    git = {
      version = ">= 0.4.2"
      source  = "github.com/ethanmdavidson/git"
    }
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

//  BLOCK: data
//  Defines the data sources.

data "git-repository" "cwd" {}

//  BLOCK: variable
//  The many variables defined for build.

variable "proxmox_host" {
    type = string
}

variable "proxmox_node" {
    type = string
}

variable "proxmox_user" {
    type = string
}

variable "proxmox_apikey" {
    type = string
}

variable "vlan_tag" {
    type = string
    default = ""
}

variable "ssh_user" {
    type = string
}

variable "ssh_private_key_file" {
    type = string
}  

variable "build_key" {
    type = string
}

locals {
  iso_path = "{{var.iso_path}}"
  data_source_content = {
    "/ks.cfg" = templatefile("${abspath(path.root)}/anaconda-ks.cfg", {
      ssh_user                 = var.ssh_user
      build_key                = var.build_key
      }
    )
  }
  data_source_command = "inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg"
}

source "proxmox-iso" "rhel-tpl" {

    proxmox_url = "https://${var.proxmox_host}:8006/api2/json"
    insecure_skip_tls_verify = true
    node = var.proxmox_node
    boot_iso {
      type = "scsi"
      iso_file = "local:iso/rhel-9.5-x86_64-dvd.iso"
      unmount = true
    }
    vm_name = "rhel-base-image"
    vm_id = 999
    username = var.proxmox_user
    token = var.proxmox_apikey
    os = "l26"
    bios = "ovmf"
    efi_config {
      efi_storage_pool  = "local-lvm"
      pre_enrolled_keys = false
      efi_format        = "raw"
      efi_type          = "4m"
    }
    qemu_agent = true
    tpm_config {
      tpm_version 	    = "v2.0"
      tpm_storage_pool  = "local-lvm"
    }
    cpu_type = "host"
    cores = "2"
    memory = "4096"
    scsi_controller = "virtio-scsi-pci"
    disks {
      type		          = "sata"
      disk_size         = "20G"
      storage_pool      = "local-lvm"
      format		        = "raw"
    }
    network_adapters {
      bridge            = "vmbr0"
      vlan_tag          = var.vlan_tag
      model             = "virtio"
    }
    communicator        = "ssh"
    ssh_username        = var.ssh_user
    ssh_private_key_file = var.ssh_private_key_file 
    ssh_timeout         = "30m"
    ssh_handshake_attempts = "100"
    boot_command        = ["<e><bs><down><down><down>", "<left>", "<spacebar>", "${local.data_source_command}", "<leftCtrlOn>x<leftCtrlOff>"]
    http_content        = local.data_source_content
}

build {
    sources = ["source.proxmox-iso.rhel-tpl"]

    provisioner "ansible" {
    user          = var.ssh_user
    playbook_file = "${path.cwd}/rhel-packer-config.yml"
    extra_arguments = [ "--scp-extra-args", "'-O'" ] # Added to include work around https://github.com/hashicorp/packer/issues/11783#issuecomment-1137052770
    ansible_env_vars = [
      "ANSIBLE_CONFIG=${path.cwd}/ansible.cfg",
      "ANSIBLE_PYTHON_INTERPRETER=/usr/bin/python3"
    ]
  }
}


