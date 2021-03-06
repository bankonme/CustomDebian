#!/bin/bash
# author : Oros
# 2015-02-03
# Many thanks to netblue30 http://l3net.wordpress.com/2013/09/21/how-to-build-a-debian-livecd/

function help()
{
	echo "Build a custom live Debian."
	echo "$0 [new|rebuild]"
	echo -e " new     : remove ./livework if exist and build a new live"
	echo -e " rebuild : keep ./livework, clean chroot and build a new live"
	echo -e "\n$0 should be run as root"
	exit 0
}

function clean_chroot()
{
	if [ -d ../custom_conf ]; then
		cp -r ../custom_conf/* chroot/
	fi
	rm -fr chroot/root/.bash_history
	rm -fr chroot/var/log/*
	rm -fr chroot/var/cache/apt/archives/*
	rm -fr chroot/tmp/*
}

if [ ! -f config ]; then
	if [ -f default/config ]; then
		cp default/config config
	else
		echo "$0: ${1:-"config file not found"}" 1>&2
		exit 1
	fi
fi
. ./config

if [[ ! -d custom_conf && -d default/custom_conf ]]; then
	cp -r default/custom_conf custom_conf
fi

if [[ ! -d custom_setup && -d default/custom_setup ]]; then
	cp -r default/custom_setup custom_setup
fi

if [[ ! -d other_files && -d default/other_files ]]; then
	cp -r default/other_files other_files
fi

if [ ! "$#" -eq 1 ]; then
	help
fi

if [ "$EUID" -ne 0 ]; then 
	echo -e "\033[31mPlease run as root\033[0m" 1>&2
	exit 1
fi

now=`date +%s`

if [ "$1" == "new" ]; then
	if [ ! `which xorriso` ]; then
		apt-get install -y xorriso
	fi
	if [ ! `which live-build` ]; then
		apt-get install -y live-build
	fi
	if [ ! `which syslinux` ]; then
		apt-get install -y syslinux
	fi
	if [ ! `which mksquashfs` ]; then
		apt-get install -y squashfs-tools
	fi
	rm -fr ./livework
	mkdir -p ./livework
	cd ./livework
	debootstrap --arch=${archi} ${debian_version} chroot
	
	if [[ ! -d "chroot" || `ls "chroot"` == "" ]]; then
		echo -e "\033[31mchroot is empty 0_0!?\033[0m" 1>&2
		echo "This can happen when you run this script in a encrypted /home/ :-("
		echo "Try to move CustomDebian in an other folder like /tmp/ and try again."
		exit 1
	fi

	if [[ -f ../other_files/setup_in_chroot_head.sh && -f ../other_files/setup_in_chroot_footer.sh ]]; then
		cat ../other_files/setup_in_chroot_head.sh > chroot/setup_in_chroot.sh
		echo -e "apt-get install -y linux-image-${archi}\napt-get install -y live-boot" >> chroot/setup_in_chroot.sh
		echo -e "cp /usr/sbin/update-initramfs.orig.initramfs-tools /usr/sbin/update-initramfs\nupdate-initramfs -u" >> chroot/setup_in_chroot.sh
		if [ -d ../custom_setup ]; then
			for f in ../custom_setup/*.sh; do
				cat $f >> chroot/setup_in_chroot.sh
			done
		fi
		cat ../other_files/setup_in_chroot_footer.sh >> chroot/setup_in_chroot.sh
		chmod +x chroot/setup_in_chroot.sh
		echo -e "\033[31mEnter in chroot\033[0m"
		chroot chroot /setup_in_chroot.sh
		echo -e "\033[31mExit chroot\033[0m"
		rm -fr chroot/setup_in_chroot.sh
		echo "${dist_name}" > chroot/etc/hostname
		clean_chroot
	fi
elif [ "$1" == "rebuild" ]; then
	if [[ -d "livework" && -d "./livework/chroot" ]]; then
		cd ./livework
		clean_chroot
	else
		echo -e "\033[31m./livework/chroot doesn't exist!\033[0m" 1>&2
		exit 1
	fi
else
	help
fi

mkdir -p binary/{live,isolinux}
#cp chroot/boot/vmlinuz-3.2.0-4-${archi} binary/live/vmlinuz
cp $(ls chroot/boot/vmlinuz* |sort --version-sort -f|tail -n1) binary/live/vmlinuz
#cp chroot/boot/initrd.img-3.2.0-4-${archi} binary/live/initrd
cp $(ls chroot/boot/initrd* |sort --version-sort -f|tail -n1) binary/live/initrd
#mksquashfs chroot binary/live/filesystem.squashfs -comp xz -e boot
mksquashfs chroot binary/live/filesystem.squashfs -comp xz

isohdpfx_path=/usr/lib/syslinux/isohdpfx.bin
if [ -f /usr/lib/syslinux/isolinux.bin ]; then
	cp /usr/lib/syslinux/isolinux.bin binary/isolinux/
elif [ -f /usr/lib/ISOLINUX/isolinux.bin ]; then
	cp /usr/lib/ISOLINUX/isolinux.bin binary/isolinux/
	isohdpfx_path=/usr/lib/ISOLINUX/isohdpfx.bin
else
	if [ ! `which isolinux` ]; then
		apt-get install -y isolinux
		if [ -f /usr/lib/ISOLINUX/isolinux.bin ]; then
			cp /usr/lib/ISOLINUX/isolinux.bin binary/isolinux/
			isohdpfx_path=/usr/lib/ISOLINUX/isohdpfx.bin
		else
			echo -e "\033[31m/usr/lib/syslinux/isolinux.bin or /usr/lib/ISOLINUX/isolinux.bin not found!\033[0m" 1>&2
			exit 1		
		fi
	else
		echo -e "\033[31m/usr/lib/syslinux/isolinux.bin or /usr/lib/ISOLINUX/isolinux.bin not found!\033[0m" 1>&2
		exit 1	
	fi
fi

if [ ! -f $isohdpfx_path ]; then
	echo -e "\033[31m${isohdpfx_path} not found!\033[0m" 1>&2
	exit 1
fi

if [ -f /usr/lib/syslinux/vesamenu.c32 ]; then
	cp /usr/lib/syslinux/vesamenu.c32 binary/isolinux/
elif [ -f /usr/lib/syslinux/modules/bios/vesamenu.c32 ]; then
	cp /usr/lib/syslinux/modules/bios/vesamenu.c32 binary/isolinux/
else
	echo -e "\033[31m/usr/lib/syslinux/vesamenu.c32 or /usr/lib/syslinux/modules/bios/vesamenu.c32 not found!\033[0m" 1>&2
	exit 1
fi

cp ../other_files/splash.png binary/isolinux/

echo "default vesamenu.c32
prompt 0
MENU background splash.png
MENU title Boot Menu
MENU COLOR screen       37;40   #80ffffff #00000000 std
MENU COLOR border       30;44   #40ffffff #a0000000 std
MENU COLOR title        1;36;44 #ffffffff #a0000000 std
MENU COLOR sel          7;37;40 #e0ffffff #20ffffff all
MENU COLOR unsel        37;44   #50ffffff #a0000000 std
MENU COLOR help         37;40   #c0ffffff #a0000000 std
MENU COLOR timeout_msg  37;40   #80ffffff #00000000 std
MENU COLOR timeout      1;37;40 #c0ffffff #00000000 std
MENU COLOR msg07        37;40   #90ffffff #a0000000 std
MENU COLOR tabmsg       31;40   #ffDEDEDE #00000000 std
MENU HIDDEN
MENU HIDDENROW 8
MENU WIDTH 78
MENU MARGIN 15
MENU ROWS 5
MENU VSHIFT 7
MENU TABMSGROW 11
MENU CMDLINEROW 11
MENU HELPMSGROW 16
MENU HELPMSGENDROW 29

timeout 50

label live-${archi}-ram
	menu label ^${dist_name} RAM (${archi})" > binary/isolinux/isolinux.cfg
if [ "${boot_default}" == "ram" ]; then
	echo "	menu default" >> binary/isolinux/isolinux.cfg
fi
echo "	linux /live/vmlinuz apm=power-off boot=live live-media-path=/live/ toram=filesystem.squashfs
	append initrd=/live/initrd boot=live quiet

label live-${archi}
	menu label ^${dist_name} (${archi})" >> binary/isolinux/isolinux.cfg
if [ "${boot_default}" == "" ]; then
	echo "	menu default" >> binary/isolinux/isolinux.cfg
fi
echo "	linux /live/vmlinuz
	append initrd=/live/initrd boot=live quiet

label live-${archi}-failsafe
	menu label ^${dist_name} (${archi} failsafe)" >> binary/isolinux/isolinux.cfg
if [ "${boot_default}" == "failsafe" ]; then
	echo "	menu default" >> binary/isolinux/isolinux.cfg
fi
echo "	linux /live/vmlinuz
	append initrd=/live/initrd boot=live config memtest noapic noapm nodma nomce nolapic nomodeset nosmp nosplash vga=normal

endtext
" >> binary/isolinux/isolinux.cfg

xorriso -as mkisofs -r -J -joliet-long -l -cache-inodes -isohybrid-mbr $isohdpfx_path -partition_offset 16 -A "${dist_name}"  -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o ${iso_name} binary

echo "End"
date
last=`date +%s`
count=$(($last - $now))
min=$((count/60))
sec=$((count%60))
echo "Time : ${min}m ${sec}s"
if [ -f ${iso_name} ] ; then
	echo "ISO build in ./livework/${iso_name}"
else
	echo -e "\033[31mError, ./livework/${iso_name} not build :-(\033[0m" 1>&2
	exit 1
fi
