# archlinux-raspberry-install
Menu driven ( whiptail ) basic archlinux installation for raspberry pi. 
Works on Raspberry PI Zero,1,2,3,4.

There are still steps required after first bootup.
See https://archlinuxarm.org/platforms/armv6/raspberry-pi

> Use the serial console or SSH to the IP address given to the board by your router.
Login as the default user alarm with the password alarm.
The default root password is root.
 
> Initialize the pacman keyring and populate the Arch Linux ARM package signing keys:
pacman-key --init
pacman-key --populate archlinuxarm
