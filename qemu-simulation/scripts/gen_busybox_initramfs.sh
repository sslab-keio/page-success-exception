#!/usr/bin/env bash

mkdir -p $INITRAMFS_DIR
mkdir -p $INITRAMFS_DIR/{bin,sbin,dev,etc,home,mnt,proc,sys,usr,tmp}
mkdir -p $INITRAMFS_DIR/usr/{bin,sbin}
mkdir -p $INITRAMFS_DIR/proc/sys/kernel

pushd $INITRAMFS_DIR/dev 2> /dev/null
  sudo mknod sda b 8 0
  sudo mknod console c 5 1
popd 2> /dev/null

cp build/busybox/busybox $INITRAMFS_DIR/bin/

cat << EOF > $INITRAMFS_DIR/init
#!/bin/busybox sh
/bin/busybox --install -s
mount -t devtmpfs  devtmpfs  /dev
mount -t proc      proc      /proc
mount -t sysfs     sysfs     /sys
mount -t tmpfs     tmpfs     /tmp
setsid cttyhack sh
echo /sbin/mdev > /proc/sys/kernel/hotplug
mdev -s
sh
EOF

chmod +x $INITRAMFS_DIR/init
cd $INITRAMFS_DIR && find . -print0 | cpio --null --create --verbose --format=newc | gzip -9 > initramfs.cpio.gz
