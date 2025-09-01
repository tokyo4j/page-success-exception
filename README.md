# Page-success exception demo

- QEMU: https://github.com/tokyo4j/qemu/tree/page-success-exception
- xv6: https://github.com/tokyo4j/xv6-riscv/tree/page-success-exception

## Setup

```sh
git clone https://github.com/tokyo4j/page-success-exception
cd page-success-exception
git submodule update --init
just xv6
just qemu-setup
just qemu
just run
```

The output should look like:

```
$ just run
qemu/build/qemu-system-riscv64 -machine virt -bios none -kernel xv6-riscv/kernel/kernel -m 256M -smp 1 -nographic -global virtio-mmio.force-legacy=false -drive file=xv6-riscv/fs.img,if=none,format=raw,id=x0 -device virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0

xv6 kernel is booting

enclave content="
```

But if we apply the patch below:

```diff
diff --git a/kernel/start.c b/kernel/start.c
index 30fef0f..78be623 100644
--- a/kernel/start.c
+++ b/kernel/start.c
@@ -73,7 +73,7 @@ start()
   w_tp(id);

   // enable page-success exception
-  asm volatile("csrw %0, %1" :: "i"(CSR_MPSEC), "r"(CSR_MPSEC_ENABLE));
+  asm volatile("csrw %0, %1" :: "i"(CSR_MPSEC), "r"(CSR_MPSEC_DISABLE));
   // set machine mode exception vector
   asm volatile("csrw mtvec, %0" :: "r" (pse_entry));
   // store M-mode stack in mscratch
```

...the output should then look like:

```
$ just run
qemu/build/qemu-system-riscv64 -machine virt -bios none -kernel xv6-riscv/kernel/kernel -m 256M -smp 1 -nographic -global virtio-mmio.force-legacy=false -drive file=xv6-riscv/fs.img,if=none,format=raw,id=x0 -device virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0

xv6 kernel is booting

enclave content="This is enclave"

init: starting sh
$
```

This indicates that the read access to the enclave (which contains a message "This is enclave") is rejected by the page-success exception handler in the first output.

## Spec

- 2 new CSRs are added:
  - `mpsec`: Page-success exception control register
    - Writing `1` to `mpsec` enables page-success exception
    - Writing `2` to `mpsec` disables page-success exception
    - Writing `4` to `mpsec` accepts the address translation in page-success exception
    - Writing `8` to `mpsec` rejects the address translation in page-success exception
  - `mpsepa`: Page-success exception physical address register
    - Stores the physical address for the address translation handled in page-success exception
    - Note: read `mtval` for the virtual address
- When page-success exception is enabled, every TLB-miss in S-mode or U-mode are intercepted and it raises page-success exception in M-mode
- The page-success exception handler can accept or reject the address translation by writing `4` or `8` to `mpsec`
  - If the translation is accepted, the S-mode or U-mode program continues its execution after `mret`
  - If the translation is rejected, the same page-success exception is raised again after `mret` (I'm not sure how we should handle this)
- Page-success exceptions include the following 3 new exceptions:
  - _Page instruction fetch success exception_ (mcause=0x18)
  - _Page load success exception_ (mcause=0x19)
  - _Page store success exception_ (mcause=0x1a)
