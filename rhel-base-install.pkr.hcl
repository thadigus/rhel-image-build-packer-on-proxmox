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

variable "storage_pool" {
    type = string
    default = "local-lvm"
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

variable "ansible_provisioner_playbook_path" {
    type = string
    default = "rhel-packer-config.yml"
}

variable "rhel_boot_iso_path" {
    type = string
    default = "local:iso/rhel-9.6-x86_64-dvd.iso"
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
      iso_file = var.rhel_boot_iso_path
      unmount = true
    }
    vm_name = "rhel-base-image"
    vm_id = 999
    username = var.proxmox_user
    token = var.proxmox_apikey
    os = "l26"
    bios = "ovmf"
    machine = "q35"
    efi_config {
      efi_storage_pool  = var.storage_pool
      pre_enrolled_keys = false
      efi_format        = "raw"
      efi_type          = "4m"
    }
    qemu_agent = true
    tpm_config {
      tpm_version 	    = "v2.0"
      tpm_storage_pool  = var.storage_pool
    }
    cpu_type = "host"
    cores = "2"
    memory = "4096"
    scsi_controller = "virtio-scsi-pci"
    disks {
      type		          = "scsi"
      disk_size         = "20G"
      storage_pool      = var.storage_pool
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
    playbook_file = "${path.cwd}/${var.ansible_provisioner_playbook_path}"
    extra_arguments = [ "--scp-extra-args", "'-O'" ] # Added to include work around https://github.com/hashicorp/packer/issues/11783#issuecomment-1137052770
    ansible_env_vars = [
      "ANSIBLE_CONFIG=${path.cwd}/ansible.cfg",
      "ANSIBLE_PYTHON_INTERPRETER=/usr/bin/python3"
    ]
  }
}


