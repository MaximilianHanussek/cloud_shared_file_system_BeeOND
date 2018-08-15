# cloud_shared_file_system_BeeOND
Span a shared file system among several OpenStack cloud VMs by connceting cinder volumes. The shared filesystem is based on BeeGFS and BeeOND by ThinkParQ.
This repository contains several scripts which are necessary to run the shared file system and also a simple start up `build_beeond_cluster` script which comes with an example of the configuration file `beeond_cluster.conf`. 

The start up script `build_beeond_cluster` will start up two or three VMs depending on the number of worker nodes entered (1 or 2). The VMs will start with the given configurations in the `beeond_cluster.conf` (Image, Flavor, Network, Security group, Cinder storage type, Cinder volume size, Number of workers ). Currently only CentOS images are supported. Also two or three Cinder Volumes, will be created and attached to the two or three VMs. One volume for each VM. As a parameter the `build_beeond_cluster` requires the full path to configuration file. An example of such a filled file for the de.NBI cloud site Tübingen is given in `example_beeond_cluster.conf`.

In order to start a cluster fill out the configuration file and run the following command

<pre>build_beeond_cluster /path/to/config/file</pre>

This will start up two or three VMs, updates the VMs and installs additional required tools.
Afterwards then VMs will be rebooted and will continue with the software installation process.
This will be done in parallel for all two or three VMs. In the next step the cinder volumes will be created, attached to the VMs and configured. Subsequently BeeGFS, BeeOND and other required software from this github repo will be installed on all VMs. In order to communicate with the other VMs it necessary that the privat key has to be copied into the so called master VM. In a future version this private key will only be needed temporarily for a short time and replaced by an internally generated key. Also it will be possible to use SSH Keys protected by a password, currently it is only working without password protection. Finally the shared file system will be started and you will find the mount point of the file system under the following root directory `/beeond`. Every file you will put in the `/beeond` directory will be available on all participating nodes.
