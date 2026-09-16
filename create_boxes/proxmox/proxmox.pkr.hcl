packer {
  required_version = ">= 1.14.0"

  required_plugins {
    virtualbox = {
      source  = "github.com/hashicorp/virtualbox"
      version = "~> 1.1"
    }
    vagrant = {
      source  = "github.com/hashicorp/vagrant"
      version = "~> 1.1"
    }
  }
}

variable "box_version" {
  type        = string
  description = "Versione propria della box, distinta dalla versione PVE."
  default     = "9.2.1-1"
}

variable "cpus" {
  type    = number
  default = 4
}

variable "disk_size_mb" {
  type    = number
  default = 81920
}

variable "headless" {
  type    = bool
  default = true
}

variable "memory_mb" {
  type    = number
  default = 8192
}

variable "prepared_iso_path" {
  type        = string
  description = "Percorso assoluto dell'ISO unattended generata dal wrapper."
}

variable "prepared_iso_sha256" {
  type        = string
  description = "SHA-256 dell'ISO unattended locale."
}

variable "ssh_password" {
  type        = string
  description = "Password root temporanea usata solo dal communicator Packer."
  sensitive   = true
}

variable "vagrant_public_key_path" {
  type        = string
  description = "Chiave pubblica insecure distribuita con Vagrant."
}

source "virtualbox-iso" "proxmox" {
  boot_wait            = "15s"
  cpus                 = var.cpus
  disk_size            = var.disk_size_mb
  format               = "ovf"
  guest_additions_mode = "disable"
  guest_os_type        = "Debian_64"
  hard_drive_interface = "sata"
  headless             = var.headless
  iso_checksum         = "sha256:${var.prepared_iso_sha256}"
  iso_interface        = "ide"
  iso_url              = var.prepared_iso_path
  memory               = var.memory_mb
  output_directory     = "output/virtualbox-iso"
  shutdown_command     = "shutdown -P now"
  ssh_password         = var.ssh_password
  ssh_timeout          = "60m"
  ssh_username         = "root"
  vm_name              = "proxmox-ve-box-builder"

  vboxmanage = [
    ["modifyvm", "{{.Name}}", "--audio-enabled", "off"],
    ["modifyvm", "{{.Name}}", "--nested-hw-virt", "on"],
    ["modifyvm", "{{.Name}}", "--nicpromisc1", "allow-all"],
  ]
}

build {
  name    = "proxmox-ve"
  sources = ["source.virtualbox-iso.proxmox"]

  provisioner "file" {
    destination = "/tmp/vagrant-insecure.pub"
    source      = var.vagrant_public_key_path
  }

  provisioner "shell" {
    environment_vars = ["BOX_VERSION=${var.box_version}"]
    scripts = [
      "scripts/prepare-vagrant.sh",
      "scripts/cleanup.sh",
    ]
  }

  post-processor "vagrant" {
    output               = "output/proxmox-ve-${var.box_version}-virtualbox-amd64.box"
    vagrantfile_template = "box/Vagrantfile"
  }
}
