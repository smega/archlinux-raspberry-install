#!/bin/bash
#smega 2019

# global variables for final settings
gzip=""
wpaconfigfile=""

# variables for install
declare -A globals
globals=( ['sdcard']="" \
           ['image']="" \
        ['hostname']="" )

declare -A globals_wifi
globals_wifi=( ['countrycode']="" \
                      ['ssid']="" \
                  ['ssid_password']="" )

#variables used during installation
IMAGEDIR=./images
CONFIGDIR=./confs
WIFI_CARD=wlan0
WPA_CONFIG=$CONFIGDIR/wpa_supplicant.conf
WPA_CONFIG_TEMPLATE=$CONFIGDIR/wpa_supplicant.conf_template
DEFAULTHOSTNAME='Archlinux-raspberry'
WIFI_ENABLED=0
#WPA_CONFIG_FINAL=$CONFIGDIR/wpa_supplicant.conf-${WIFI_CARD}.conf

#temporarily created to mount sdcard
ROOTTEMP=/mnt/roottemp
BOOTTEMP=/mnt/boottemp

#Archlinux mirror settings
ARCHSITE=http://de4.mirror.archlinuxarm.org/os/
ARCH_FILE_REGEX=ArchLinuxARM-rpi-.*latest.tar.gz
GZIPS=(`curl --silent ${ARCHSITE} | grep -i "${ARCH_FILE_REGEX}" | awk -F"[ \"]*" '{ if ( $3 ~ /gz$/) print $3, $7 }'`)


#----------------------------------------------------------------
#pre-installation tasks
#check imagedir
if [ ! -d "$IMAGEDIR" ]; then mkdir -p $IMAGEDIR; fi

#check configdir
#if [ ! -d "$CONFIGDIR" ]; then mkdir -p $CONFIGDIR; fi

#set hostname to default
globals['hostname']=$DEFAULTHOSTNAME

#---------------------------------------------------------------
#functions
# get all removable devices
function getDevices()
{
  devices=(`lsblk -lnp | awk '/disk/ {if ($3 == "1" ) print $1}'`)
  local num=1
  menudevices=()
  if [[ "${devices[@]}" ]]; then
    for device in "${devices[@]}"; do
      menudevices+=("$num")
      menudevices+=("$device")
      ((num+=1))
    done
  else
    whiptail --title "No removable device!" --msgbox "Please insert an SDcard..." 20 78
  fi
}

#--------------------------------------------------------------
#check if selected device is mounted
function checkMount()
{
  device=$1
  number=$2
  m=$(lsblk -lnp -o NAME,SIZE,MOUNTPOINT $device | awk '{if ($3 != "") print  }')
  if [ "$m" ]; then
    whiptail --title "Checking Sdcard" --msgbox "$device:\n$(echo $m | awk '{ print $1 }') is mounted on $(echo $m | awk '{ print $3 }')\n\nPlease choose another one..." 20 78
#    globals['sdcard']=""
  else
    whiptail --title "Checking Sdcard" --msgbox "$device is not mounted.\n\nIt will be used..." 20 78
    globals['sdcard']=${devices[number-1]}
  fi
}

#-----------------------------------------------------------------
#select image
function getImages()
{
#  images=(`ls -lh $IMAGEDIR/ | awk '/.gz$/ {print $9}'`)
  images=(`ls -1 $IMAGEDIR/ | grep -iE ".gz$"`)
  menuimages=()
  local num=1
  if [ "$images" ]; then
    for image in ${images[@]}; do
      menuimages+=("$num")
      menuimages+=("$image")
      let "num=num+1"
    done
  else
    whiptail --title "No image found in 'images' directory." --msgbox "Please copy the gz file there or download one in step 3." 10 78
  fi
}

#-----------------------------------------------------------------
#create array for menu of response from Archlinux download site
function getmenuGzips() {
  local menugzips=()
  local num=1
  for ((n=0; n<"${#GZIPS[@]}"; n+=2)); do
    menugzips+=("$num")
    menugzips+=("${GZIPS[n]}")
    let "num=num+1"
  done
  echo ${menugzips[*]}
}

#----------------------------------------------------------------
#create array of gzips only where the file that will be installed is selected from
function getonlyGzips()
{
  local onlygzips=()
  for ((n=0; n<"${#GZIPS[@]}"; n+=2)); do
    onlygzips+=("${GZIPS[n]}")
  done
  echo ${onlygzips[*]}
}

#-----------------------------------------------------------------
#create array of gzip sizes for the whiptail gauge
function getonlySizes() {
  local onlysizes=()
  for ((n=1; n<"${#GZIPS[@]}"; n+=2)); do
    #remove trailing \r
    size=$(echo ${GZIPS[n]} | sed 's/[^0-9]*//g')
    onlysizes+=("${size}")
  done
  echo ${onlysizes[*]}
}

#-----------------------------------------------------------------
#download image
function downloadImage() {
  local gzip=$1
  local gzipsize=$2
  curl --silent -o $IMAGEDIR/${gzip} ${ARCHSITE}${gzip} &
  {
  while [[ "$downsize" != "$gzipsize"  ]]; do
    if [ -f $IMAGEDIR/${gzip} ]; then
      downsize=$(ls -l $IMAGEDIR/${gzip} | awk '{ print $5 }')
    else
      downsize=1
    fi
    multi=$(( downsize * 100  ))
    percent=$(( multi / gzipsize  ))
    echo $percent
    sleep 1
  done
  } | whiptail --gauge "Downloading $gzip" 6 60 0 
}

#--------------------------------------------------
#set wpa_supplicant.conf file or collect info for wireless config
function setWireless() {
  WPA_ENABLED=1
  whiptail --title "creating wpa_supplicant.conf" --msgbox "
   You will need:
   a) Country code (the ISO code of your country)
   b) SSID of your router
   c) Your router's password.
" 20 98

  globals_wifi['countrycode']=$(whiptail --inputbox --title "Creating wpa_supplicant.conf" "Enter countrycode: ( the ISO code of your country )" 10 50 3>&1 1>&2 2>&3)
  globals_wifi['ssid']=$(whiptail --inputbox --title "Creating wpa_supplicant.conf" "Enter SSID:" 10 50 3>&1 1>&2 2>&3)
  globals_wifi['ssid_password']=$(whiptail --inputbox --title "Creating wpa_supplicant.conf" "Enter password:" 10 50 3>&1 1>&2 2>&3)
}

#--------------------------------------------------------------------------------
#partition and format SDcard
function partition_and_format_SDcard() {
  local DEV=$1
fdisk -u $DEV << EOF
o
n
p
1

+100M
t
c
n
p
2


w
EOF

  mkfs.vfat ${DEV}1
  mkfs.ext4 -F ${DEV}2
}

#--------------------------------------------------------------------------------
#create temporary directories and mount partitions
function create_mount() {
  local DEV=$1
  for i in ${ROOTTEMP} ${BOOTTEMP}; do
    if [ ! -d "$i" ]; then
      mkdir -vp $i
    fi
  done

  mount -v ${DEV}2 ${ROOTTEMP}
  mount -v ${DEV}1 ${BOOTTEMP}
echo mounted
}

#--------------------------------------------------------------------------------
#remove temporary directories and mount partitions
function remove_mount() {
  for i in ${ROOTTEMP} ${BOOTTEMP}; do
    if [ -d "$i" ]; then
echo umounted
      umount -v $i
      rm -fr $i
    fi
  done
}

#--------------------------------------------------------------------------------
#create wpa_supplicant.conf file
function create_wpa_supplicant_conf() {
  local countrycode=$1
  local ssid=$2
  local password=$3

cat << END >> ${WPA_CONFIG}
country=${countrycode}
ctrl_interface=DIR=/var/run/wpa_supplicant
update_config=1

network={
  ssid="${ssid}"
  psk="${password}"
  priority=5
}
END
}

#--------------------------------------------------------------------------------
#returns array with empty config settings
function check_array {

  local -n assoc=$1
  local string=""

  for i in "${!assoc[@]}"; do
    if [ ! "${assoc[$i]}" ]; then
      string="$string ${i}"
    fi
  done
  echo ${string}
}

#---------------------------------------------------------------------------------
#create string from data in array
function string_from_array {

  local -n assoc=$1
  local string=""

  for i in "${!assoc[@]}"; do
    if [ "${assoc[$i]}" ]; then
      string=("${string}${i}: ${assoc[$i]} \n")
    fi
  done
  echo ${string}
}

#---------------------------------------------------------------------------------
#---------------------------------------------------------------------------------
#---------------------------------------------------------------------------------
#program starts
clear

#initial information screen
if ! (whiptail --title "Information and required pre-installation steps" --yesno "
1. If you have the Archlinux gzipped root filesystem please copy it to the 'images' directory. 
   Or you can select and download the file during installation.
2. If you need wireless connection during the first startup (for Zero it is mandatory!) please copy the wpa_supplicant.conf file to the $CONFIGDIR directory.
   Or you can build one during the installation.

Select Yes if you are ready to proceed to installation.
Select No if you want to quit to do any pre-installation step.
" 20 98); then
    echo "Bye bye!!"
    exit
fi

#installation start
while [ 1 ]; do
  CHOICE=$(
  whiptail --title "Install Archlinux for Raspberry PI" --menu "Choose" 16 100 9 \
        "1)" "Choose sdcard."   \
        "2)" "Choose Archlinux gzip file."  \
        "3)" "Download Archlinux gzip file."  \
        "4)" "Set hostname."  \
        "5)" "Set wireless config."  \
        "9)" "Check settings before creating sdcard." \
        "7)" "Start creating SDcard...."  \
        "8)" "Exit script...." 3>&2 2>&1 1>&3
)

  case $CHOICE in

        "1)")
             #select device
             getDevices
             devicenumber=$(whiptail --title "Removable devices" --menu "Select SDCard" 20 80 10 ${menudevices[@]}  3>&2 2>&1 1>&3-)
             #check if device is mounted
             if [ "$devicenumber" ]; then
               checkMount ${devices[devicenumber-1]} $devicenumber
             fi
        ;;

        "2)")
             #select gzipped archlinux root filesystem
             getImages
             if [ $menuimages ]; then
               imagenumber=$(whiptail --title "Gzip file - Size" --menu "Select image" 20 80 10 ${menuimages[@]}  3>&2 2>&1 1>&3-)
               globals['image']=${images[imagenumber-1]}
             fi
        ;;

        "3)")
             #download archlinux root filesystem
             menugzips=(`getmenuGzips`)
             onlygzips=(`getonlyGzips`)
             onlysizes=(`getonlySizes`)

             gzipnumber=$(whiptail --title "Archlinux files available on server" --menu "Select file to download." 20 80 10 ${menugzips[@]}  3>&2 2>&1 1>&3-)
             gzip=${onlygzips[gzipnumber-1]}
             gzipsize=${onlysizes[gzipnumber-1]}


             if [ -f $IMAGEDIR/${gzip} ]; then
               if (whiptail --title "File exists" --yesno "$gzip exists in ./image directory.\n\nDo you still want to download it?" 20 98); then
                 rm -f $IMAGEDIR/${gzip}
                 downloadImage ${gzip} ${gzipsize}
               fi
             else
               downloadImage ${gzip} ${gzipsize}
             fi
        ;;

        "4)")
             #set hostname
             globals['hostname']=$(whiptail --inputbox --title "Enter hostname" "\nDefault hostname: $DEFAULTHOSTNAME" 10 50 3>&1 1>&2 2>&3)
             if [ "${globals[hostname]}" == "" ]; then
               globals['hostname']=$DEFAULTHOSTNAME
             fi
        ;;

        "5)")
               setWireless
        ;;

        "9)")
             #check if all needed config settings are there
             #missing data
             globalmissing=$(check_array globals)
             wifimissing=$(check_array globals_wifi)

             #found data
             globalstring=$(string_from_array globals)
             wifistring=$(string_from_array globals_wifi)

             #clear variable
             missingdata=""
             if [ ! "$WPA_ENABLED" ]; then
               missingdata="${missingdata}${globalmissing}"
               wpastring="WIFI is not needed - no wifi data"
               globalstring="$globalstring\n${wpastring}"
             else
               missingdata="${missingdata}${globalmissing}${wifimissing}"
               wpastring="WIFI is needed"
               globalstring="${globalstring}\n${wpastring}\n${wifistring}"
             fi

             if [ "$missingdata"  ]; then
               whiptail --title "Checking needed information" --msgbox "Data that has been set: \n$globalstring \nMissing data:\n${missingdata}" 20 78
             else
               whiptail --title "Checking needed information" --msgbox "All data is there \n $globalstring" 20 78
             fi
        ;;

        "7)")
             card_contains=$(lsblk ${globals[sdcard]})
             if (whiptail --title "Check all data" --yesno "SDcard:\n$card_contains\nImage: ${globals[image]}\nHostname: ${globals[hostname]}\nWireless settings:\nCountrycode: ${globals_wifi[countrycode]}\nSSID: ${globals_wifi[ssid]}\nPassword: ${globals_wifi[ssid_password]}\n" 20 98); then

               #partition and format sdcard
               partition_and_format_SDcard ${globals[sdcard]}

               #create temporary directories and mount partitions
               create_mount ${globals[sdcard]}

               #untar files to sdcard
               echo "untar system files to sdcard"
               bsdtar -xpf $IMAGEDIR/${globals[image]} -C ${ROOTTEMP}
               sleep 20
               sync

               #move boot to boot partition
               echo "move /boot/* to the boot partition"
               mv  ${ROOTTEMP}/boot/* ${BOOTTEMP}

               #copy files
               if [ "$WIFI_ENABLED" ]; then
                 #build wpa_supplicant.conf
                 create_wpa_supplicant_conf ${globals_wifi['countrycode']} ${globals_wifi['ssid']} ${globals_wifi['ssid_password']}
                 echo "copying files for wifi"
                 cp -v ${WPA_CONFIG} ${ROOTTEMP}/etc/wpa_supplicant/wpa_supplicant-wlan0.conf
                 cp -v ${CONFIGDIR}/wlan0.network ${ROOTTEMP}/etc/systemd/network/wlan0.network
                 ln -s ${ROOTTEMP}/lib/systemd/system/wpa_supplicant\@.service ${ROOTTEMP}/etc/systemd/system/multi-user.target.wants/wpa_supplicant\@wlan0.service

                 #remove /etc/resolv.conf link and create custom one
                 unlink ${ROOTTEMP}/etc/resolv.conf
                 #echo "nameserver 192.168.1.1" > ${ROOTTEMP}/etc/resolv.conf
                 echo "nameserver 8.8.8.8" >> ${ROOTTEMP}/etc/resolv.conf
               fi

               echo "enable root ssh"
               sed -in s/^.*PermitRootLogin.*/PermitRootLogin\ yes/g ${ROOTTEMP}/etc/ssh/sshd_config

               echo "add hostname to /etc/hosts"
               sed -in s/127.0.0.1/127.0.0.1\ localhost\ ${globals[hostname]}/ ${ROOTTEMP}/etc/hosts

               echo "set hostname"
               echo ${globals[hostname]} > ${ROOTTEMP}/etc/hostname

               # cleaning up - unmount partitions and delete temporary directories
               remove_mount
               rm -fr ${WPA_CONFIG}

               if [ "$?" == 0 ]; then
                 whiptail --title "Finish" --msgbox "The SDcard has been successfully created." 20 78
               else
                 whiptail --title "Finish" --msgbox "There were problems." 20 78
               fi
               exit
             fi
        ;;

        "8)")
            exit
        ;;
  esac
done
