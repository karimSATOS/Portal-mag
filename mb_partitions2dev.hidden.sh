#!/bin/sh

BOXIP=http://localhost
WGET=/usr/bin/wget
BOOT=/boot
DEV=sda
LOG_AND_BACKUPDIR=/home/root
LOGFILE=$LOG_AND_BACKUPDIR/mb-partitioning_on_device_$(date +%Y.%m.%d_%H-%M-%S).log
FSTAB_BACKUP=$LOG_AND_BACKUPDIR/fstab.org
LAST_USERDATA_MOUNT_FILE=$LOG_AND_BACKUPDIR/last_userdata_mount.txt

## with the following variable you can choose if you want to have an extra reserve of nearly 1gb for userdata Partition (default 1gb).
## if you don't want an extra reserve, change the following two lines to #RESERVE=1025050 and RESERVE=1050
RESERVE=1025050
#RESERVE=1050
## PLEASE NOTE !
## if a space is free after creating Partitions for Multiboot Slots, a userdata Partition will be created absolutely, indifferent.
## if you select an extra reserve or not, the question is only how large will the userdata Partition be.

## with the following variable you can select if you want to have the userdata Partition formatted in ext4 or fat32 (default = fat32).
## if you want to have the userdata Partition formatted in ext4 instead, change the following two lines to #USERDATA_FS=fat32 and USERDATA_FS=ext4
USERDATA_FS=ext4
#USERDATA_FS=ext4

## the following variable is to select the Mountpoint for the userdata Partition, for example: /media/usb or /media/sdcard (default = /media/hdd).
USERDATA_MOUNTPOINT=/media/hdd

## the following variable is to limit how many Extra Multiboot Slots you want to create.
EXTRA_MB_SLOTSLIMIT=20

#########################################################
### From here on there is nothing to change for users ###
#########################################################
### mb_partitions2dev.sh         version:1.3          ###
#########################################################

STARTUP_END="rootwait blkdevparts=mmcblk0:1M(boot),1M(bootargs),1M(bootoptions),3M(baseparam),4M(pqparam),4M(logo),4M(deviceinfo),4M(softwareinfo),4M(loaderdb),32M(loader),8M(trustedcore),16M(linuxkernel1),16M(linuxkernel2),16M(linuxkernel3),16M(linuxkernel4),-(userdata)'"

IMG_RUN_CHECKFILE=$BOOT/STARTUP
IMG_ON_MEDIA=usb0

# the following cammand is to close the window of hotkey (or other plugin) first (you don't need it, because messages are shown in OSD messages, wait a bit after starting the script and then you will see the messages).
$WGET -q -O - $BOXIP/web/remotecontrol?command=174 && sleep 2

# General Logging.
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>$LOGFILE 2>&1

# OSD Startmessage incl. Start Date/Time.
STARTDATE="$(date +%a.%d.%b.%Y-%H:%M:%S)" && echo -e "\n\nJOB START -> $STARTDATE\n"
$WGET -O - -q "$BOXIP/web/message?text=Start%20Partitioning%20on%20${DEV}%20...%20->%20$STARTDATE&type=1&timeout=8" > /dev/null && sleep 3

# OSD Error Output.
osd_error_message() {
    sleep 11
	$WGET -O - -q "$BOXIP/web/message?text=ABORT%20---%20Details%20thereto%20in%3B%0A$LOGFILE%20&type=3" > /dev/null
	echo ""
}


echo -e "\nCheck if a Flash memory Image is running,\nso that $0 may work.\n"
img_check="$(grep "boot" $IMG_RUN_CHECKFILE | awk '{print $2}' | cut -d "." -f1)"
if [ "$img_check" = "$IMG_ON_MEDIA" ] ; then
	osd_error_message
	echo -e "\n... ABBORT ...\nthis Script $0 runs only \nif you start it from a Flash memory Image (Slots 1-4).\n" && exit 1
fi
echo -e "ok, Image runs in the Flash memory,\n$0 may work."

echo -e "\nCheck if your Device /dev/$DEV (SD-Card or USB Device) has been initialized.\n"
CHECK_1="$(parted -s /dev/${DEV} unit KiB print free | awk '/^ 1/ { print $NF }')"
if [ "$CHECK_1" = "kernel2" ] ; then
	CHECK_2="$(parted -s /dev/${DEV} unit KiB print free | awk '/^ 2/ { print $NF }')"
	if [ "$CHECK_2" = "rootfs2" ] ; then
		osd_error_message
		echo -e "\n... ABORT ...\nDevice /dev/$DEV has to be formatted (initialize) first\nbefore you can create Multiboot Slot Partitions on it."
		echo "you can do this via the GUI on your Box."
		echo -e "... ATTENTION ... -> do not initialize the wrong Device.\n" && exit 1
	fi
fi
echo -e "All ok -> Device /dev/$DEV (SD-Card or USB Device) is initialized.\n"


echo -e "\n## User Settings ##\nRESERVE: $RESERVE\nUSERDATA_FS: $USERDATA_FS\nUSERDATA_MOUNTPOINT: $USERDATA_MOUNTPOINT\nEXTRA_MB_SLOTSLIMIT: $EXTRA_MB_SLOTSLIMIT\n"


echo -e "\nCheck how much Slots are possible for Multiboot ...\n"
#DEV_SIZE="$(parted -s /dev/${DEV} unit KiB print free | sed '/^$/d' | grep -w "1" | awk '{print $3}' | tr -d '[:alpha:]')"
DEV_SIZE="$(parted -s /dev/${DEV} unit KiB print free | sed '/^$/d' | awk '/^ 1/ { print $3 }' | tr -d '[:alpha:]')"
DEV_SIZE=$((DEV_SIZE-$RESERVE))
echo "DEV_SIZE = $DEV_SIZE"

count=0
ROOT_PART_SIZE=2097152
KERNEL_PART_SIZE=16384
SLOT_SIZE=$((ROOT_PART_SIZE+$KERNEL_PART_SIZE))
if [ "$EXTRA_MB_SLOTSLIMIT" -lt "1" ] ; then
	EXTRA_MB_SLOTSLIMIT=1
fi
MB_PARTITIONSLIMIT=$EXTRA_MB_SLOTSLIMIT ; let ++MB_PARTITIONSLIMIT
while [ $DEV_SIZE -ge $SLOT_SIZE ] ; do
	count=$((count+1))
	SLOT_SIZE=$((ROOT_PART_SIZE+$KERNEL_PART_SIZE))
	SLOT_SIZE=$((SLOT_SIZE*$count))

	if [ $DEV_SIZE -lt $SLOT_SIZE ] ; then
		break
	elif [ "$count" = "$MB_PARTITIONSLIMIT" ] ; then
		MB_PARTITIONSLIMIT=$((MB_PARTITIONSLIMIT-1))
		echo -e "\nMultiboot Slotslimit ($MB_PARTITIONSLIMIT) reached." && break
	else
		PARTITIONS+=( "$count" )
		SLOTS+=( $((count+4)) )
	fi
done
echo -e "Slots which are possible for Multiboot-> ${SLOTS[@]}\n\n"


#echo -e "\numount /dev/${DEV}1 ..."
#umount /dev/${DEV}1
#if [ "$?" != "0" ] ; then
#	osd_error_message
#	echo -e "\n... ABORT ...\numount /dev/${DEV}1 has failed -> start $0 again.\n" && exit 1
#else
#	echo -e "\numount /dev/${DEV}1 was successful.\n"
#fi

mount_count=0
while mount | grep dev/${DEV}1 && [ "$?" = "0" ] ; do
	mount_count=$((mount_count+1))
	echo -e "\numount /dev/${DEV}1 ..."
	umount /dev/${DEV}1

	if [ "$?" = "0" ] ; then
		echo -e "\numount /dev/${DEV}1 was successful.\n" && break
	else
		if [ "$mount_count" = "3" ] ; then
			osd_error_message
			echo -e "\n... ABORT ...\numount /dev/${DEV}1 has failed 3 times,\ntry to umount it manually and/or start $0 again.\n" && exit 1
		fi

		echo -e "\numount /dev/${DEV}1 has failed,\ntry it again in 3 seconds ..."
		sleep 3
	fi
done


echo -e "\nCreate Slots ${SLOTS[@]}\non a SD-Card or USB Device ..."
count=2
count_partitions=1
startkernel=1024
endkernel=17408
startrootfs=17408
endrootfs=2114560
for i in ${PARTITIONS[@]} ; do
	if [ "$i" = "1" ] ; then
		echo -e "\nfor kernel${count} and rootfs${count} -> \$i must be similar to \$count_partitions"
		echo -e "\$i = $i\ncount = $count\ncount_partitions = $count_partitions\nstartkernel = $startkernel"
		echo -e "endkernel = $endkernel\nstartrootfs = $startrootfs\nendrootfs = $endrootfs\n"
		parted -s /dev/${DEV} \
			rm 1 \
			mklabel gpt \
			unit KiB mkpart kernel${count} $startkernel $endkernel \
			unit KiB mkpart rootfs${count} ext4 $startrootfs $endrootfs \
			print \
			quit
		echo -e "Continue ...\n\n"
		continue
	fi

	count=$((count+1))
	count_partitions=$((count_partitions+1))
	startkernel=$((startkernel+2113536))
	endkernel=$((endkernel+2113536))
	startrootfs=$((startrootfs+2113536))
	endrootfs=$((endrootfs+2113536))

	if [ "$i" = "$count_partitions" ] ; then
		echo "for kernel${count} and rootfs${count} -> \$i must be similar to \$count_partitions"
		echo -e "\$i = $i\ncount = $count\ncount_partitions = $count_partitions\nstartkernel = $startkernel"
		echo -e "endkernel = $endkernel\nstartrootfs = $startrootfs\nendrootfs = $endrootfs\n"
		parted -s /dev/${DEV} \
			unit KiB mkpart kernel${count} $startkernel $endkernel \
			unit KiB mkpart rootfs${count} ext4 $startrootfs $endrootfs \
			print \
			quit
	fi
done

DEV_SIZE="$(parted -s /dev/${DEV} unit KiB print free | sed '/^$/d' | awk 'END{print $2}' | tr -d '[:alpha:]')"

if [ $endrootfs -lt $DEV_SIZE ] ; then
	USERDATA_PART=yes
	echo -e "Create userdata Partition with the space which is left ...\n"
	parted -s /dev/${DEV} \
		unit KiB mkpart userdata $USERDATA_FS $endrootfs $DEV_SIZE \
		print \
		quit
fi
echo "All Partitions created."
echo -e "\nendrootfs = $endrootfs, DEV_SIZE = $DEV_SIZE\n" # to remove later


echo -e "\nnow format rootfs Partitions ...\n"
for i in ${PARTITIONS[@]} ; do
	i=$((i+$i))
	i=/dev/${DEV}${i}

	sleep 2 && umount $i 2> /dev/null && sleep 1
	mkfs.ext4 $i

	if [ "$?" != "0" ] ; then
		osd_error_message
		echo -e "\n... ABORT ...\nFormatting partition $i has failed -> start $0 again."
		echo -e "... BUT PLEASE NOTE ...\nyou need first to initialize your Device (/dev/${DEV}) again via GUI."
		echo -e "... ATTENTION ... -> do not initialize the incorrectness Device.\n" && exit 1
	else
		echo -e "Formatting partition $i was successful.\n\n"
	fi
done

FSTAB=/etc/fstab
create_new_line() {
	if [ -n "$(tail -c 1 $FSTAB)" ] ; then echo -e "\nwrite blank line at the end in $FSTAB ...\n" && echo "" >> $FSTAB ; fi
}

if [ "$USERDATA_PART" = "yes" ] ; then
	echo -e "and now format the userdata Partition ...\n"
	USERDATA_PARTITION=${#PARTITIONS[*]}
	USERDATA_PARTITION=$((USERDATA_PARTITION*2+1))
	USERDATA_PARTITION=/dev/${DEV}${USERDATA_PARTITION}
	sleep 3 && umount $USERDATA_PARTITION 2> /dev/null && sleep 2

	if [ "$USERDATA_FS" = "fat32" ] ; then
		mkfs.vfat $USERDATA_PARTITION
	elif [ "$USERDATA_FS" = "ext4" ] ; then
		mkfs.ext4 $USERDATA_PARTITION
	fi

	if [ "$?" != "0" ] ; then
		$WGET -O - -q "$BOXIP/web/message?text=Please%20Note%20%21%20%20Formatting%20the%20userdata%20Partition%20has%20failed%2C%0Atry%20it%20manually%2E%0Athe%20other%20Job%20was%20full%20ok%2E&type=1&timeout=10" > /dev/null && sleep 10
		echo -e "\n... IMPORTANT NOTICE ...\nFormatting the userdata Partition has failed,\ntry it manually.\n"
	else
		echo -e "\nFormatting the userdata Partition was successful.\n"


		# Writing userdata Mount in the /etc/fstab and mount it (original /etc/fstab will backed up).
		if [ -e $FSTAB_BACKUP ] ; then mv -f $FSTAB_BACKUP ${FSTAB_BACKUP}.old ; cp $FSTAB $FSTAB_BACKUP ; else cp $FSTAB $FSTAB_BACKUP ; fi

		echo -e "\nWriting userdata Partition ($USERDATA_PARTITION)\nin $FSTAB and mount it ...\n"
		UUID="$(blkid -o value -s UUID $USERDATA_PARTITION)"
		TYPE="$(blkid -o value -s TYPE $USERDATA_PARTITION)"
		OPTS="defaults"
		echo -e "## \$USERDATA_PARTITION DATA ##\nUSERDATA_PARTITION : $USERDATA_PARTITION\nUSERDATA_MOUNTPOINT : $USERDATA_MOUNTPOINT\nUUID : $UUID\nTYPE : $TYPE\nOPTS : $OPTS\n"

		MOUNT_LINE="$(echo -e "UUID=$UUID\t$USERDATA_MOUNTPOINT\t$TYPE\t$OPTS\t0  0")"
		if [ -e $LAST_USERDATA_MOUNT_FILE ] ; then
			LAST_UUID="$(grep "UUID" $LAST_USERDATA_MOUNT_FILE | awk '{print $1}')"
			REST_LAST_MOUNT="$(grep "UUID" $LAST_USERDATA_MOUNT_FILE | awk '{print $2"\t"$3"\t"$4"\t"$5"  "$6}')"
			echo -e "Last Mount for Userdata Partition in $FSTAB;\n${LAST_UUID} $REST_LAST_MOUNT\nis being replaced with;\n$MOUNT_LINE\n...\n"
			sed -i "s#$LAST_UUID.*#$MOUNT_LINE#g" $FSTAB
		else
			if grep "$USERDATA_MOUNTPOINT" $FSTAB > /dev/null; then
				echo -e "Last Mount for Userdata Partition in $FSTAB;\nwith Mountpoint -> $USERDATA_MOUNTPOINT\nis being replaced with;\n$MOUNT_LINE\n...\n"
				sed -i "s#.*$USERDATA_MOUNTPOINT.*#$MOUNT_LINE#g" $FSTAB
			else
				echo -e "Writing Mount for Userdata Partition;\n$MOUNT_LINE\nin $FSTAB ...\n"
				echo -e "$MOUNT_LINE\n" >> $FSTAB
				## finally delete potential empty lines in the /etc/fstab file, if necessary create a blank line at the end in the /etc/fstab file.
				sed -i '/^$/d' $FSTAB
				create_new_line
			fi
		fi

		NEWUUID_CHECK="$(grep "$USERDATA_MOUNTPOINT" $FSTAB | awk '{print $1}' | cut -d '=' -f2)"
		if [ "$NEWUUID_CHECK" = "$UUID" ] ; then
			echo -e "Writing the userdata Partition ($USERDATA_PARTITION)\nin $FSTAB was successful.\n"
		else
			echo -e "\n... IMPORTANT NOTICE ...\nWriting the userdata Partition ($USERDATA_PARTITION) in"
			echo -e "$FSTAB has failed, it's best to do this manually.\n"
		fi

		echo "$MOUNT_LINE" > $LAST_USERDATA_MOUNT_FILE
		
		mkdir -p $USERDATA_MOUNTPOINT
		mount -a
	fi
fi


echo -e "\nCheck respectively if it's necessary to create Startup Files ...\n"
count_startups=4
usb0_and_kernel_dev_count=-1
root_dev_count=0
for i in ${PARTITIONS[@]} ; do
	count_startups=$((count_startups+1))
	usb0_and_kernel_dev_count=$((usb0_and_kernel_dev_count+2))
	root_dev_count=$((root_dev_count+2))

	if [ -f $BOOT/STARTUP_${count_startups} ] ; then
		echo -e "File $BOOT/STARTUP_${count_startups} is present.\n"
	else
		STARTUP="boot usb0.${DEV}$usb0_and_kernel_dev_count 'root=/dev/${DEV}$root_dev_count rootfstype=ext4 kernel=/dev/${DEV}$usb0_and_kernel_dev_count"
		echo "$STARTUP $STARTUP_END" > $BOOT/STARTUP_${count_startups}
		chmod 755 $BOOT/STARTUP_${count_startups}

		if [ "$?" = "0" ] ; then
			echo -e "File $BOOT/STARTUP_${count_startups} has been created.\n"
		else
			$WGET -O - -q "$BOXIP/web/message?text=Please%20Note%20%21%20%20Creating%20File%20$BOOT/STARTUP_${count_startups}%20has%20failed%2C%0Acreate%20it%20manually%2E%0Athe%20other%20Job%20was%20full%20ok%2E&type=1&timeout=10" > /dev/null && sleep 10
			echo -e "\n... IMPORTANT NOTICE ...\nCreating File $BOOT/STARTUP_${count_startups} has failed,\ncreate it manually.\n"
		fi
	fi
done


# OSD Endmessage incl. Start Date/Time.
ENDDATE="$(date +%a.%d.%b.%Y-%H:%M:%S)" && echo -e "\nJOB END -> $ENDDATE\n\n"
$WGET -O - -q "$BOXIP/web/message?text=Partitioning%20on%20${DEV}%20was%20successful%20completed%20->%20$ENDDATE&type=1" > /dev/null


exit
