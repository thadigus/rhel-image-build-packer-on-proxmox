#!/bin/bash
/usr/bin/packer init -var-file=./rhel-packer-install-sensitive.auto.pkrvars.hcl .
/usr/bin/packer validate -var-file=./rhel-packer-install-sensitive.auto.pkrvars.hcl .
/usr/bin/packer build -force -var-file=./rhel-packer-install-sensitive.auto.pkrvars.hcl .
