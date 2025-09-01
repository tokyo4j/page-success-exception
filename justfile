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
  find . -print0 | cpio --null -ov --format=newc | gzip -9 > ../initramfs.cpio.gz

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

#-d int,exec,cpu,mmu,nochain,op,in_asm
