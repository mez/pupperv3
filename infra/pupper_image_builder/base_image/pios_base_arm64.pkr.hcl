packer {
  required_plugins {
    git = {
      version = ">=v0.3.2"
      source  = "github.com/ethanmdavidson/git"
    }
  }
}

source "arm" "raspbian" {
  file_urls             = ["file://trixie_base.img.xz"]
  file_checksum_type    = "none"
  file_target_extension = "xz"
  file_unarchive_cmd    = ["xz", "--decompress", "$ARCHIVE_PATH"]
  image_build_method    = "resize"
  image_path            = "pupOS_pios_base.img"
  image_size            = "8G"
  image_type            = "dos"
  image_partitions {
    name         = "boot"
    type         = "c"
    start_sector = "16384"
    filesystem   = "fat"
    size         = "512M"
    mountpoint   = "/boot/firmware"
  }
  image_partitions {
    name         = "root"
    type         = "83"
    start_sector = "1064960"
    filesystem   = "ext4"
    size         = "0"
    mountpoint   = "/"
  }
  image_chroot_env             = ["PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"]
  qemu_binary_source_path      = "/usr/bin/qemu-aarch64-static"
  qemu_binary_destination_path = "/usr/bin/qemu-aarch64-static"
}

build {
  sources = ["source.arm.raspbian"]

  provisioner "shell" {
    inline = ["sleep 10"]
  }

  # DNS for internet access inside chroot
  provisioner "shell" {
    inline = [
      "sudo mv /etc/resolv.conf /etc/resolv.conf.bk",
      "echo 'nameserver 8.8.8.8' | sudo tee /etc/resolv.conf",
      "echo 'nameserver 1.1.1.1' | sudo tee -a /etc/resolv.conf",
    ]
  }

  provisioner "shell" {
    script = "setup_scripts/set_hostname.sh"
  }

  provisioner "file" {
    source      = "resources/firstrun.sh"
    destination = "/boot/firstrun.sh"
  }

  provisioner "shell" {
    script = "provision_pios_base.sh"
  }

  provisioner "shell" {
    inline = [
      "sudo mv /etc/resolv.conf.bk /etc/resolv.conf",
    ]
  }
}
