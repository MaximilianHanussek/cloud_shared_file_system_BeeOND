#!/bin/bash

#Start initial UNICORE cluster over API

config_file_path=$1

#Read from config file
readarray -t api_parameters_array < "$config_file_path"

credentials=${api_parameters_array[0]}
path_private_key=${api_parameters_array[1]}
flavor=${api_parameters_array[2]}
image=${api_parameters_array[3]}
network=${api_parameters_array[4]}
security_group=${api_parameters_array[5]}
key_name=${api_parameters_array[6]}
storage_type=${api_parameters_array[7]}
volume_size=${api_parameters_array[8]} #Has to be entered in GB
number_workers=${api_parameters_array[9]}
vm_name_master=beeond_queen
vm_name_compute1=beeond_worker1
vm_name_compute2=beeond_worker2
volume_name_master=volume_beeond_queen
volume_name_compute1=volume_beeond_worker1
volume_name_compute2=volume_beeond_worker2

#Source the rc credentials
source "$credentials"

#Create instance(s)
echo "VMs are launching"
if [[ $number_workers == "1" ]]; then
	vm_id_master=$(openstack server create --flavor "$flavor" --image "$image" --nic net-id="$network" --security-group "$security_group" --key-name "$key_name" "$vm_name_master" | grep "^| id" | awk '{print $4}')
	vm_id_compute1=$(openstack server create --flavor "$flavor" --image "$image" --nic net-id="$network" --security-group "$security_group" --key-name "$key_name" "$vm_name_compute1" | grep "^| id" | awk '{print $4}')
else
	vm_id_master=$(openstack server create --flavor "$flavor" --image "$image" --nic net-id="$network" --security-group "$security_group" --key-name "$key_name" "$vm_name_master" | grep "^| id" | awk '{print $4}')
	vm_id_compute1=$(openstack server create --flavor "$flavor" --image "$image" --nic net-id="$network" --security-group "$security_group" --key-name "$key_name" "$vm_name_compute1" | grep "^| id" | awk '{print $4}')
	vm_id_compute2=$(openstack server create --flavor "$flavor" --image "$image" --nic net-id="$network" --security-group "$security_group" --key-name "$key_name" "$vm_name_compute2" | grep "^| id" | awk '{print $4}')
fi

if [[ $number_workers == "1" ]]; then
	echo "VM ID master: " $vm_id_master
	echo "VM ID worker: " $vm_id_compute1
else
	echo "VM ID master: " $vm_id_master
	echo "VM ID worker1: " $vm_id_compute1
	echo "VM ID worker2: " $vm_id_compute2
fi
### BEGIN FUNCTION DECLARATION ###################################################################################################################################################################

### Check if VM is active and can be used (ping and ssh is established) $1 is the vm_id
check_vm_acessability() {

active=0
ping=0
ssh=0

while true; do
	vm_status=$(openstack server show $1 | grep "status" | awk '{print $4}')
	if [[ $vm_status == "BUILD" ]]; then
		active=0
		echo "VM state of $1 is " $vm_status 
		sleep 10
	elif [[ $vm_status == "ACTIVE" ]]; then
		active=1
		echo "VM $1 is active"
		break	
	elif [[ $vm_status == "ERROR" ]]; then
		echo "VM $1 is in state error and will be deleted"
		openstack server delete $1
		break
	else
		echo "Unknown error occured"
		exit 1; 
	fi
done

if [[ $active == 1 ]]; then
	ping_counter=0
	vm_ip=""
	vm_ip=$(openstack server show $1 | grep addresses | awk '{print $4}' | awk -F = '{print $2}')
	#echo "IP address master: " $vm_ip
	while true; do	
		if ping_bool $vm_ip; then
			ping=1
			echo "Ping is established"
			break
		else 
			if [[ $ping_counter == 36 ]]; then
				echo "Ping could not been established, VM will be deleted"
				openstack server delete $1
				exit 1;
			else
				echo "Waiting for ping"
				ping_counter=$((ping_counter+1))	
				sleep 10
			fi
		fi	
	done
fi

if [[ $active == 1 && $ping == 1 ]]; then
	ssh_counter=0
	ssh_exit_status=""
	while true; do
		ssh_check=$(nmap $vm_ip -PN -p ssh | grep -c open)
		ssh -i $path_private_key -q -o BatchMode=yes centos@$vm_ip exit
		ssh_exit_status=$(echo $?)
		
		if [[ $ssh_counter == 18 ]]; then
			echo "Ping could not been established, VM will be deleted"
                	openstack server delete $1
           		exit 1;
		else
			if [[ $ssh_exit_status == 255 ]]; then
				echo "Waiting for SSH connection"
				sleep 10
			else

				if [[ $ssh_check == 1 && $ssh_exit_status == 0 ]]; then
					ssh=1
					echo "SSH connection is working"
					break
				else
					echo "Waiting for SSH connection"
					ssh_counter=$((ssh_counter+1))
					sleep 20
				fi

			fi
		fi
	done	
fi
}

### Check if cinder volume is active and can be used (available) $1 is the volume_id
check_volume_acessability() {
available=0

while true; do
	volume_status=$(openstack volume show $1 | grep " status" | awk '{print $4}')
	if [[ $volume_status == "creating" ]]; then
		available=0
		echo "Volume state of $1 is " $volume_status 
		sleep 10
	elif [[ $volume_status == "available" ]]; then
		available=1
		echo "Volume state of $1 is available"
		break	
	elif [[ $volume_status == "error" ]]; then
		echo "Volume $1 is in state error and will be deleted"
		openstack volume delete $1
		break
	else
		echo "Unknown error occured"
		exit 1; 
	fi
done
}

### Update VM to newest packages and kernel $1 is the vm_name and $2 is the corresponding IP and $3 is the corresponding vm_id
update_vm() {

#Update and install necessary packages

if [[ $ssh == 1 ]]; then
echo "$1 is updating"
ssh -i $path_private_key -o BatchMode=yes -q -tt -n centos@$2 sudo yum update -y -q 1> /dev/null 2> /dev/null 
ssh -i $path_private_key -o BatchMode=yes -q -tt -n centos@$2 sudo reboot 1> /dev/null 2> /dev/null
fi

echo "VM $1 is rebooting"
sleep 30
check_vm_acessability "$3"
	
if [[ $ssh == 1 ]]; then
echo "VM $1 installation process is continuing"
ssh -i $path_private_key -q -tt -n centos@$2 sudo yum group install "Development Tools" -y -q 1> /dev/null 2> /dev/null
ssh -i $path_private_key -q -tt -n centos@$2 sudo yum install epel-release -y -q 1> /dev/null 2> /dev/null
ssh -i $path_private_key -q -tt -n centos@$2 sudo yum install vim wget nano htop git python-devel kernel-devel -y -q 1> /dev/null 2> /dev/null
hostname=$(ssh -i $path_private_key -q -tt -n centos@$2 hostname)
hostname=$(echo $hostname | tr -d "\n\r")
echo "VM Hostname of $1 is set"
ssh -i $path_private_key -q -tt -n centos@$2 hostname_master=$hostname hostnamectl --static set-hostname $hostname
fi
}

### Install and configure beeond with $1 is the vm_name and $2 the corressponding IP
install_and_configure_beeond() {

echo "Set mountpoint permissions for $1"
#Set mountpoint permissions correctly
ssh -i $path_private_key -q -tt -n centos@$2 sudo chmod -R 777 /mnt/

echo "Installation of beeond on $1"
#Install beeond for virtual unicore cluster
#Add BeeGFS repo
ssh -i $path_private_key -q -tt -n centos@$2 sudo wget -O /etc/yum.repos.d/beegfs.repo https://www.beegfs.io/release/latest-stable/dists/beegfs-rhel7.repo 1> /dev/null 2> /dev/null
#Add repo key
ssh -i $path_private_key -q -tt -n centos@$2 sudo rpm --import https://www.beegfs.io/release/latest-stable/gpg/RPM-GPG-KEY-beegfs 1> /dev/null 2> /dev/null
#Install beegfs services
ssh -i $path_private_key -q -tt -n centos@$2 sudo yum install beegfs-mgmtd -y -q 1> /dev/null 2> /dev/null
ssh -i $path_private_key -q -tt -n centos@$2 sudo yum install beegfs-meta -y -q 1> /dev/null 2> /dev/null
ssh -i $path_private_key -q -tt -n centos@$2 sudo yum install beegfs-storage -y -q 1> /dev/null 2> /dev/null
ssh -i $path_private_key -q -tt -n centos@$2 sudo yum install beegfs-client beegfs-helperd beegfs-utils -y -q 1> /dev/null 2> /dev/null
#Install beeond
ssh -i $path_private_key -q -tt -n centos@$2 sudo yum install beeond -y -q 1> /dev/null 2> /dev/null

echo "Set log directory permissions for $1"
#Set log permissions correctly
ssh -i $path_private_key -q -tt -n centos@$2 sudo chmod -R 777 /var/log/

echo "Set run directory permissions for $1"
#Set run permissions correctly
ssh -i $path_private_key -q -tt -n centos@$2 sudo chmod 777 /var/run/

echo "Disble SELinux on $1"
#Set SELinux to permissive mode
ssh -i $path_private_key -q -tt -n centos@$2 sudo setenforce 0
ssh -i $path_private_key -q -tt -n centos@$2 sudo sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux

echo "Disable beeond repo update on $1"
#Disable repo update
ssh -i $path_private_key -q -tt -n centos@$2 sudo sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/beegfs.repo

echo "Download git repo on $1"
#Download git repo for customized beeond files
ssh -i $path_private_key -q -tt -n centos@$2 git clone https://github.com/MaximilianHanussek/cloud_shared_file_system_BeeOND.git 1> /dev/null 2> /dev/null

echo "Replace standard beeond scripts on $1"
#Replace standard beeond scripts with custom scripts
ssh -i $path_private_key -q -tt -n centos@$2 sudo cp -f /home/centos/cloud_shared_file_system_BeeOND/beeond /opt/beegfs/sbin/
ssh -i $path_private_key -q -tt -n centos@$2 sudo cp -f /home/centos/cloud_shared_file_system_BeeOND/beegfs-ondemand-stoplocal /opt/beegfs/lib/

echo "Create filesystem on cinder volume on $1"
#Create filesystem on volumes
ssh -i $path_private_key -q -tt -n centos@$2 sudo mkfs.xfs /dev/vdb 1> /dev/null 2> /dev/null

echo "Mount cinder volumes on $1"
#Mount cinder volume(s)
ssh -i $path_private_key -q -tt -n centos@$2 sudo mount /dev/vdb /mnt
ssh -i $path_private_key -q -tt -n centos@$2 sudo chmod -R 777 /mnt/

if [[ $1 == "$vm_name_master" ]]; then
echo "Set new beegfs storage pooltype thresholds on $1"
#Set new thresholds for beegfs pooltypes 
ssh -i $path_private_key -q -tt -n centos@$2 "sudo sed -i 's/.*tuneMetaSpaceLowLimit.*/tuneMetaSpaceLowLimit = 100M/' /etc/beegfs/beegfs-mgmtd.conf"
ssh -i $path_private_key -q -tt -n centos@$2 "sudo sed -i 's/.*tuneMetaSpaceEmergencyLimit.*/tuneMetaSpaceEmergencyLimit = 10M/' /etc/beegfs/beegfs-mgmtd.conf"
ssh -i $path_private_key -q -tt -n centos@$2 "sudo sed -i 's/.*tuneStorageSpaceLowLimit.*/tuneStorageSpaceLowLimit = 500M/' /etc/beegfs/beegfs-mgmtd.conf"
ssh -i $path_private_key -q -tt -n centos@$2 "sudo sed -i 's/.*tuneStorageSpaceEmergencyLimit.*/tuneStorageSpaceEmergencyLimit = 50M/' /etc/beegfs/beegfs-mgmtd.conf"
fi
} 

### END FUNCTION DECLARATION ###################################################################################################################################################################


sleep 10

if [[ $number_workers == "1" ]]; then
	check_vm_acessability "$vm_id_master"
	vm_ip_master=$vm_ip

	check_vm_acessability "$vm_id_compute1"
	vm_ip_compute1=$vm_ip
else
	check_vm_acessability "$vm_id_master"
	vm_ip_master=$vm_ip

	check_vm_acessability "$vm_id_compute1"
	vm_ip_compute1=$vm_ip

	check_vm_acessability "$vm_id_compute2"
	vm_ip_compute2=$vm_ip
fi

if [[ $number_workers == "1" ]]; then
	update_vm "$vm_name_master" "$vm_ip_master" "$vm_id_master" &
	update_vm "$vm_name_compute1" "$vm_ip_compute1" "$vm_id_compute1" &
else
	update_vm "$vm_name_master" "$vm_ip_master" "$vm_id_master" &
	update_vm "$vm_name_compute1" "$vm_ip_compute1" "$vm_id_compute1" &
	update_vm "$vm_name_compute2" "$vm_ip_compute2" "$vm_id_compute2" &
fi
wait

#Create cinder volumes for every VM

if [[ $number_workers == "1" ]]; then
	volume_id_master=$(openstack volume create --size $volume_size --type "$storage_type" "$volume_name_master" | grep "^| id" | awk '{print $4}')
	echo "Volume ID master: " $volume_id_master

	volume_id_compute1=$(openstack volume create --size $volume_size --type "$storage_type" "$volume_name_compute1" | grep "^| id" | awk '{print $4}')
	echo "Volume ID compute1: " $volume_id_compute1
else
	volume_id_master=$(openstack volume create --size $volume_size --type "$storage_type" "$volume_name_master" | grep "^| id" | awk '{print $4}')
	echo "Volume ID master: " $volume_id_master

	volume_id_compute1=$(openstack volume create --size $volume_size --type "$storage_type" "$volume_name_compute1" | grep "^| id" | awk '{print $4}')
	echo "Volume ID compute1: " $volume_id_compute1

	volume_id_compute2=$(openstack volume create --size $volume_size --type "$storage_type" "$volume_name_compute2" | grep "^| id" | awk '{print $4}')
	echo "Volume ID compute2: " $volume_id_compute2
fi

if [[ $number_workers == "1" ]]; then
	check_volume_acessability "$volume_id_master"
	if [[ $available == 1 ]]; then
		openstack server add volume --device /dev/vdb $vm_id_master $volume_id_master
	fi
	echo "Cinder Volume is attached to $vm_name_master"

	check_volume_acessability "$volume_id_compute1"
	if [[ $available == 1 ]]; then
		openstack server add volume --device /dev/vdb $vm_id_compute1 $volume_id_compute1
	fi
	echo "Cinder Volume is attached to $vm_name_compute1"
else
	check_volume_acessability "$volume_id_master"
	if [[ $available == 1 ]]; then
		openstack server add volume --device /dev/vdb $vm_id_master $volume_id_master
	fi
	echo "Cinder Volume is attached to $vm_name_master"

	check_volume_acessability "$volume_id_compute1"
	if [[ $available == 1 ]]; then
		openstack server add volume --device /dev/vdb $vm_id_compute1 $volume_id_compute1
	fi
	echo "Cinder Volume is attached to $vm_name_compute1"

	check_volume_acessability "$volume_id_compute2"
	if [[ $available == 1 ]]; then
		openstack server add volume --device /dev/vdb $vm_id_compute2 $volume_id_compute2
	fi
	echo "Cinder Volume is attached to $vm_name_compute2"
fi

if [[ $number_workers == "1" ]]; then
	install_and_configure_beeond "$vm_name_master" "$vm_ip_master" &
	install_and_configure_beeond "$vm_name_compute1" "$vm_ip_compute1" &
else
	install_and_configure_beeond "$vm_name_master" "$vm_ip_master" &
	install_and_configure_beeond "$vm_name_compute1" "$vm_ip_compute1" &
	install_and_configure_beeond "$vm_name_compute2" "$vm_ip_compute2" &
fi
wait

#Compile beegfs client beforehand as it needs special permissions for the autobuild
if [[ $number_workers == "1" ]]; then
	echo "Compile beegfs client on $vm_name_master"
	ssh -i $path_private_key -q -tt -n centos@$vm_ip_master sudo /etc/init.d/beegfs-client rebuild 1> /dev/null 2> /dev/null

	echo "Compile beegfs client on $vm_name_compute1"
	ssh -i $path_private_key -q -tt -n centos@$vm_ip_compute1 sudo /etc/init.d/beegfs-client rebuild 1> /dev/null 2> /dev/null

else
	echo "Compile beegfs client on $vm_name_master"
	ssh -i $path_private_key -q -tt -n centos@$vm_ip_master sudo /etc/init.d/beegfs-client rebuild 1> /dev/null 2> /dev/null

	echo "Compile beegfs client on $vm_name_compute1"
	ssh -i $path_private_key -q -tt -n centos@$vm_ip_compute1 sudo /etc/init.d/beegfs-client rebuild 1> /dev/null 2> /dev/null

	echo "Compile beegfs client on $vm_name_compute2"
	ssh -i $path_private_key -q -tt -n centos@$vm_ip_compute2 sudo /etc/init.d/beegfs-client rebuild 1> /dev/null 2> /dev/null
fi

echo "Create beeond nodelist on $vm_name_master"
#Create beeond nodelist
ssh -i $path_private_key -q -tt -n centos@$vm_ip_master touch /home/centos/.beeond_nodefile 1> /dev/null 2> /dev/null

echo "Set up nodefile on $vm_name_master"
#Set up nodefile
if [[ $number_workers == "1" ]]; then
	ssh -i $path_private_key -q -tt -n centos@$vm_ip_master "echo $vm_ip_master > /home/centos/.beeond_nodefile" 1> /dev/null 2> /dev/null
	ssh -i $path_private_key -q -tt -n centos@$vm_ip_master "echo $vm_ip_compute1 >> /home/centos/.beeond_nodefile" 1> /dev/null 2> /dev/null
else
	ssh -i $path_private_key -q -tt -n centos@$vm_ip_master "echo $vm_ip_master > /home/centos/.beeond_nodefile" 1> /dev/null 2> /dev/null
	ssh -i $path_private_key -q -tt -n centos@$vm_ip_master "echo $vm_ip_compute1 >> /home/centos/.beeond_nodefile" 1> /dev/null 2> /dev/null
	ssh -i $path_private_key -q -tt -n centos@$vm_ip_master "echo $vm_ip_compute2 >> /home/centos/.beeond_nodefile" 1> /dev/null 2> /dev/null
fi

echo "Copy private key into VM (temporarily)"
#Copy private key temporarily into VM
scp -i $path_private_key $path_private_key centos@$vm_ip_master:/home/centos/ 1> /dev/null 2> /dev/null

#Create VM internal private keys TO DO

echo "Start BeeOND cluster"
#Start beeond shared file system on master
ssh -i $path_private_key -q -tt -n centos@$vm_ip_master beeond start -n /home/centos/.beeond_nodefile -d /mnt/ -c /beeond/ -a /home/centos/maximilian-demo.pem -z centos 1> /dev/null 2> /dev/null

echo "Success: The BeeOND cluster has started sucessfully and is ready to use."
echo "You can share files between the VMs via the /beeond directory."

#Stop beeond shared filed system and delete all data of the system
#beeond stop -n /home/centos/.beeond_nodefile -L -d -a /home/centos/maximilian-demo.pem -z centos



