[working-directory: 'xv6-riscv']
xv6:
  make -j16 fs.img kernel/kernel

[working-directory: 'qemu']
qemu-setup:
  mkdir -p build
  cd build; CC=clang ../configure --target-list="riscv64-softmmu" --disable-fuse --disable-user --disable-curl --enable-debug

[working-directory: 'qemu']
qemu:
  make -C build -j16

[working-directory: 'opensbi']
opensbi:
  #CROSS_COMPILE='riscv64-linux-gnu-' PLATFORM='generic' FW_TEXT_START='0x80000000' make -j16
  LLVM=1 PLATFORM='generic' FW_TEXT_START='0x80000000' compiledb make -j16

[working-directory: 'busybox']
busybox-setup $CROSS_COMPILE='riscv64-linux-gnu-' $ARCH='riscv':
  make defconfig
  sed 's/CONFIG_TC=y/CONFIG_TC=n/' -i .config
  sed 's/CONFIG_FEATURE_TC_INGRESS=y/CONFIG_FEATURE_TC_INGRESS=n/' -i .config
  sed 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' -i .config

[working-directory: 'busybox']
busybox $CROSS_COMPILE='riscv64-linux-gnu-' $ARCH='riscv':
  #compiledb make -j16 install
  make -j16 install

[working-directory: 'xvisor']
xvisor-setup $CROSS_COMPILE='riscv64-linux-gnu-' $ARCH='riscv':
  make O=./build generic-64b-defconfig

[working-directory: 'xvisor']
xvisor $CROSS_COMPILE='riscv64-linux-gnu-' $ARCH='riscv':
  #compiledb make -j16
  #compiledb make -j16 -C tests/riscv/virt64/basic
  make -j16 VERBOSE=y
  make -j16 VERBOSE=y -C tests/riscv/virt64/basic

INIT := "\
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
"
[working-directory: 'busybox']
fs: busybox
  #!/usr/bin/bash
  rm -rf initramfs
  rm -f initramfs.cpio.gz
  rm -f xvisor-initrd.cpio
  mkdir initramfs
  cd initramfs
  mkdir -p {bin,sbin,dev,etc,home,mnt,proc,sys,usr,tmp}
  mkdir -p usr/{bin,sbin}
  mkdir -p proc/sys/kernel
  cd dev
    sudo mknod sda b 8 0
    sudo mknod console c 5 1
  cd ..
  cp ../busybox bin/
  cat << EOF > init
  {{INIT}}
  EOF
  chmod +x init

[working-directory: 'busybox']
fs-linux: fs
  #!/usr/bin/bash
  cd initramfs
  find . -print0 | cpio --null --create --verbose --format=newc | gzip -9 > ../initramfs.cpio.gz

XV_DIR := "../../xvisor"
LINUX_DIR := "../../linux"
[working-directory: 'busybox']
fs-xvisor: fs-linux
  #!/usr/bin/bash
  cd initramfs
  mkdir -p {system,images/riscv/virt64}
  cp {{XV_DIR}}/docs/banner/roman.txt system/banner.txt
  cp {{XV_DIR}}/docs/logo/xvisor_logo_name.ppm system/logo.ppm
  dtc -q -I dts -O dtb -o images/riscv/virt64-guest.dtb {{XV_DIR}}/tests/riscv/virt64/virt64-guest.dts
  cp {{XV_DIR}}/build/tests/riscv/virt64/basic/firmware.bin images/riscv/virt64/firmware.bin
  cp {{XV_DIR}}/tests/riscv/virt64/linux/nor_flash.list images/riscv/virt64/nor_flash.list
  cp {{XV_DIR}}/tests/riscv/virt64/linux/cmdlist images/riscv/virt64/cmdlist
  cp {{XV_DIR}}/tests/riscv/virt64/xscript/one_guest_virt64.xscript boot.xscript
  cp {{LINUX_DIR}}/build/arch/riscv/boot/Image images/riscv/virt64/Image
  dtc -q -I dts -O dtb -o images/riscv/virt64/virt64.dtb {{XV_DIR}}/tests/riscv/virt64/linux/virt64.dts
  cp ../initramfs.cpio.gz images/riscv/virt64/rootfs.img
  find . -print0 | cpio --null --create --verbose --format=newc > ../xvisor-initrd.cpio

[working-directory: 'linux']
linux-setup $CROSS_COMPILE='riscv64-linux-gnu-' $ARCH='riscv':
  mkdir -p build
  make O=./build defconfig
  scripts/config --file build/.config -d CONFIG_DRM -d CONFIG_TRANSPARENT_HUGEPAGE

[working-directory: 'linux']
linux $CROSS_COMPILE='riscv64-linux-gnu-' $ARCH='riscv':
  make O=./build -j16 Image

[working-directory: 'linux']
linux-llvm $CROSS_COMPILE='riscv64-linux-gnu-' $ARCH='riscv':
  mkdir -p build-llvm
  make O=./build-llvm LLVM=1 defconfig
  scripts/config --file build-llvm/.config -d CONFIG_DRM -d CONFIG_TRANSPARENT_HUGEPAGE
  make O=./build-llvm LLVM=1 -j16 Image
  scripts/clang-tools/gen_compile_commands.py -d build-llvm

# -cpu rv64,smaia=true,ssaia=true,sscofpmf=true
# -bios opensbi/build/platform/generic/firmware/fw_dynamic.bin

QEMU_OPTS := "\
-M virt \
-m 256M \
-smp 1 \
-nographic \
-global virtio-mmio.force-legacy=false \
-drive file=xv6-riscv/fs.img,if=none,format=raw,id=x0 \
-device virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0 \
"

run-xv6-debug-qemu:
  gdbserver :2345 qemu/build/qemu-system-riscv64 {{QEMU_OPTS}} \
    -bios none -kernel xv6-riscv/kernel/kernel

run-xv6-debug:
  qemu/build/qemu-system-riscv64 {{QEMU_OPTS}} \
    -bios none -kernel xv6-riscv/kernel/kernel -s -S

run-xv6:
  qemu/build/qemu-system-riscv64 {{QEMU_OPTS}} \
    -bios none -kernel xv6-riscv/kernel/kernel

run-linux:
  qemu/build/qemu-system-riscv64 {{QEMU_OPTS}} \
    -bios opensbi/build/platform/generic/firmware/fw_dynamic.bin \
    -kernel linux/build/arch/riscv/boot/Image \
    -initrd busybox/initramfs.cpio.gz -append "console=ttyS0 init=/init"

XV_CMDS := "\
vfs mount initrd /; \
vfs run /boot.xscript; \
guest kick guest0; \
vserial bind guest0/uart0; \
"

run-xvisor:
  qemu/build/qemu-system-riscv64 -M virt -m 512M -nographic \
    -bios opensbi/build/platform/generic/firmware/fw_dynamic.bin \
    -kernel xvisor/build/vmm.bin \
    -initrd busybox/xvisor-initrd.cpio -append 'vmm.bootcmd="{{XV_CMDS}}"'

#-d int,exec,cpu,mmu,nochain,op,in_asm
