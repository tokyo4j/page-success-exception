[working-directory: 'xv6-riscv']
xv6:
  make -j16 fs.img kernel/kernel

[working-directory: 'qemu']
qemu-setup:
  mkdir -p build
  cd build; CC=clang ../configure --target-list="riscv64-softmmu" --disable-fuse --disable-user --enable-debug

[working-directory: 'qemu']
qemu:
  make -C build -j16

QEMU_OPTS := "\
-machine virt \
-bios none \
-kernel xv6-riscv/kernel/kernel \
-m 256M \
-smp 1 \
-nographic \
-global virtio-mmio.force-legacy=false \
-drive file=xv6-riscv/fs.img,if=none,format=raw,id=x0 \
-device virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0 \
"

run-debug-qemu:
  gdbserver :2345 qemu/build/qemu-system-riscv64 {{QEMU_OPTS}}

run-debug-xv6:
  qemu/build/qemu-system-riscv64 {{QEMU_OPTS}} -s -S

run:
  qemu/build/qemu-system-riscv64 {{QEMU_OPTS}}

#-d int,exec,cpu,mmu,nochain,op,in_asm
