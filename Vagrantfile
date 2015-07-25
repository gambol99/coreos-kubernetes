#
#   Author: Rohith
#   Date: 2015-06-15 16:30:49 +0100 (Mon, 15 Jun 2015)
#
#  vim:ts=2:sw=2:et
#
# -*- mode: ruby -*-dd
# vi: set ft=ruby :

require 'yaml'
require 'net/http'
require 'erb'
require 'fileutils'

VAGRANT_DEFAULT_PROVIDER = :virtualbox
EXTRA_DISKS              = "./extra_disks"
ENVIRONMENT_CONFIG       = "./config/config.yml"

def config
  require ArgumentError, "unable to find the vagrant config" unless File.exist?(ENVIRONMENT_CONFIG)
  YAML.load(File.read(ENVIRONMENT_CONFIG)) || {}
end

def boxes
  config['boxes'] || {}
end

#
# We use the users public key and inject into the cloudinit
#
def public_key
  @key ||= File.read("#{ENV['HOME']}/.ssh/id_rsa.pub")
end

def etcd_masters
  @cluster ||= nil
  unless @cluster
    @cluster = {}
    boxes.each_pair do |fqdn, host|
      hostname = fqdn.split('.').first
      metadata = host['metadata'] || {}
      @cluster[hostname] = host['virtualbox']['ip'] if metadata['etcd_master']
    end
  end
  @cluster
end

def extra_disk(name, hostname)
  FileUtils.mkdir_p('./extra_disks') unless File.exist?(EXTRA_DISKS)
  "#{EXTRA_DISKS}/#{name}-#{hostname}.vdi"
end

Vagrant.configure(2) do |config|
  # Disable the VB Guest plugin, it doesn't work with Core OS
  config.vbguest.no_install = true if Vagrant.has_plugin?('vagrant-vbguest')

  boxes.each_pair do |hostname, host|
    @hostname     = hostname.split('.').first
    @domain       = hostname.split('.')[1..20].join('.')
    @public_key   = public_key
    @etcd_cluster = etcd_masters
    @metadata     = host['metadata'] || {}
    vbox          = host['virtualbox']

    is_coreos   = vbox['box'] =~ /^core/

    #
    # Cloudinit configuration
    #
    cloudinit ||= ""
    cloudinit = ERB.new(File.read(vbox['cloudinit']), nil, '-' ).result(binding) if is_coreos

    config.vm.define hostname do |x|
      x.vm.hostname  = hostname
      x.vm.box       = vbox['box']
      x.vm.box_url   = vbox['url'] if vbox['url']

      #
      # Virtualbox related configuration
      #
      x.vm.provider :virtualbox do |virtualbox,override|
        virtualbox.gui   = vbox['gui'] || false
        virtualbox.name  = hostname

        #
        # Extra disks and storage
        #
        ( vbox['disks'] || [] ).each_with_index do |disk,index|
          disk_filename = extra_disk(disk['name'], hostname)
          unless File.exist?(disk_filename)
            virtualbox.customize ['createhd', '--filename', disk_filename, '--size', disk['size'] ]
            virtualbox.customize [ 'storageattach', :id,
              '--storagectl', 'IDE Controller', '--port', 1, '--device', index, '--type', 'hdd', '--medium', disk_filename ]
          end
        end

        # step: apply the customizaitions
        (vbox['resources'] || {} ).each_pair do |key,value|
          virtualbox.customize [ "modifyvm", :id, "--#{key}", value ]
        end

        # step: the override for virtualbox
        override.vm.network :private_network, ip: vbox['ip']
      end

      # step: perform a fake cloudinit on the box
      config.vm.provision :shell, :inline => cloudinit, :privileged => true
    end
  end
end
