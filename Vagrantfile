# -*- mode: ruby -*-
# vi: set ft=ruby :

# No VB Guest available
IMAGE_NAME = "bento/ubuntu-20.04"
IMAGE_VERSION = "202010.24.0"
NODE_COUNT = 3
VAGRANT_ROOT = File.dirname(File.expand_path(__FILE__))
SECONDARY_DISK_SIZE_IN_GB = 10

Vagrant.configure("2") do |config|

    # config.ssh.insert_key = false
    config.vbguest.auto_update = false

    config.vm.provider "virtualbox" do |v|
        v.memory = 1500
        v.cpus = 2
        v.customize ["modifyvm", :id, "--cableconnected1", "on"]
    end

    (1..NODE_COUNT).each do |i|
        config.vm.define "node-#{i}" do |node|
            file_to_disk = File.join(VAGRANT_ROOT, "node-#{i}-filename.vdi")
            node.vm.box = IMAGE_NAME
            node.vm.box_version = IMAGE_VERSION
            node.vm.network "private_network", ip: "192.168.10.#{i + 9}"
            node.vm.hostname = "node-#{i}"
            node.ssh.shell = "bash -c 'BASH_ENV=/etc/profile exec bash'"
            node.vm.synced_folder '.', '/vagrant', disabled: true
            node.vm.provision "file", source: "scripts/.", destination: "/home/vagrant"
            node.vm.provision :shell, path: "scripts/bootstrap.sh", privileged: true
            node.vm.provider :virtualbox do |vb|
              if(!File.file?(file_to_disk))
                vb.customize ['createhd', '--filename', file_to_disk, '--size', SECONDARY_DISK_SIZE_IN_GB * 1024]
              end
              vb.customize ['storageattach', :id, '--storagectl', 'SATA Controller', '--port', 1, '--device', 0, '--type', 'hdd', '--medium', file_to_disk]
            end
        end
    end
end
