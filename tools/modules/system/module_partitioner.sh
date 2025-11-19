# shellcheck shell=bash
declare -A module_options
module_options+=(
	["module_partitioner,author"]="@igorpecovnik"
	["module_partitioner,maintainer"]="@igorpecovnik"
	["module_partitioner,feature"]="module_partitioner"
	["module_partitioner,example"]="new run create delete show getroot autoinstall help"
	["module_partitioner,desc"]="Partitioner manager TUI"
	["module_partitioner,status"]="review"
	["module_partitioner,doc_link"]="https://docs.armbian.com"
	["module_partitioner,group"]="System"
	["module_partitioner,port"]=""
	["module_partitioner,arch"]=""
)

function module_partitioner() {
	local title="Partitioner"

	# Read boot loader functions
	# We can have three function in platform_install.sh:
	# - write_uboot_platform <dir> <device>: function to write u-boot to a block device
	# - write_uboot_platform_mtd <dir> <device> <log> <mtd_devices>:
	#   	function to write u-boot to a mtd (eg. SPI flash) device
	#   	$1 = u-boot files directory
	#   	$2 = first MTD device path (e.g.: /dev/mtdblock0) - this is for backward compatibility before Armbian 23.nn
	#   	$3 = Log file name
	#   	$4 = :space: separated list of all MTD device names
	#            Note: MTD char device names are passed in format device_name:partition_label - e.g.: mtd0:SPL
	# - setup_write_uboot_platform: detect DEVICE to write uboot
	# shellcheck source=/dev/null
	[[ -f /usr/lib/u-boot/platform_install.sh ]] && source /usr/lib/u-boot/platform_install.sh

	# Start mtdcheck with probable MTD block device partitions:
	mtdcheck=$(grep 'mtdblock' /proc/partitions | awk '{print $NF}' | xargs)
	# Append mtdcheck with probable MTD char devices filtered for partition name(s)
	# containing "spl" or "boot" case insensitive,
	# since we are currently interested in MTD partitions for boot flashing only.
	# Note: The following statement will add matching MTD char device names
	#       combined with partition name (separated from devicename by a :colon:):
	#       mtd0:partition0_name mtd1:partition1_name ... mtdN:partitionN_name
	[[ -f /proc/mtd ]] && mtdcheck="$mtdcheck${mtdcheck:+ }$(grep -i -E '^mtd[0-9]+:.*(spl|boot).*' /proc/mtd | awk '{print $1$NF}' | sed 's/\"//g' | xargs)"

	command -v bc >/dev/null 2>&1 || apt-get install -y bc
	command -v ntfs-3g >/dev/null 2>&1 || apt-get install -y ntfs-3g
	command -v dialog >/dev/null 2>&1 || apt-get install -y dialog
	command -v parted >/dev/null 2>&1 || apt-get install -y parted
	command -v rsync >/dev/null 2>&1 || apt-get install -y rsync

	# Convert the example string to an array
	local commands
	IFS=' ' read -r -a commands <<< "${module_options["module_partitioner,example"]}"

	case "$1" in
		"${commands[0]}")
			echo "Install to partition $2"
			exit
		;;
		"${commands[1]}")

			while true; do

				# get all available targets
				${module_options["module_partitioner,feature"]} "${commands[4]}"

				list=()
				periodic=1
				while IFS="=" read -r key value; do
					case "$key" in
						"name") name="$value" ;;
						"size") size=$(printf "%14s" "$value") ;;
						"type") type=$(printf "%4s" "$value") ;;
						"fsused") fsused="$value" ;;
						"fstype") fstype="$value" ;;
						"mountpoint") : ;; # mountpoint not used currently
					esac
					if [ "$((periodic % 6))" -eq 0 ]; then
						if [[ "$type" == "disk" ]]; then
							# recognize devices features
							driveinfo=$(udevadm info --query=all --name="$name" | grep 'ID_MODEL=' | cut -d"=" -f2 | sed "s/_/ /g")
							drivebus=$(udevadm info --query=all --name="$name" | grep 'ID_BUS=' | cut -d"=" -f2 | sed "s/_/ /g")
							[[ $name == *mtdb* ]] && driveinfo="SPI flash"
							[[ $name == *nvme* ]] && driveinfo="M2 NVME solid state drive $driveinfo"
							# if smartmontools are installed, lets query more info
							if [[ $name == *nvme* ]] && command -v smartctl >/dev/null; then
								mapfile -t array < <(smartctl -ija "$name" | jq -r '
								.model_name,
								.nvme_smart_health_information_log.data_units_written,
								.temperature.current'
								)
								tbw=$(echo "${array[1]}" | awk '{ printf "%.0f\n", $1*500/1024/1024/1024; }')""
								temperature="${array[2]}℃"
								driveinfo="${array[0]} | TBW: ${tbw} | Temperature: ${temperature}"
							fi
							[[ $name == *mmc* ]] && driveinfo="eMMC or SD card"
							[[ $name == *sd* && $drivebus == usb ]] && driveinfo="USB storage $driveinfo"
							list+=("${name}" "$(printf "%-30s%12s" "$name" "$size")" "$driveinfo")
						fi # type is disk
					fi
					periodic=$((periodic + 1))
				done <<< "$devices"

				list_length=$((${#list[@]} / 3))
				selected_disk=$(dialog \
				--notags \
				--cancel-label "Cancel" \
				--ok-label "Install" \
				--extra-button \
				--extra-label "Advanced" \
				--erase-on-exit \
				--item-help \
				--title "Select destination drive" \
				--menu "\n Storage device                        Size" \
				$((list_length + 8)) 48 $((list_length + 1)) \
				"${list[@]}" 3>&1 1>&2 2>&3)
				exitstatus=$?

				case "$exitstatus" in
					0) ${module_options["module_partitioner,feature"]} "${commands[5]}" "$selected_disk" # auto install
						;;
					1) break
						;;
					3)
						# drive partitioning
						devices=$(
							lsblk -Alnp -io NAME,SIZE,FSUSED,TYPE,FSTYPE,MOUNTPOINT -e 252 --json \
							| jq --arg selected_disk "$selected_disk" '.blockdevices[]?
							| select((.name | test ($selected_disk))
							and (.name | test ("mtdblock0|nvme|mmcblk|sd"))
							and (.name | test ("boot") | not ))' \
							| jq -r 'to_entries|map("\(.key)=\(.value|tostring)")|.[]'
						)
						list=()
						periodic=1
						while IFS="=" read -r key value; do
								case "$key" in
									"name") name="$value" ;;
									"size") size=$(printf "%14s" "$value") ;;
									"type") type=$(printf "%4s" "$value") ;;
									"fsused") fsused="$value" ;;
									"fstype") fstype="$value" ;;
									"mountpoint") : ;; # mountpoint not used currently
								esac
								if [ "$((periodic % 6))" -eq 0 ]; then
									if [[ "$type" == "part" ]]; then
										#echo "$periodic $name $size $type $fsused $fstype $mountpoint"
										driveinfo=$(udevadm info --query=all --name="$name" | grep 'ID_MODEL=' | cut -d"=" -f2 | sed "s/_/ /g")
										drivebus=$(udevadm info --query=all --name="$name" | grep 'ID_BUS=' | cut -d"=" -f2 | sed "s/_/ /g")
										[[ $fstype == null ]] && fstype=""
										[[ $fsused == null ]] && fsused=""
										[[ $name == *mtdb* ]] && driveinfo="SPI flash"
										[[ $name == *nvme* ]] && driveinfo="M2 NVME solid state drive $driveinfo"
										[[ $name == *mmc* ]] && driveinfo="eMMC or SD card"
										[[ $name == *sd* && $drivebus == usb ]] && driveinfo="USB storage $driveinfo"
										list+=("${name}" "$(printf "%-10s%14s%9s%9s" "${name}" "${fstype}" "${size}" "${fsused}")" "$driveinfo")
									fi
								fi
								periodic=$((periodic + 1))
						done <<< "$devices"
						;;
					esac
				list_length=$((${#list[@]} / 3))
				partitioner=$(dialog \
				--notags \
				--cancel-label "Cancel" \
				--ok-label "Install" \
				--erase-on-exit \
				--extra-button \
				--item-help \
				--extra-label "Manage" \
				--title "Select or manage partitions" \
				--menu "\n Partition        FS type     Size     Used" \
				$((list_length + 8)) 48 $((list_length + 1)) \
				"${list[@]}" 3>&1 1>&2 2>&3)
				exitstatus=$?
				case "$exitstatus" in
					0) ${module_options["module_partitioner,feature"]} "${commands[0]}" "$partitioner" ;;
					3) ${module_options["module_partitioner,feature"]} "${commands[3]}" "$partitioner" ;;
					1) break ;;
				esac
			done
		;;
		"${commands[2]}")
			echo "Select $3"
			exit
		;;
		"${commands[3]}")
			# get additional info from partition
			local size
			size=$(lsblk -Alnbp -io SIZE "$2" | xargs -I {} echo "scale=0;{}/1024/1024/1024" | bc -l)
			local fstype
			fstype=$(lsblk -Alnbp -io FSTYPE "$2")
			local minimal
			minimal=$(ntfsresize --info "$2" -m | tail -1 | grep -Eo '[0-9]{1,10}' | xargs -I {} echo "scale=0;{}/1024" | bc -l)
			while true; do
				shrinkedsize=$(dialog --title "Shrinking $fstype partition $2" \
				--inputbox "\nValid size between ${minimal}-${size} GB" 9 50 "$(( minimal + size / 2 ))" 3>&1 1>&2 2>&3)
				exitstatus=$?
				if [[ $shrinkedsize -ge $minimal ]]; then
					break
				fi
			done
			if ntfsresize --no-action --size "${shrinkedsize}G" "$2" >/dev/null && [[ $exitstatus -ne 1 ]]; then
				ntfsresize -f --size "${shrinkedsize}G" "$2"
			fi
			read -r
			# Removal logic here
		;;
		"${commands[4]}")
			#recognize_root
			root_uuid=$(sed -e 's/^.*root=//' -e 's/ .*$//' < /proc/cmdline)
			root_partition=$(blkid | tr -d '":' | grep "${root_uuid}" | awk '{print $1}')
			root_partition_name=$(echo "$root_partition" | sed 's/\/dev\///g')
			root_partition_device_name=$(lsblk -ndo pkname "$root_partition")
			root_partition_device=/dev/$root_partition_device_name
			# list all devices except rootfs
			devices=$(
				lsblk -Alnp -io NAME,SIZE,FSUSED,TYPE,FSTYPE,MOUNTPOINT -e 252 --json \
				| jq --arg root_partition_device "$root_partition_device" '.blockdevices[]?
				| select((.name | test ($root_partition_device) | not)
				and (.name | test ("mtdblock0|nvme|mmcblk|sd"))
				and (.name | test ("boot|mtdb") | not ))' \
				| jq -r 'to_entries|map("\(.key)=\(.value|tostring)")|.[]'
			)
		;;
		"${commands[5]}")
			# autoinstall - call armbian-install logic
			_armbian_install_main "$@"
		;;
		"${commands[6]}")

				if [[ $(type -t write_uboot_platform_mtd) == function ]]; then
					if dialog --title "$title" --backtitle "$backtitle" --yesno \
						"Do you want to write the bootloader to MTD Flash?\n\nIt is required if you have not done it before or if you have some non-Armbian bootloader in this flash." 8 60; then
						write_uboot_to_mtd_flash "$DIR" "$mtdcheck"
					fi
				fi

			echo "Delete $2"
			read -r
			# Removal logic here
		;;
		"${commands[7]}")
			echo -e "\nUsage: ${module_options["module_partitioner,feature"]} <command>"
			echo -e "Commands:  ${module_options["module_partitioner,example"]}"
			echo "Available commands:"
			echo -e "\trun\t- Run $title."
			echo
		;;
		*)
			${module_options["module_partitioner,feature"]} "${commands[7]}"
		;;
	esac
}

# ============================================================================
# Armbian Install Functions - Integrated from armbian-install.sh
# ============================================================================

# Create boot and root file system
# "$1" = boot
# "$2" = root (Example: create_armbian "/dev/nand1" "/dev/sda3")
# "$3" = selected UEFI root target
create_armbian()
{
	[[ -n "$3" ]] && diskcheck=$3

	# create mount points, mount and clean
	local TempDir
	TempDir=$(mktemp -d /mnt/armbian-install.XXXXXX || exit 2)
	sync && mkdir -p "${TempDir}"/bootfs "${TempDir}"/rootfs
	if [[ $eMMCFilesystemChoosen =~ ^(btrfs|f2fs)$ ]]; then
		[[ -n $1 ]] && mount "${1::-1}1" "${TempDir}"/bootfs
		[[ -n $2 ]] && ( mount -o compress-force=zlib "$2" "${TempDir}"/rootfs 2> /dev/null || mount "$2" "${TempDir}"/rootfs )
	else
		[[ -n $2 ]] && ( mount -o compress-force=zlib "$2" "${TempDir}"/rootfs 2> /dev/null || mount "$2" "${TempDir}"/rootfs )
		[[ -n $1 && $1 != "mtd" ]] && mount "$1" "${TempDir}"/bootfs
	fi
	rm -rf "${TempDir}"/bootfs/* "${TempDir}"/rootfs/*

	# sata root part
	local satauuid
	satauuid=$(blkid -o export "$2" | grep -w UUID)

	# write information to log
	{
		echo -e "\nOld UUID:  ${root_uuid}"
		echo "SD UUID:   $sduuid"
		echo "SATA UUID: $satauuid"
		echo "eMMC UUID: $emmcuuid $eMMCFilesystemChoosen"
		echo "Boot: \$1 $1 $eMMCFilesystemChoosen"
		echo "Root: \$2 $2 $FilesystemChoosen"
	} >> "$logfile"

	# calculate usage and see if it fits on destination
	local USAGE DEST
	USAGE=$(df -BM | grep ^/dev | head -1 | awk '{print $3}' | tr -cd '[0-9]. \n')
	DEST=$(df -BM | grep ^/dev | grep "${TempDir}"/rootfs | awk '{print $4}' | tr -cd '[0-9]. \n')
	if [[ $USAGE -gt $DEST ]]; then
		dialog --title "$title" --backtitle "$backtitle" --colors --infobox\
		"\n\Z1Partition too small.\Zn Needed: $USAGE MB Avaliable: $DEST MB" 5 60
		umount_device "$1"; umount_device "$2"
		exit 3
	fi

	if [[ $1 == *nand* ]]; then
		# creating nand boot. Copy precompiled uboot
		rsync -aqc "$BOOTLOADER"/* "${TempDir}"/bootfs
	fi

	# write information to log
	{
		echo "Usage: $USAGE"
		echo -e "Dest: $DEST\n\n/etc/fstab:"
		cat /etc/fstab
		echo -e "\n/etc/mtab:"
		grep '^/dev/' /etc/mtab | grep -E -v "log2ram|folder2ram" | sort
		echo -e "\nFiles currently open for writing:"
		lsof / 2>/dev/null | awk 'NR==1 || $4~/[0-9][uw]/' | grep -v "^COMMAND"
		echo -e "\nTrying to stop running services to minimize open files:\c"
		stop_running_services "nfs-|smbd|nmbd|winbind|ftpd|netatalk|monit|cron|webmin|rrdcached"
		stop_running_services "fail2ban|ramlog|folder2ram|postgres|mariadb|mysql|postfix|mail|nginx|apache|snmpd"
		pkill dhclient 2>/dev/null
		LANG=C echo -e "\n\nChecking again for open files:"
		lsof / 2>/dev/null | awk 'NR==1 || $4~/[0-9][uw]/' | grep -v "^COMMAND"
	} >> "$logfile"

	# count files is needed for progress bar
	dialog --title " $title " --backtitle "$backtitle" --infobox "\n  Counting files ... few seconds." 5 60
	local TODO
	TODO=$(rsync -avx --delete --stats --exclude-from="$EX_LIST" / "${TempDir}"/rootfs | grep "Number of files:"|awk '{print $4}' | tr -d '.,')
	echo -e "\nCopying ${TODO} files to $2. \c" >> "$logfile"

	# creating rootfs
	# Speed copy increased x10
	# Variables for interfacing with rsync progress
	local nsi_conn_path nsi_conn_done nsi_conn_progress
	nsi_conn_path="${TempDir}/nand-sata-install"
	nsi_conn_done="${nsi_conn_path}/done"
	nsi_conn_progress="${nsi_conn_path}/progress"
	mkdir -p "${nsi_conn_path}"
	echo 0 >"${nsi_conn_progress}"
	echo no >"${nsi_conn_done}"

	# Launch rsync in background
	{ \
	rsync -avx --delete --exclude-from="$EX_LIST" / "${TempDir}"/rootfs | \
	nl | awk '{ printf "%.0f\n", 100*$1/"'"$TODO"'" }' \
	> "${nsi_conn_progress}" ;
	# create empty persistent journal directory if it exists before install
	[ -d /var/log.hdd/journal ] && mkdir "${TempDir}"/rootfs/var/log/journal
	# save exit code from rsync
	echo "${PIPESTATUS[0]}" >"${nsi_conn_done}"
	} &

	# while variables
	local rsync_copy_finish rsync_progress prev_progress rsync_done
	rsync_copy_finish=0
	rsync_progress=0
	prev_progress=0
	rsync_done=""
	while [ "${rsync_copy_finish}" -eq 0 ]; do
		# Sometimes reads the progress file while writing and only partial numbers (like 1 when is 15)
		prev_progress=${rsync_progress}
		rsync_progress=$(tail -n1 "${nsi_conn_progress}")
		if [[ -z ${rsync_progress} ]]; then
			rsync_progress=${prev_progress}
		fi
		if [ "${prev_progress}" -gt "${rsync_progress}" ]; then
			rsync_progress=${prev_progress}
		fi
		echo "${rsync_progress}"
		# finish the while if the rsync is finished
		rsync_done=$(cat "${nsi_conn_done}")
		if [[ "${rsync_done}" != "no" ]]; then
			if [[ ${rsync_done} -eq 0 ]]; then
				rm -rf "${nsi_conn_path}"
				rsync_copy_finish=1
			else
				# if rsync return error
				echo "Error: could not copy rootfs files, exiting"
				exit 4
			fi
		else
			sleep 0.5
		fi

	done | \
	dialog --backtitle "$backtitle" --title " $title " --gauge "\n\n  Transferring rootfs to $2 ($USAGE MB). \n\n \
	 This will take approximately $(( $((USAGE/300)) * 1 )) minutes to finish. Please wait!\n\n" 11 80

	# run rsync again to silently catch outstanding changes between / and "${TempDir}"/rootfs/
	dialog --title "$title" --backtitle "$backtitle" --infobox "\n               Cleaning up ... Almost done." 5 60
	rsync -avx --delete --exclude-from="$EX_LIST" / "${TempDir}"/rootfs >/dev/null 2>&1

	# mark OS as transferred
	if ! grep -q "INSTALLED=true" /etc/armbian-image-release; then
		echo "INSTALLED=true" >> "${TempDir}"/rootfs/etc/armbian-image-release
	fi

	# creating fstab from scratch
	rm -f "${TempDir}"/rootfs/etc/fstab
	mkdir -p "${TempDir}"/rootfs/etc "${TempDir}"/rootfs/media/mmcboot "${TempDir}"/rootfs/media/mmcroot

	# Restore TMP and swap
	echo "# <file system>					<mount point>	<type>	<options>							<dump>	<pass>" > "${TempDir}"/rootfs/etc/fstab
	echo "tmpfs						/tmp		tmpfs	defaults,nosuid							0	0" >> "${TempDir}"/rootfs/etc/fstab
	grep swap /etc/fstab >> "${TempDir}"/rootfs/etc/fstab

	# creating fstab, kernel and boot script for NAND partition
	if [[ $1 == *nand* ]]; then
		echo "Finishing installation to NAND." >> "$logfile"
		REMOVESDTXT="and remove SD to boot from NAND"
		echo "$1 /boot vfat	defaults 0 0" >> "${TempDir}"/rootfs/etc/fstab
		echo "$2 / ext4 defaults,noatime,commit=120,errors=remount-ro 0 1" >> "${TempDir}"/rootfs/etc/fstab
		dialog --title "$title" --backtitle "$backtitle" --infobox "\nConverting kernel ... few seconds." 5 60
		mkimage -A arm -O linux -T kernel -C none -a "0x40008000" -e "0x40008000" -n "Linux kernel" -d \
			/boot/zImage "${TempDir}"/bootfs/uImage >/dev/null 2>&1
		cp /boot/script.bin "${TempDir}"/bootfs/

		if [[ $DEVICE_TYPE != "a13" ]]; then
			cat <<-EOF > "${TempDir}"/bootfs/uEnv.txt
			console=ttyS0,115200
			root=$2 rootwait
			extraargs="console=tty1 hdmi.audio=EDID:0 disp.screen0_output_mode=EDID:0 consoleblank=0 loglevel=1"
			EOF
		else
			cat <<-EOF > "${TempDir}"/bootfs/uEnv.txt
			console=ttyS0,115200
			root=$2 rootwait
			extraargs="consoleblank=0 loglevel=1"
			EOF
		fi

		sync

		[[ $DEVICE_TYPE = "a20" ]] && echo "machid=10bb" >> "${TempDir}"/bootfs/uEnv.txt
		# ugly hack becouse we don't have sources for A10 nand uboot
		if [[ $ID == Cubieboard || $BOARD_NAME == Cubieboard || $ID == "Lime A10" || $BOARD_NAME == "Lime A10" ]]; then
			cp "${TempDir}"/bootfs/uEnv.txt "${TempDir}"/rootfs/boot/uEnv.txt
			cp "${TempDir}"/bootfs/script.bin "${TempDir}"/rootfs/boot/script.bin
			cp "${TempDir}"/bootfs/uImage "${TempDir}"/rootfs/boot/uImage
		fi
		umount_device "/dev/nand"
		tune2fs -o journal_data_writeback /dev/nand2 >/dev/null 2>&1
		tune2fs -O ^has_journal /dev/nand2 >/dev/null 2>&1
		e2fsck -f /dev/nand2 >/dev/null 2>&1
	fi

	# Boot from eMMC, root = eMMC or SATA / USB
	if [[ ($2 == ${emmccheck}p* || $1 == ${emmccheck}p*) && $DEVICE_TYPE != "uefi" ]]; then
		local targetuuid choosen_fs
		if [[ "$2" == "${DISK_ROOT_PART}" ]]; then
			targetuuid=$satauuid
			choosen_fs=$FilesystemChoosen
			echo "Finalizing: boot from eMMC, rootfs on USB/SATA/NVMe." >> "$logfile"
			if [[ $eMMCFilesystemChoosen =~ ^(btrfs|f2fs)$ ]]; then
				echo "$emmcuuid	/media/mmcroot  $eMMCFilesystemChoosen	${mountopts[$eMMCFilesystemChoosen]}" >> "${TempDir}"/rootfs/etc/fstab
			fi
		else
			targetuuid=$emmcuuid
			choosen_fs=$eMMCFilesystemChoosen
			echo "Finishing full install to eMMC." >> "$logfile"
		fi

		# fix that we can have one exlude file
		cp -R /boot "${TempDir}"/bootfs
		# old boot scripts
		[[ -f "${TempDir}"/bootfs/boot/boot.cmd ]] && sed -e 's,root='"$root_uuid"',root='"$targetuuid"',g' -i "${TempDir}"/bootfs/boot/boot.cmd
		# new boot scripts
		if [[ -f "${TempDir}"/bootfs/boot/armbianEnv.txt ]]; then
			sed -e 's,rootdev=.*,rootdev='"$targetuuid"',g' -i "${TempDir}"/bootfs/boot/armbianEnv.txt
			grep -q '^rootdev' "${TempDir}"/bootfs/boot/armbianEnv.txt || echo "rootdev=$targetuuid" >> "${TempDir}"/bootfs/boot/armbianEnv.txt
		else
			[[ -f "${TempDir}"/bootfs/boot/boot.cmd ]] && sed -e 's,setenv rootdev.*,setenv rootdev '"$targetuuid"',g' -i "${TempDir}"/bootfs/boot/boot.cmd
			[[ -f "${TempDir}"/bootfs/boot/boot.ini ]] && sed -e 's,^setenv rootdev.*$,setenv rootdev "'"$targetuuid"'",' -i "${TempDir}"/bootfs/boot/boot.ini
			[[ -f "${TempDir}"/rootfs/boot/boot.ini ]] && sed -e 's,^setenv rootdev.*$,setenv rootdev "'"$targetuuid"'",' -i "${TempDir}"/rootfs/boot/boot.ini
		fi

		if [[ -f "${TempDir}"/bootfs/boot/extlinux/extlinux.conf ]]; then
			sed -e 's,root='"$root_uuid"',root='"$targetuuid"',g' -i "${TempDir}"/bootfs/boot/extlinux/extlinux.conf
			[[ -f "${TempDir}"/bootfs/boot/boot.cmd ]] && rm "${TempDir}"/bootfs/boot/boot.cmd
		else
			mkimage -C none -A arm -T script -d "${TempDir}"/bootfs/boot/boot.cmd "${TempDir}"/bootfs/boot/boot.scr	>/dev/null 2>&1 || (echo 'Error while creating U-Boot loader image with mkimage' >&2 ; exit 5)
		fi

		# fstab adj
		if [[ "$1" != "$2" ]]; then
			echo "$emmcbootuuid	/media/mmcboot	ext4    ${mountopts[ext4]}" >> "${TempDir}"/rootfs/etc/fstab
			echo "/media/mmcboot/boot   				/boot		none	bind								0       0" >> "${TempDir}"/rootfs/etc/fstab
		fi
		# if the rootfstype is not defined as cmdline argument on armbianEnv.txt
		if ! grep -qE '^rootfstype=.*' "${TempDir}"/bootfs/boot/armbianEnv.txt; then
			[[ -f "${TempDir}"/bootfs/boot/armbianEnv.txt ]] && echo "rootfstype=$choosen_fs" >> "${TempDir}"/bootfs/boot/armbianEnv.txt
		fi

		if [[ $eMMCFilesystemChoosen =~ ^(btrfs|f2fs)$ ]]; then
			echo "$targetuuid	/		$choosen_fs	${mountopts[$choosen_fs]}" >> "${TempDir}"/rootfs/etc/fstab
			[[ -n ${emmcswapuuid} ]] && sed -e 's,/var/swap.*,'"$emmcswapuuid"' 	none		swap	sw								0	0,g' -i "${TempDir}"/rootfs/etc/fstab
			if [[ -f "${TempDir}"/bootfs/boot/armbianEnv.txt ]]; then
				sed -e 's,rootfstype=.*,rootfstype='"$eMMCFilesystemChoosen"',g' -i "${TempDir}"/bootfs/boot/armbianEnv.txt
			else
				echo 'rootfstype='"$eMMCFilesystemChoosen" >>"${TempDir}"/bootfs/boot/armbianEnv.txt
			fi
		else
			[[ -f "${TempDir}"/bootfs/boot/armbianEnv.txt ]] && sed -e 's,rootfstype=.*,rootfstype='"$choosen_fs"',g' -i "${TempDir}"/bootfs/boot/armbianEnv.txt
			echo "$targetuuid	/		$choosen_fs	${mountopts[$choosen_fs]}" >> "${TempDir}"/rootfs/etc/fstab
		fi

		if [[ $(type -t write_uboot_platform) != function ]]; then
			echo "Error: no u-boot package found, exiting"
			exit 6
		fi
		write_uboot_platform "$DIR" "$emmccheck"

	fi

	# Boot from SD card, root = SATA / USB
	if [[ "$2" == "${DISK_ROOT_PART}" && -z "$1" && "$DEVICE_TYPE" != "uefi" ]]; then
		echo -e "Finishing transfer to disk, boot from SD/eMMC" >> "$logfile"
		[[ -f /boot/boot.cmd ]] && sed -e 's,root='"$root_uuid"',root='"$satauuid"',g' -i /boot/boot.cmd
		[[ -f /boot/boot.ini ]] && sed -e 's,^setenv rootdev.*$,setenv rootdev "'"$satauuid"'",' -i /boot/boot.ini
		# new boot scripts
		if [[ -f /boot/armbianEnv.txt ]]; then
			sed -e 's,rootdev=.*,rootdev='"$satauuid"',g' -i /boot/armbianEnv.txt
			grep -q '^rootdev' /boot/armbianEnv.txt || echo "rootdev=$satauuid" >> /boot/armbianEnv.txt
			sed -e 's,rootfstype=.*,rootfstype='"$FilesystemChoosen"',g' -i /boot/armbianEnv.txt
			grep -q '^rootfstype' /boot/armbianEnv.txt || echo "rootfstype=$FilesystemChoosen" >> /boot/armbianEnv.txt
		else
			sed -e 's,setenv rootdev.*,setenv rootdev '"$satauuid"',' -i /boot/boot.cmd
			sed -e 's,setenv rootdev.*,setenv rootdev '"$satauuid"',' -i /boot/boot.ini
			sed -e 's,setenv rootfstype.*,setenv rootfstype '"$FilesystemChoosen"',' -i /boot/boot.cmd
			sed -e 's,setenv rootfstype.*,setenv rootfstype '"$FilesystemChoosen"',' -i /boot/boot.ini
		fi
		if [[ -f /bootfs/boot/extlinux/extlinux.conf ]]; then
			sed -e 's,root='"$root_uuid"',root='"$satauuid"',g' -i /boot/extlinux/extlinux.conf
			[[ -f /boot/boot.cmd ]] && rm /boot/boot.cmd
		fi
		if [[ -f /boot/boot.cmd ]]; then
			if ! mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr >/dev/null 2>&1; then
				echo 'Error while creating U-Boot loader image with mkimage' >&2
				exit 7
			fi
		fi
		mkdir -p "${TempDir}"/rootfs/media/mmc/boot
		{
			echo "${sduuid}	/media/mmcboot	ext4    ${mountopts[ext4]}"
			echo "/media/mmcboot/boot  				/boot		none	bind								0       0"
			echo "$satauuid	/		$FilesystemChoosen	${mountopts[$FilesystemChoosen]}"
		} >> "${TempDir}"/rootfs/etc/fstab
		# recreate swap file if already existing (might be missing since zram only)
		if [ -f /var/swap ]; then
			fallocate -l 128M "${TempDir}"/rootfs/var/swap || dd if=/dev/zero of="${TempDir}"/rootfs/var/swap bs=1M count=128 status=noxfer
			mkswap "${TempDir}"/rootfs/var/swap
		fi
	fi

	if [[ "$2" == "${DISK_ROOT_PART}" && -z "$1" && "$DEVICE_TYPE" = "uefi" ]]; then
		# create swap file size of your memory so we can use it for S4
		local MEM_TOTAL
		MEM_TOTAL=$(awk '/MemTotal/ {print $2}' /proc/meminfo)

		# but no more then 16Gb
		[[ ${MEM_TOTAL} -gt 16107868 ]] && MEM_TOTAL=16107868
		dd if=/dev/zero of="${TempDir}"/rootfs/swapfile bs="${MEM_TOTAL}" count=1024 conv=notrunc >> "$logfile"

		mkswap "${TempDir}"/rootfs/swapfile >> "$logfile"
		chmod 0600 "${TempDir}"/rootfs/swapfile
		sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/\"$/ resume=UUID=$(findmnt -no UUID -T "${TempDir}"/rootfs/swapfile) resume_offset=$(filefrag -v "${TempDir}"/rootfs/swapfile |grep " 0:"| awk '{print $4}' | cut -d"." -f1)\"/" "${TempDir}"/rootfs/etc/default/grub.d/98-armbian.cfg

		echo "GRUB_DISABLE_OS_PROBER=false" >> "${TempDir}"/rootfs/etc/default/grub.d/98-armbian.cfg

		{
			echo "$satauuid	/		$FilesystemChoosen	${mountopts[$FilesystemChoosen]}"
			echo "UUID=$(lsblk -io KNAME,LABEL,UUID,PARTLABEL | grep "$diskcheck" | grep -i efi | awk '{print $3}')				/boot/efi		vfat	 defaults 0 2"
			echo "/swapfile none swap sw 0 0"
		} >> "${TempDir}"/rootfs/etc/fstab

		cat <<-hibernatemenu >"${TempDir}"/rootfs/etc/polkit-1/localauthority/50-local.d/com.ubuntu.enable-hibernate.pkla
		[Re-enable hibernate by default in upower]
		Identity=unix-user:*
		Action=org.freedesktop.upower.hibernate
		ResultActive=yes

		[Re-enable hibernate by default in logind]
		Identity=unix-user:*
		Action=org.freedesktop.login1.hibernate;org.freedesktop.login1.handle-hibernate-key;org.freedesktop.login1;org.freedesktop.login1.hibernate-multiple-sessions;org.freedesktop.login1.hibernate-ignore-inhibit
		ResultActive=yes
		hibernatemenu

		efi_partition=$(LC_ALL=C fdisk -l "/dev/$diskcheck" 2>/dev/null | grep "EFI" | awk '{print $1}')

		echo "Install GRUB to $efi_partition"
		mkdir -p "${TempDir}"/rootfs/{dev,proc,sys}
		mount "$efi_partition" "${TempDir}"/rootfs/boot/efi
		mount --bind /dev "${TempDir}"/rootfs/dev
		mount --make-rslave --bind /dev/pts "${TempDir}"/rootfs/dev/pts
		mount --bind /proc "${TempDir}"/rootfs/proc
		mount --make-rslave --rbind /sys "${TempDir}"/rootfs/sys
		local arch_target
		arch_target=$([[ $(arch) == x86_64 ]] && echo "x86_64-efi" || echo "arm64-efi")
		chroot "${TempDir}/rootfs/" /bin/bash -c "grub-install --target=$arch_target --efi-directory=/boot/efi --bootloader-id=Armbian" >> "$logfile"
		chroot "${TempDir}/rootfs/" /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg" >> "$logfile"
		grep "${TempDir}"/rootfs/sys /proc/mounts | cut -f2 -d" " | sort -r | xargs umount -n
		umount "${TempDir}"/rootfs/proc
		umount "${TempDir}"/rootfs/dev/pts
		umount "${TempDir}"/rootfs/dev
		umount "${TempDir}"/rootfs/boot/efi
	fi

	# Boot from MTD flash, root = SATA / USB
	if [[ $1 == *mtd* ]]; then
		if [[ -f "${TempDir}"/rootfs/boot/armbianEnv.txt ]]; then
			sed -e 's,rootdev=.*,rootdev='"$satauuid"',g' -i "${TempDir}"/rootfs/boot/armbianEnv.txt
		fi
		if [[ -f "${TempDir}"/rootfs/boot/extlinux/extlinux.conf ]]; then
			sed -e 's,root='"$root_uuid"',root='"$satauuid"',g' -i "${TempDir}"/rootfs/boot/extlinux/extlinux.conf
		fi
		echo "$satauuid	/		$FilesystemChoosen	${mountopts[$FilesystemChoosen]}" >> "${TempDir}"/rootfs/etc/fstab
	fi

	# recreate OMV mounts at destination if needed
	if grep -q ' /srv/' /etc/fstab && [ -f /etc/default/openmediavault ]; then
		echo -e '# >>> [openmediavault]' >> "${TempDir}"/rootfs/etc/fstab
		grep ' /srv/' /etc/fstab | while read -r REPLY; do
			echo "${REPLY}" >> "${TempDir}"/rootfs/etc/fstab
			local mount_point
			mount_point=$(awk -F" " '{print $2}' <<<"${REPLY}")
			mkdir -p "${TempDir}/rootfs${mount_point}"
			chmod 700 "${TempDir}/rootfs${mount_point}"
		done
		echo -e '# <<< [openmediavault]' >> "${TempDir}"/rootfs/etc/fstab
	fi

	{
		echo -e "\nChecking again for open files:"
		lsof / | awk 'NR==1 || $4~/[0-9][uw]/' | grep -v "^COMMAND"
		LANG=C echo -e "\n$(date): Finished\n\n"
	} >> "$logfile"
	cat "$logfile" > "${TempDir}"/rootfs"$logfile"
	sync

	umount "${TempDir}"/rootfs
	mountpoint -q "${TempDir}"/bootfs && umount "${TempDir}"/bootfs
}

# Accept device as parameter: for example /dev/sda unmounts all their mounts
umount_device()
{
	if [[ -n $1 ]]; then
		local device="$1"
		for n in "${device}"*; do
			if [[ $device != "$n" ]]; then
				if mount|grep -q "$n"; then
					umount -l "$n" >/dev/null 2>&1
				fi
			fi
		done
	fi
}

show_nand_warning()
{
	local temp_rc
	temp_rc=$(mktemp)
	cat <<-'EOF' > "$temp_rc"
	screen_color = (WHITE,RED,ON)
	EOF
	local warn_text="You are installing the system to sunxi NAND.

	This is not recommended as NAND has \Z1worse performance
	and reliability\Zn than a good SD card.

	You have been warned."

	DIALOGRC="$temp_rc" dialog --title "NAND warning" --backtitle "$backtitle" --colors \
		--ok-label "I understand and agree" --msgbox "$warn_text" 10 70
}

# formatting sunxi NAND - no parameters, fixed solution.
format_nand()
{
	[[ ! -e /dev/nand ]] && echo '/dev/nand does not exist' >&2 && exit 8

	show_nand_warning

	dialog --title "$title" --backtitle "$backtitle" --infobox "\n            Formatting ... up to one minute." 5 60
	if [[ $DEVICE_TYPE = "a20" ]]; then
		(echo y;) | sunxi-nand-part -f a20 /dev/nand 65536 'bootloader 65536' 'linux 0' >> "$logfile" 2>&1
	else
		(echo y;) | sunxi-nand-part -f a10 /dev/nand 65536 'bootloader 65536' 'linux 0' >> "$logfile" 2>&1
	fi

	mkfs.vfat /dev/nand1 >> "$logfile" 2>&1
	mkfs.ext4 -qF /dev/nand2 >> "$logfile" 2>&1
}

# formatting eMMC [device] example /dev/mmcblk1 - one can select filesystem type
format_emmc()
{
	# choose and create fs
	local BTRFS FilesystemTargets FilesystemOptions FilesystemCmd FilesystemChoices
	IFS=" " read -r -a FilesystemOptions <<< ""
	BTRFS=$(grep -o btrfs /proc/filesystems)
	FilesystemTargets="1 ext4 2 f2fs"
	if [[ -n "$BTRFS" ]] && ! uname -r | grep -q '^3.'; then
		FilesystemTargets="$FilesystemTargets 3 $BTRFS"
	fi
	IFS=' ' read -r -a FilesystemOptions <<< "$FilesystemTargets"

	FilesystemCmd=(dialog --title "Select filesystem type for eMMC $1" --backtitle "$backtitle" --menu "\n" 10 60 16)
	if ! FilesystemChoices=$("${FilesystemCmd[@]}" "${FilesystemOptions[@]}" 2>&1 >/dev/tty); then
		exit 9
	fi
	eMMCFilesystemChoosen=${FilesystemOptions[(2*$FilesystemChoices)-1]}

	# deletes all partitions on eMMC drive
	dd bs=1 seek=446 count=64 if=/dev/zero of="$1" >/dev/null 2>&1
	# calculate capacity and reserve some unused space to ease cloning of the installation
	local QUOTED_DEVICE CAPACITY LASTSECTOR
	QUOTED_DEVICE="${1//\//\\/}"
	CAPACITY=$(parted "$1" unit s print -sm | awk -F":" "/^${QUOTED_DEVICE}/ {printf (\"%0d\", \$2 / ( 1024 / \$4 ))}")

	# We use 16MiB to align partitions which may overestimate the erase block
	# size of a NAND device. Overestimating is harmless. (512 byte
	# sectors, so we use 32768 as divider and substract 1)
	if [[ $CAPACITY -lt 4000000 ]]; then
		LASTSECTOR=$(( 32768 * $(parted "$1" unit s print -sm | awk -F":" "/^${QUOTED_DEVICE}/ {printf (\"%0d\", ( \$2 * 98 / 3276800))}") -1 ))
	else
		LASTSECTOR=$(( 32768 * $(parted "$1" unit s print -sm | awk -F":" "/^${QUOTED_DEVICE}/ {printf (\"%0d\", ( \$2 * 99 / 3276800))}") -1 ))
	fi

	# get target partition table type from the root partition device
	local PART_TABLE_TYPE
	PART_TABLE_TYPE=$(parted "$root_partition_device" print -sm | awk -F ":" -v pattern="$root_partition_device" '$0 ~ pattern {print $6}')

	parted -s "$1" -- mklabel "$PART_TABLE_TYPE"
	dialog --title "$title" --backtitle "$backtitle" --infobox "\nFormating $1 to $eMMCFilesystemChoosen ... please wait." 5 60
	# we can't boot from btrfs or f2fs
	if [[ $eMMCFilesystemChoosen =~ ^(btrfs|f2fs)$ ]]; then
		local partedFsType DEFAULT_BOOTSIZE DEFAULT_BOOTSIZE_SECTORS
		partedFsType="${eMMCFilesystemChoosen}"
		if [[ $eMMCFilesystemChoosen == "f2fs" ]]; then
			partedFsType=''
		fi

		# default boot partition size, in MiB
		DEFAULT_BOOTSIZE=512

		# (convert to sectors for partitioning)
		DEFAULT_BOOTSIZE_SECTORS=$(((DEFAULT_BOOTSIZE * 1024 * 1024) / 512))

		# check if the filesystem tools are actually installed
		if ! command -v "mkfs.${eMMCFilesystemChoosen}" >/dev/null 2>&1; then
			echo "Error: Filesystem tools for ${eMMCFilesystemChoosen} not installed, exiting"
			exit 9
		fi

		# check whether swap is currently defined and a new swap partition is needed
		if grep -q swap /etc/fstab; then
			parted -s "$1" -- mkpart primary "$partedFsType" "${FIRSTSECTOR}"s $((FIRSTSECTOR + DEFAULT_BOOTSIZE_SECTORS - 1))s
			parted -s "$1" -- mkpart primary "$partedFsType" $((FIRSTSECTOR + DEFAULT_BOOTSIZE_SECTORS))s $((FIRSTSECTOR + 393215))s
			parted -s "$1" -- mkpart primary "$partedFsType" $((FIRSTSECTOR + 393216))s "${LASTSECTOR}"s
			partprobe "$1"
			{ mkfs.ext4 "${mkopts[ext4]}" "$1"'p1'; mkswap "$1"'p2'; "mkfs.${eMMCFilesystemChoosen}" "$1"'p3' "${mkopts[$eMMCFilesystemChoosen]}"; } >> "$logfile" 2>&1
			emmcbootuuid=$(blkid -o export "$1"'p1' | grep -w UUID)
			emmcswapuuid=$(blkid -o export "$1"'p2' | grep -w UUID)
			emmcuuid=$(blkid -o export "$1"'p3' | grep -w UUID)
			dest_root=$emmccheck'p3'
		else
			parted -s "$1" -- mkpart primary "$partedFsType" "${FIRSTSECTOR}"s $((FIRSTSECTOR + DEFAULT_BOOTSIZE_SECTORS - 1))s
			parted -s "$1" -- mkpart primary "$partedFsType" $((FIRSTSECTOR + DEFAULT_BOOTSIZE_SECTORS))s "${LASTSECTOR}"s
			partprobe "$1"
			{ mkfs.ext4 "${mkopts[ext4]}" "$1"'p1'; "mkfs.${eMMCFilesystemChoosen}" "$1"'p2' "${mkopts[$eMMCFilesystemChoosen]}"; } >> "$logfile" 2>&1
			emmcbootuuid=$(blkid -o export "$1"'p1' | grep -w UUID)
			emmcuuid=$(blkid -o export "$1"'p2' | grep -w UUID)
			dest_root=$emmccheck'p2'
		fi
	else
		parted -s "$1" -- mkpart primary "$eMMCFilesystemChoosen" "${FIRSTSECTOR}"s "${LASTSECTOR}"s
		partprobe "$1"
		"mkfs.${eMMCFilesystemChoosen}" "${mkopts[$eMMCFilesystemChoosen]}" "$1"'p1' >> "$logfile" 2>&1
		emmcuuid=$(blkid -o export "$1"'p1' | grep -w UUID)
		emmcbootuuid=$emmcuuid
	fi
}

# formatting SATA/USB/NVMe partition, examples: /dev/sda3 or /dev/nvme0n1p1
format_disk()
{
	# choose and create fs
	local ROOTFSTYPE BTRFS FilesystemTargets FilesystemOptions FilesystemCmd FilesystemChoices
	IFS=" "
	ROOTFSTYPE=$(lsblk -o MOUNTPOINT,FSTYPE | awk -F" " '/^\/\ / {print $2}')
	case ${ROOTFSTYPE} in
		btrfs)
			FilesystemTargets='1 btrfs'
			;;
		*)
			BTRFS=$(grep -o btrfs /proc/filesystems)
			FilesystemTargets='1 ext4'
			if [[ -n "$BTRFS" && "$choice" != 6 ]] && ! uname -r | grep -q '^3.'; then
				FilesystemTargets="$FilesystemTargets 2 $BTRFS"
			fi
			;;
	esac
	IFS=' ' read -r -a FilesystemOptions <<< "$FilesystemTargets"

	FilesystemCmd=(dialog --title "Select filesystem type for $1" --backtitle "$backtitle" --menu "\n" 10 60 16)
	if ! FilesystemChoices=$("${FilesystemCmd[@]}" "${FilesystemOptions[@]}" 2>&1 >/dev/tty); then
		exit 10
	fi
	FilesystemChoosen=${FilesystemOptions[(2*$FilesystemChoices)-1]}

	dialog --title "$title" --backtitle "$backtitle" --infobox "\nFormating $1 to $FilesystemChoosen ... please wait." 5 60
	"mkfs.${FilesystemChoosen}" "${mkopts[$FilesystemChoosen]}" "$1" >> "$logfile" 2>&1
}

# choose target SATA/USB/NVMe partition.
check_partitions()
{
	local EXCLUDE INCLUDE CMD AvailablePartitions FREE_SPACE PartitionOptions PartitionCmd PartitionChoices
	IFS=" "
	[[ -n "$1" ]] && EXCLUDE=" | grep -v $1"
	[[ -n "$2" ]] && INCLUDE=" | grep $2" && diskcheck=$2
	CMD="lsblk -io KNAME,FSTYPE,SIZE,TYPE,MOUNTPOINT | grep -v -w $root_partition_name $INCLUDE $EXCLUDE | grep -E '^sd|^nvme|^md|^mmc' | awk -F\" \" '/ part | raid..? / {print \$1}'"
	AvailablePartitions=$(eval "$CMD")

	FREE_SPACE=$(sfdisk --list-free /dev/"$diskcheck" | grep G | tail -1 | awk '{print $4}' | sed "s/G//")

	# wiping destination to make sure we don't run into issues
	if dialog --yes-label "Proceed" --no-label 'Skip' --title "$title" --backtitle "$backtitle" --yesno "\nIt is highly recommended to wipe all partitions on the destination disk\n \n/dev/$diskcheck\n\nand leave installer to make them!" 10 75; then
		exec 3>&1
		local ACKNOWLEDGEMENT
		ACKNOWLEDGEMENT=$(dialog --colors --nocancel --backtitle "$backtitle" --no-collapse --title " Warning " \
		--clear --radiolist "\nTHIS OPERATION WILL WIPE ALL DATA ON DRIVE:\n\n/dev/$diskcheck\n " 0 56 4 "Yes, I understand" "" off       2>&1 1>&3)
		exec 3>&-
		if [[ "${ACKNOWLEDGEMENT}" == "Yes, I understand" ]]; then
			dd if=/dev/zero of=/dev/"${diskcheck}" bs=1M count=10 >> "$logfile" 2>&1
			partprobe -s "/dev/${diskcheck}" >> "$logfile" 2>&1
			# only make one ext4 partition if we don't have UEFI
			if [[ "$DEVICE_TYPE" != "uefi" ]]; then
				echo -e 'mktable gpt\nmkpart primary ext4 0% 100%\nquit' | parted "/dev/${diskcheck}" 2>&1 | tee -a "$logfile" > /dev/null
				partprobe -s "/dev/${diskcheck}" 2>&1 | tee -a "$logfile" > /dev/null
				sleep 2
			fi
		fi
	fi

	if [[ -z $AvailablePartitions ]] || [[ "${FREE_SPACE%.*}" -gt 4 ]]; then
		# Consider brand new devices or devices with a wiped partition table
		if [[ -z $(blkid /dev/"$diskcheck") ]]; then
			FREE_SPACE=$(echo "scale=0; $(blockdev --getsize64 /dev/"$diskcheck")/1024^3" | bc -l)
		else
			FREE_SPACE=$(parted /dev/"$diskcheck" unit GB print free | awk '/Free Space/{c++; sum += $3; print sum}' | tail -1)
		fi
		if [[ "${FREE_SPACE%.*}" -lt 4 ]]; then
			dialog --ok-label 'Exit' --title ' Warning ' --backtitle "$backtitle" --colors --no-collapse --msgbox "\n\Z1There is not enough free capacity on /dev/$diskcheck. Please check your device.\Zn" 7 52
			exit 11
		fi
		if ! dialog --yes-label "Proceed" --no-label 'Exit' --title "$title" --backtitle "$backtitle" --yesno "\nDestination $diskcheck has ${FREE_SPACE}GB of available space. \n\nAutomated install will generate needed partition(s)!" 9 55; then
			exit 11
		fi
		if [[ "$DEVICE_TYPE" == "uefi" ]]; then
			if [[ -z "$efi_partition" ]]; then
				wipefs -aq /dev/"$diskcheck"
				# create EFI partition
				{
					echo n; echo ; echo ; echo ; echo +200M;
					echo t; echo EF; echo w;
				} | fdisk /dev/"$diskcheck" &> /dev/null || true
				yes | mkfs.vfat /dev/"${diskcheck}"p1 &> /dev/null || true
				fatlabel /dev/"${diskcheck}"p1 EFI
			fi
			{
				echo n; echo ; echo ; echo ; echo
				echo w
			} | fdisk /dev/"$diskcheck" &> /dev/null || true
			yes | mkfs.ext4 /dev/"${diskcheck}"p2 &> /dev/null || true

			# re-read
			for mmc_dev in /dev/mmcblk[0-9]; do
				[[ -b "$mmc_dev" ]] && [[ "$mmc_dev" != "$root_partition_device" ]] && emmccheck="$mmc_dev" && break
			done
			efi_partition=$(LC_ALL=C fdisk -l "/dev/$diskcheck" 2>/dev/null | grep "EFI" | awk '{print $1}')
		else
			# Create new partition of max free size
			{
				echo n; echo ; echo ; echo ; echo
				echo w
			} | fdisk /dev/"$diskcheck" &> /dev/null || true
		fi
	fi
	CMD="lsblk -io KNAME,FSTYPE,SIZE,TYPE,MOUNTPOINT,PARTTYPENAME | grep -v -w $root_partition_name $INCLUDE $EXCLUDE | grep Linux | grep -E '^sd|^nvme|^md|^mmc' | awk -F\" \" '/ part | raid..? / {print \$1}' | uniq | sed 's|^|/dev/|' | nl | xargs echo -n"
	partprobe
	AvailablePartitions=$(eval "$CMD")
	IFS=' ' read -r -a PartitionOptions <<< "$AvailablePartitions"

	PartitionCmd=(dialog --title 'Select the destination:' --backtitle "$backtitle" --menu "\n" 10 60 16)
	if ! PartitionChoices=$("${PartitionCmd[@]}" "${PartitionOptions[@]}" 2>&1 >/dev/tty); then
		exit 11
	fi
	DISK_ROOT_PART=${PartitionOptions[(2*$PartitionChoices)-1]}
}

# build and update new bootscript
update_bootscript()
{
	if [ -f /boot/boot.cmd.new ]; then
		mv -f /boot/boot.cmd.new /boot/boot.cmd >/dev/null 2>&1
		mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr  >/dev/null 2>&1
	elif [ -f /boot/boot.ini.new ]; then
		mv -f /boot/boot.ini.new /boot/boot.ini >/dev/null 2>&1
		local rootdev rootfstype
		rootdev=$(sed -e 's/^.*root=//' -e 's/ .*$//' < /proc/cmdline)
		rootfstype=$(sed -e 's/^.*rootfstype=//' -e 's/ .*$//' < /proc/cmdline)
		sed -i "s/setenv rootfstype.*/setenv rootfstype \"$rootfstype\"/" /boot/boot.ini
		sed -i "s/setenv rootdev.*/setenv rootdev \"$rootdev\"/" /boot/boot.ini
	fi
}

# show warning [TEXT]
show_warning()
{
	if ! dialog --title "$title" --backtitle "$backtitle" --cr-wrap --colors --yesno " \Z1$(toilet -W -f ascii9 ' WARNING')\Zn\n$1" 16 67; then
		exit 13
	fi
}

# try to stop running services
stop_running_services()
{
	systemctl --state=running | awk -F" " '/.service/ {print $1}' | sort -r | \
		grep -E -e "$1" | while read -r REPLY; do
		echo -e "\nStopping ${REPLY} \c"
		systemctl stop "${REPLY}" 2>&1
	done
}

# show warning and write u-boot to MTD device(s)
#  $1 = u-boot files directory
#  $2 = space separated list of all MTD block and/or MTD char device partitions
write_uboot_to_mtd_flash()
{
	local DIR="$1"
	local MTD_ALL_DEVICE_PARTITIONS="$2"
	# For backward compatibility to existing implementations of function write_uboot_platform_mtd
	local MTD_DEFAULT_DEVICE_PATH="/dev/${MTD_ALL_DEVICE_PARTITIONS%% *}"
	MTD_DEFAULT_DEVICE_PATH="${MTD_DEFAULT_DEVICE_PATH%%:*}"
	local MESSAGE="This script will update the bootloader on one or multiple of these MTD devices:\n[ $MTD_ALL_DEVICE_PARTITIONS ]\n\nIt may take up to a few minutes - Continue?"
	if dialog --title "$title" --backtitle "$backtitle" --cr-wrap --colors --yesno " \Z1$(toilet -W -f ascii9 ' WARNING')\Zn\n$MESSAGE" 19 67; then
		write_uboot_platform_mtd "$DIR" "$MTD_DEFAULT_DEVICE_PATH" "$logfile" "$MTD_ALL_DEVICE_PARTITIONS"
		update_bootscript
		echo 'Done'
	fi
}

# Main installation logic - renamed from main() to _armbian_install_main_logic()
_armbian_install_main_logic()
{
	export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

	# This tool must run under root
	if [[ $EUID -ne 0 ]]; then
		echo 'This tool must run as root. Exiting ...' >&2
		exit 14
	fi

	[ -f "$logfile" ] && echo -e '\n\n\n' >> "$logfile"
	LANG=C echo -e "$(date): Start armbian-install.\n" >> "$logfile"

	# find real mmcblk device numbered 0, 1, 2 for eMMC, SD
	local emmc_dev sd_dev
	while IFS= read -r ret; do
		if [ -b "${ret}boot0" ]; then
			emmc_dev=$ret
		else
			sd_dev=$ret
		fi
	done < <(find /dev -name 'mmcblk[0-2]' -type b 2>/dev/null)

	local ichip dest_boot dest_root rootchip BOOTPART
	IFS="'"
	local options=()

	if [[ -n $emmccheck ]]; then
		if [[ "${emmccheck}" == "$sd_dev" ]]; then
			ichip='SD card'
		elif [[ "${emmccheck}" == "$emmc_dev" ]]; then
			ichip='eMMC'
		fi
		dest_boot=$emmccheck'p1'
		dest_root=$emmccheck'p1'
	elif [ -b /dev/nand1 ] && [ -b /dev/nand2 ]; then
		ichip='legacy SUNXI NAND'
		dest_boot='/dev/nand1'
		dest_root='/dev/nand2'
	fi

	if [[ -n $diskcheck && -d /sys/firmware/efi ]]; then
		while read -r line; do
			options+=("$line" "Install UEFI system with Grub")
		done <<< "$diskcheck"
	else
		[[ -n $sduuid && -n $diskcheck ]]		&& options+=(1 'Boot from SD - system on SATA, USB or NVMe')
		[[ -n $emmccheck ]] 				&& options+=(2 "Boot from $ichip - system on $ichip")
		[[ -n $emmccheck && -n $diskcheck ]] 		&& options+=(3 "Boot from $ichip - system on SATA, USB or NVMe")
		[[ -n $mtdcheck ]] 				&& options+=(4 'Boot from MTD Flash - system on SATA, USB or NVMe')

		if [[ -n ${root_partition_device} && ${DEVICE_TYPE} != "uefi" ]]; then
			if [ "${root_partition_device}" == "$sd_dev" ]; then
				rootchip='SD card'
			elif [ "${root_partition_device}" == "$emmc_dev" ]; then
				rootchip='eMMC'
			fi
			options+=(5 "Install/Update the bootloader on $rootchip (${root_partition_device})")
		fi

		if [ -n "${emmc_dev}" ] && [ "${emmc_dev}" != "${root_partition_device}" ]; then
			options+=(6 "Install/Update the bootloader on eMMC (${emmc_dev})")
			BOOTPART=${emmc_dev}
		elif [ -n "${sd_dev}" ] && [ "${sd_dev}" != "${root_partition_device}" ]; then
			options+=(6 "Install/Update the bootloader on SD card (${sd_dev})")
			BOOTPART=${sd_dev}
		fi

		[[ -n $mtdcheck && \
		$(type -t write_uboot_platform_mtd) == function ]] 		&& options+=(7 'Install/Update the bootloader on MTD Flash')
	fi

	[[ ${#options[@]} -eq 0 || "$root_uuid" == "$emmcuuid" || "$root_uuid" == "/dev/nand2" ]] && \
	dialog --ok-label 'Cancel' --title ' Warning ' --backtitle "$backtitle" --colors --no-collapse --msgbox '\n\Z1There are no targets. Please check your drives.\Zn' 7 52
	local cmd choices command REMOVESDTXT
	cmd=(dialog --title 'Choose an option:' --backtitle "$backtitle" --menu "\nCurrent root: $root_uuid \n              $rootchip (${root_partition_device})\n" 14 75 7)
	if ! choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty); then
		exit 16
	fi

	for choice in $choices; do
		case $choice in
			1)
				title='MMC (SD/eMMC) boot | USB/SATA/NVMe root install'
				command='Reboot'
				check_partitions
				show_warning "This script will erase your device $DISK_ROOT_PART. Continue?"
				format_disk "$DISK_ROOT_PART"
				create_armbian "" "$DISK_ROOT_PART"
				;;
			2)
				title="$ichip install"
				command='Power off'
				show_warning "This script will erase your $ichip ($emmccheck).\n     Continue?"
				if [[ -n $emmccheck ]]; then
					umount_device "$emmccheck"
					format_emmc "$emmccheck"
				elif [ -b /dev/nand ]; then
					umount_device '/dev/nand'
					format_nand
				fi
				create_armbian "$dest_boot" "$dest_root"
				;;
			3)
				title="$ichip boot | USB/SATA/NVMe root install"
				command='Power off'
				check_partitions
				show_warning "This script will erase your ${ichip} ($emmccheck)\n    and $DISK_ROOT_PART. Continue?"
				if [[ -n $emmccheck ]]; then
					umount_device "$emmccheck"
					format_emmc "$emmccheck"
				elif [ -b /dev/nand ]; then
					umount_device '/dev/nand'
					format_nand
				fi
				umount_device "${DISK_ROOT_PART//[0-9]*/}"
				format_disk "$DISK_ROOT_PART"
				create_armbian "$dest_boot" "$DISK_ROOT_PART"
				;;
			4)
				# Espressobin has flash boot by default
				title='MTD Flash boot | USB/SATA/NVMe root install'
				command='Power off'
				# we need to copy boot
				sed -i '/boot/d' "$EX_LIST"
				check_partitions
				show_warning "This script will erase your device $DISK_ROOT_PART. Continue?"
				format_disk "$DISK_ROOT_PART"
				create_armbian 'mtd' "$DISK_ROOT_PART"

				if [[ $(type -t write_uboot_platform_mtd) == function ]]; then
					if dialog --title "$title" --backtitle "$backtitle" --yesno \
						"Do you want to write the bootloader to MTD Flash?\n\nIt is required if you have not done it before or if you have some non-Armbian bootloader in this flash." 8 60; then
						write_uboot_to_mtd_flash "$DIR" "$mtdcheck"
					fi
				fi
				;;
			5)
				show_warning "This script will update the bootloader on ${root_partition_device}.\n\n    Continue?"
				write_uboot_platform "$DIR" "${root_partition_device}"
				update_bootscript
				dialog --backtitle "$backtitle" --title 'Writing bootloader' --msgbox '\n          Done.' 7 30
				return
				;;
			6)
				show_warning "This script will update the bootloader on ${BOOTPART}.\n\n    Continue?"
				write_uboot_platform "$DIR" "${BOOTPART}"
				echo 'Done'
				return
				;;
			7)
				write_uboot_to_mtd_flash "$DIR" "$mtdcheck"
				return
				;;
			*)
				title='UEFI install to internal drive'
				command='Reboot'
				check_partitions "$root_partition_device_name" "$choice"
				# we need to copy boot
				sed -i '/boot/d' "$EX_LIST"
				show_warning "This script will erase your device $DISK_ROOT_PART. Continue?"
				format_disk "$DISK_ROOT_PART"
				create_armbian "" "$DISK_ROOT_PART" "$choice"
				;;
		esac
	done

	if dialog --title "$title" --backtitle "$backtitle" --yes-label "$command" --no-label 'Exit' --yesno "\nAll done. $command $REMOVESDTXT" 7 70; then
		local cmd_lower
		cmd_lower="${command,,}"
		cmd_lower="${cmd_lower// /}"
		"$cmd_lower"
	fi
}

# Wrapper function to call armbian-install main logic
_armbian_install_main() {
	# Initialize armbian-install variables
	local ORIGINAL_SCRIPT_NAME="armbian-install"
	local script_dir
	script_dir="$(dirname "${BASH_SOURCE[0]}")"
	local CWD="/usr/lib/${ORIGINAL_SCRIPT_NAME}"
	local EX_LIST="${CWD}/exclude.txt"
	[ ! -f "${EX_LIST}" ] && EX_LIST="${script_dir}/armbian-install/exclude.txt"
	[ -f /etc/default/openmediavault ] && echo '/srv/*' >> "${EX_LIST}"
	local logfile="/var/log/${ORIGINAL_SCRIPT_NAME}.log"

	# read in board info
	# shellcheck source=/dev/null
	[[ -f /etc/armbian-release ]] && source /etc/armbian-release
	local backtitle="Armbian for $BOARD_NAME install script, https://www.armbian.com"
	local title="Armbian installer v${VERSION}"

	# exceptions
	local DEVICE_TYPE BOOTLOADER FIRSTSECTOR
	if grep -q 'sun4i' /proc/cpuinfo; then DEVICE_TYPE="a10"
	elif grep -q 'sun5i' /proc/cpuinfo; then DEVICE_TYPE="a13"
	else DEVICE_TYPE="a20"; fi
	BOOTLOADER="${CWD}/${DEVICE_TYPE}/bootloader"
	[ ! -d "${BOOTLOADER}" ] && BOOTLOADER="${script_dir}/armbian-install/${DEVICE_TYPE}/bootloader"
	FIRSTSECTOR=32768

	# recognize_root
	local root_uuid root_partition root_partition_name root_partition_device_name root_partition_device
	root_uuid=$(sed -e 's/^.*root=//' -e 's/ .*$//' < /proc/cmdline)
	root_partition=$(blkid | tr -d '":' | grep "${root_uuid}" | awk '{print $1}')
	root_partition_name=$(echo "$root_partition" | sed 's/\/dev\///g')
	root_partition_device_name=$(lsblk -ndo pkname "$root_partition")
	root_partition_device=/dev/$root_partition_device_name

	# find targets: legacy SUNXI NAND, EMMC, SATA, NVMe, MTD block and/or MTD char driven flash
	local nandcheck emmccheck diskcheck mtdcheck sduuid efi_partition
	if [[ -b /dev/nand ]]; then
		for nand_dev in /dev/nand*; do
			if [[ -b "$nand_dev" ]] && [[ "$nand_dev" == *nand ]]; then
				nandcheck="$nand_dev"
				break
			fi
		done
	fi
	for mmc_dev in /dev/mmcblk[0-9]; do
		[[ -b "$mmc_dev" ]] && [[ "$mmc_dev" != "$root_partition_device" ]] && emmccheck="$mmc_dev" && break
	done
	diskcheck=$(lsblk -Al | awk -F" " '/ disk / {print $1}' | grep -E '^sd|^nvme|^mmc' | grep -v "$root_partition_device_name" | grep -v boot)
	mtdcheck=$(grep 'mtdblock' /proc/partitions | awk '{print $NF}' | xargs)
	[[ -f /proc/mtd ]] && mtdcheck="$mtdcheck${mtdcheck:+ }$(grep -i -E '^mtd[0-9]+:.*(spl|boot).*' /proc/mtd | awk '{print $1$NF}' | sed 's/\"//g' | xargs)"

	# SD card boot part
	local sdblkid
	[[ -z $emmccheck ]] && sdblkid=$(blkid -o full /dev/mmcblk*p1 | grep -v "$root_partition_device")
	[[ -n $emmccheck ]] && sdblkid=$(blkid -o full /dev/mmcblk*p1 | grep -v "$root_partition_device" | grep -v "$emmccheck")
	[[ -z $sdblkid && -z $emmccheck ]] && sdblkid=$(blkid -o full /dev/mmcblk*p1)
	[[ -z $sdblkid && -n $emmccheck ]] && sdblkid=$(blkid -o full /dev/mmcblk*p1 | grep -v "$emmccheck")
	sduuid=$(echo "$sdblkid" | sed -nE 's/^.*[[:space:]](UUID="[0-9a-zA-Z-]*").*/\1/p' | tr -d '"')

	# recognize EFI
	[[ -d /sys/firmware/efi ]] && DEVICE_TYPE="uefi"
	efi_partition=$(LC_ALL=C fdisk -l "/dev/$diskcheck" 2>/dev/null | grep "EFI" | awk '{print $1}')

	# define makefs and mount options
	declare -A mkopts mountopts
	if [[ $LINUXFAMILY == mvebu ]]; then
		mkopts[ext4]='-O ^64bit -qF'
	else
		mkopts[ext4]='-qF'
	fi
	mkopts[btrfs]='-f'
	mkopts[f2fs]='-f'
	mountopts[ext4]='defaults,noatime,commit=120,errors=remount-ro,x-gvfs-hide	0	1'
	mountopts[btrfs]='defaults,noatime,commit=120,compress=lzo,x-gvfs-hide			0	2'
	mountopts[f2fs]='defaults,noatime,x-gvfs-hide	0	2'

	# DIR: path to u-boot directory (usually empty or set by platform_install.sh)
	local DIR="${DIR:-}"

	# Export variables for use in functions
	export CWD EX_LIST logfile BOOTLOADER DEVICE_TYPE FIRSTSECTOR DIR
	export root_uuid root_partition root_partition_name root_partition_device_name root_partition_device
	export emmccheck diskcheck mtdcheck sduuid efi_partition nandcheck
	export mkopts mountopts backtitle title

	# Call main logic function
	_armbian_install_main_logic "$@"
}

# uncomment to test the module
# module_partitioner "$1"
