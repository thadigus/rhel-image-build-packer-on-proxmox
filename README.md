# RHEL Base Image Build with Hashicorp Packer

Automated installations of RHEL 9 with Kickstart files handled via HTTP using Hashicorp Packer against Proxmox Infrastructure. In order to use this repo you will need Packer installed and the RHEL 9 ISO present at `local:iso/rhel-9.5-x86_64-dvd.iso` on the target Proxmox server. This should install RHEL 9 in UEFI mode with a fairly conservative partition table. For further customization I highly recommend editing the kickstart file and Ansible playbook I've provided as these are just templates that can be expanded upon.

Start with installing Packer and editing the sensitive vars file to include your API key and parameters. I've added a set of RSA keys for SSH but I highly suggest you generate/replace them with your own. Also, be sure to set a username in the sensitive vars file and copy the public key string in so that Packer can install these for you. I don't typically set a password for any of my users and only use key based authentication. I've added a task to the Ansible playbook to set a password if you'd like. For any advice/assistance please feel free to open an issue [at the issues tab](https://gitlab.com/thadigus/rhel-image-build-packer-on-proxmox/-/issues).

Here is a quick example of setting up the repo, after creating your own `rhel-packer-install-sensitive.auto.pkrvars.hcl` file. This is how the SSH keys were generated:

```shell
[root@archwhitebox code]# ls           
README.md        rhel-base-install.pkr.hcl  rhel-packer-config.yml                          rhel-packer-install-sensitive.auto.pkrvars.hcl.EXAMPLE
anaconda-ks.cfg  rhel-packer-build.sh       rhel-packer-install-sensitive.auto.pkrvars.hcl
[root@archwhitebox code]# ssh-keygen                                          
Generating public/private rsa key pair.                                       
Enter file in which to save the key (/root/.ssh/id_rsa): ./id_rsa             
Enter passphrase (empty for no passphrase):                                   
Enter same passphrase again:                                                  
Your identification has been saved in ./id_rsa     
Your public key has been saved in ./id_rsa.pub                                
The key fingerprint is:                                                                                                                                     
SHA256:olkPQoUBi9tgfNPuoRiwbgMpdA693bbX0dK5xZCsuFc root@archwhitebox                                                                                        
The key's randomart image is:                                                 
+---[RSA 3072]----+                                                           
|  ...o.          |                                                           
|....o.      . .  |                                                           
|+=.=..       +   |                                                           
|+*=.= .   . + +  |                                                           
|*..o.++oS. + E o |                                                           
|+ o o=o+. o + o  |                                                           
| = .o. ..o o .   |                                                           
|. .     . .      |                                                           
|                 |                                                                                                                                         
+----[SHA256]-----+                                                                                                                                         
[root@archwhitebox code]# ls                                                  
README.md        id_rsa.pub                 rhel-packer-config.yml                                                                                          
anaconda-ks.cfg  rhel-base-install.pkr.hcl  rhel-packer-install-sensitive.auto.pkrvars.hcl                                                                  
id_rsa           rhel-packer-build.sh       rhel-packer-install-sensitive.auto.pkrvars.hcl.EXAMPLE
```

### Sample Kickstart File

A kickstart file has been provided in this repo, but feel free to customize this to your liking. Kickstart is a really modular and convient system for auto-installing on RHEL machines so there's a ton of options to use. Here is a basic RHEL 9 EFI install with a trimmed up partition table. The root account is locked and the user account is provisioned without a password and only SSH based authentication. Sudo is configured for NOPASSWD for default, but this can be changed with Ansible. I've also configured EPEL 9 to auto-setup in order to install open-vm-tools. Everything else is fairly minimal, there is a comment out SCAP config as well to drop in whatever profile you'd like. Be sure to note the Packer variables noted with `${variablename}` in the file. Those variables are filled by Packer at runtime as a part of the build process.

```kickstart
### RHEL 9 Kickstart Configuration
#version=RHEL9
### Set language, keyboard and timezone
lang en_US.UTF-8
keyboard --xlayouts='us'
timezone America/Indiana/Indianapolis --utc
### Add kdump Config
%addon com_redhat_kdump --enable --reserve-mb='auto'
%end
### Lock root user
rootpw --lock
### Create Ansible user for post provisioning processes
user --name=${ssh_user}
sshkey --username=${ssh_user} "${build_key}"
### Text Install
text
### Only Use SDA
ignoredisk --only-use=sda
### System Bootloader Configuration
bootloader --append="crashkernel=1G-4G:192M,4G-64G:256M,64G-:512M" --location=mbr --boot-drive=sda
### Partition Clearing Information
clearpart --none --initlabel
### Create primary system partitions.
### Modify partition sizes for the virtual machine hardware.
part /boot --fstype="xfs" --ondisk=sda --size=1024
part /boot/efi --fstype="efi" --ondisk=sda --size=512 --fsoptions="umask=0077,shortname=winnt"
part pv.0 --fstype="lvmpv" --ondisk=sda --size=18432
### Create a logical volume management (LVM) group.
volgroup vgroot --pesize=4096 pv.0
### Modify logical volume sizes for the virtual machine hardware.
logvol / --fstype="ext4" --size=4096 --name=lvroot --vgname=vgroot --label=ROOTFS
logvol swap --fstype="swap" --size=1024 --name=lvswap --vgname=vgroot --label=SWAPFS
logvol /home --fstype="ext4" --size=2048 --name=lvhome --vgname=vgroot --label=HOMEFS --fsoptions="nodev,nosuid"
logvol /tmp --fstype="ext4" --size=2048 --name=lvtmp --vgname=vgroot --label=TMPFS --fsoptions="nodev,noexec,nosuid"
logvol /opt --fstype="ext4" --size=1024 --name=lvopt --vgname=vgroot --label=OPTFS --fsoptions="nodev"
logvol /var --fstype="ext4" --size=2048 --name=lvvar --vgname=vgroot --label=VARFS --fsoptions="nodev"
logvol /var/log --fstype="ext4" --size=2048 --name=lvvarlog --vgname=vgroot --label=LOGFS --fsoptions="nodev,noexec,nosuid"
logvol /var/log/audit --fstype="ext4" --size=1024 --name=lvvarlogaudit --vgname=vgroot --label=AUDITFS --fsoptions="nodev,noexec,nosuid"
### Set system Purpose for Red Hat Cloud
syspurpose --role="Red Hat Enterprise Linux Server" --sla="Self-Support" --usage="Development/Test"
### Boot with DHCP
network --bootproto=dhcp
### Skip grpahical install
skipx
firstboot --disable
### Enable SELinux
selinux --enforcing
### Enable firewall but allow SSH
firewall --enabled --ssh
### Use SSSD for primary system authentication
auth --passalgo=sha512 --useshadow
### Ensure NetworkManager and SSHD are started
services --enabled=NetworkManager,sshd
### Reboot after Installation
reboot
### Configure SCAP profile - Optional
#%addon com_redhat_oscap
#content-type = scap-security-guide
#profile = xccdf_org.ssgproject.content_profile_ospp
#%end
### Post install script to enable EPEL, install open-vm-tools, and configure sudo access for build user. 
%post --interpreter=/bin/bash
dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
dnf makecache
dnf install -y sudo open-vm-tools python3
echo "${ssh_user} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/${ssh_user}
sed -i "s/^.*requiretty/#Defaults requiretty/" /etc/sudoers
%end
%packages
@^minimal-environment
kexec-tools
%end
### Reboot after the installation is complete.
### --eject attempt to eject the media before rebooting.
reboot --eject
```

## Packer Configuration

Luckily Packer configures itself for the most part. Be sure to follow Packer documentation for installation and troubleshooting of the first `init` and `verify` steps but most of this should be fairly straight forward. You can use the Packer Docker image to get started but I've had limited compatability with Ansible.

### Sample Secure Vars

Ensure that your secure vars are configured with at least the following lines at `./rhel-packer-install-sensitive.auto.pkrvars.hcl`. These are the variables that have been set aside to make sure that this works for your given Proxmox environment. The Ansible user is used for post-install steps and for any other customizatoin you'd like to do. Be sure to add your own tasks/roles to `rhel-packer-config.yml` for your own custom template.

```hcl
/*
    DESCRIPTION:
    Build account variables used for all builds.
    - Variables are passed to and used by guest operating system configuration files (e.g., ks.cfg, autounattend.xml).
    - Variables are passed to and used by configuration scripts.
*/

// Default Account Credentials
ssh_user                 = "ANSIBLE_SERVICE_ACCOUNT_USER" //SSH Username for Preseed/Kickstart to configure so Ansible can get into provision afterwards
build_key                = "ssh-rsa AAAAB3NzaC1yc....x/vq1OaLAz6pYk8=" // Actual public key you'd like installed for the Ansible user to be allowed in.

/*
    DESCRIPTION:
    Proxmox WebUI variables used for Linux builds. 
    - Variables are use by the source blocks.
*/

//Proxmox Credentials
proxmox_host             = "10.x.x.x"
proxmox_node             = "PROXMOXNODE"
proxmox_user             = "root@pam!APIKEY"
proxmox_apikey           = "XXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXX"

// VM Config
vlan_tag                 = ""
```

### Script for Packer Build processes

I've created a very basic script to run the Packer commands once you're sure that everything is working as intended. I'll probably eventually replace this script with an Ansible playbook to make sure everything is actually setup properly. I recommend running in a container, but I don't have a good container image to recommend. Currently I use a custom RHEL UBI 9 container with Packer and Ansible already installed.

```shell
rhel-packer-build.sh
```
