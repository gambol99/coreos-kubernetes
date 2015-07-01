#
#   Author: Rohith
#   Date: 2015-07-01 13:36:09 +0100 (Wed, 01 Jul 2015)
#
#  vim:ts=2:sw=2:et
#

SBX_DOMAIN=sbx.example.com
BASTION=10.250.1.203
CORE_BOXES=core101 core102 core103
CACHE_BOX=10.250.1.240
STORE_BOXES=store101 store102 store103
FLEETCTL=$(shell which fleetctl)
HOSTIP=$(shell hostname -i)

.PHONY: build sbx sbx-play ceph ceph-play units mirror mirror-clean mirror-stop registry compile-resources resources resources-clean

compile-resources:
	mkdir -p ./resources
	test -f resources/confd-0.9.0-linux-amd64 || /usr/bin/wget -N https://github.com/kelseyhightower/confd/releases/download/v0.9.0/confd-0.9.0-linux-amd64 -O resources/confd-0.9.0-linux-amd64
	test -f resources/hyperkube || /usr/bin/wget -N https://storage.googleapis.com/kubernetes-release/release/v0.18.2/bin/linux/amd64/hyperkube -O resources/hyperkube
	test -f resources/kubectl || /usr/bin/wget -N https://storage.googleapis.com/kubernetes-release/release/v0.18.2/bin/linux/amd64/kubectl -O resources/kubectl
	test -f resources/embassy.gz || /usr/bin/wget -N https://drone.io/github.com/gambol99/embassy/files/embassy.gz -O resources/embassy.gz

resources: 
	make compile-resources
	make resources-clean
	sudo docker run -d -p 80:80 \
		--name resources \
		-v ${PWD}/resources:/var/www/html \
		fedora/apache
	# Make sure to export the environment variable
	# export RESOURCES=${HOSTIP}

resources-clean:
	@if sudo docker ps | grep -q resources; then sudo docker kill resources; fi 
	@if sudo docker ps -a | grep -q resources; then sudo docker rm resources; fi 

mirror:
	@if sudo docker ps -a | grep -q docker-mirror; then sudo docker start docker-mirror; else make registry; fi 
	echo "place the following into you environment"
	echo "export DOCKER_MIRROR=10.250.1.1"

mirror-clean:
	# Cleaning up the docker mirror container
	@if sudo docker ps | grep -q docker-mirror; then sudo docker kill docker-mirror; fi 
	@if sudo docker ps -a | grep -q docker-mirror; then sudo docker rm docker-mirror; fi 

mirror-stop:
	# Stopping the mirror
	@if sudo docker ps | grep -q docker-mirror; then sudo docker stop docker-mirror; fi

registry:
	sudo docker run -d -p 5000:5000 \
    --name docker-mirror \
    -e STANDALONE=false \
    -e MIRROR_SOURCE=https://registry-1.docker.io \
    -e MIRROR_SOURCE_INDEX=https://index.docker.io \
   	-v ${PWD}/registry:/tmp/registry \
    registry:latest

cache:
	vagrant up /cache/
	while ! bash -c "echo > /dev/tcp/${CACHE_BOX}/22"; do sleep 0.5; done	
	make cache-play
	# Ensure you export the DOCKER_MIRROR environment var
	# export DOCKER_MIRROR=${CACHE_BOX}

cache-play:
	@if [ -n "${FLEETCTL}" ]; then fleetctl --endpoint=http://${CACHE_BOX}:4001 start units/docker-mirror.service 2>/dev/null || true; fi		

clean:
	vagrant destroy -f
	rm -f ${HOME}/.fleetctl/known_hosts
	rm -f  ./config/discovery.yml
	rm -rf ./extra_disks

halt:
	vagrant halt
	make mirror-stop

units:
	fleetctl --strict-host-key-checking=false --tunnel ${BASTION} list-units

all:
	make sbx
	make ceph 
	
sbx:
	export VAGRANT_DEFAULT_PROVIDER=virtualbox
	$(foreach I, $(CORE_BOXES), \
		vagrant up /$(I)/ ; \
	)
	# waiting for the boxes to come up
	while ! bash -c "echo > /dev/tcp/${BASTION}/22"; do sleep 0.5; done
	make sbx-play

sbx-play:
	# @TODO need to fix the ssh keys cache on this 
	# You can nw login into the box ssh -u core <FDQN>
	# Or show the units: make units
	# Note: if you dont have fleetctl on your machine, you'll need to download it from github or 
	# ssh into the box, clone this repo and perform the below manually (which is crap!!)
	# alias fleetctl="fleetctl --strict-host-key-checking=false --endpoint=http://${BASTION}:4001"
	@if [ -n "${FLEETCTL}" ]; then fleetctl --endpoint=http://${BASTION}:4001 start units/kube* 2>/dev/null || true; fi

sbx-clean:
	$(foreach I, $(CORE_BOXES), \
		vagrant destroy -f /$(I)/ ; \
	)	

ceph:
	$(foreach I, $(STORE_BOXES), \
		vagrant up /$(I)/ ; \
	)
	# waiting for the boxes to come up
	while ! bash -c "echo > /dev/tcp/${BASTION}/22"; do sleep 0.5; done
	make ceph-play

ceph-play:
	@if [ -n "${FLEETCTL}" ]; then fleetctl --strict-host-key-checking=false --endpoint=http://${BASTION}:4001 start units/ceph* 2>/dev/null || true; fi
	
ceph-clean:
	$(foreach I, $(STORE_BOXES), \
		vagrant destroy -f /$(I)/ ; \
	)
