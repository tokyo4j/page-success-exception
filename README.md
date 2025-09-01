# Page success例外デモ

- QEMU: https://github.com/tokyo4j/qemu/tree/page-success-exception
- xv6: https://github.com/tokyo4j/xv6-riscv/tree/page-success-exception

## 実行

```sh
git clone https://github.com/tokyo4j/page-success-exception
cd page-success-exception
git submodule update --init
just xv6
just qemu-setup
just qemu
just run
```

## 出力

```sh
xv6 kernel is booting

init: starting sh
$ etest
[ECREATE] id:1
start=1000, end=4000
enclave_size=3000
[EADD] id:1 va:1000->pa:87f2a000
[EADD] id:1 va:2000->pa:87f29000
[EADD] id:1 va:3000->pa:87f28000
[EENTER] id:1 pc:1000
[EEXIT]
result=213D0
```

## ハードウェア仕様

- Page success例外: TLBミスでPage table walkが成功した後にM-modeに投げられる例外
  - M-modeの例外ハンドラはアドレス変換を承認または拒否することができる
    - アドレス変換を承認して`mret`命令を実行すると、TLBエントリが埋められ、S-mode/U-modeでの実行が再開される
    - アドレス変換を拒否して`mret`命令を実行すると、再びPage success例外が投げられる(要検討)
- 2つのCSRを追加:
  - `mpsec`: Page success exception control register
    - `1`を書き込むとPage success例外を有効化
    - `2`を書き込むとPage success例外を無効化
    - `4`を書き込むとアドレス変換を承認
    - `8`を書き込むとアドレス変換を拒否
  - `mpsepa`: Page success exception physical address register
    - Page success例外が発生したアドレス変換における物理アドレス
    - Note: 仮想アドレスは`mtval`を参照
- 3つの例外を追加:
  - _Page instruction fetch success exception_ (mcause=0x18)
  - _Page load success exception_ (mcause=0x19)
  - _Page store success exception_ (mcause=0x1a)

## xv6における実装

### Memory tracking table (`kernel/firmware/firmware.c:strcut mtte`)

```c
struct mtte {
  uint64 va;
  uint8 id;
};
```

AMD SEV-SNPにおけるRMPと同様、全ての物理メモリページのEnclave IDと仮想アドレスを保持する

### ブート時 (`kernel/firmware/firmware.c:start()`)

- Page success例外を有効化
- M-mode用の割り込みベクタを設定

### 例外ハンドラ (`kernel/firmware/firmware.c:firmware_trap()`)

- Page success例外: MTTを参照してメモリアクセスを制限
  - ファームウェアへのアクセスを拒否
  - Enclaveから通常のOS/アプリの命令フェッチを拒否
  - Enclaveからの全てのメモリアクセスで、仮想アドレスとEnclave IDがMTTエントリと一致することを確認
  - 通常のOS/アプリからEnclaveのメモリへのアクセスを拒否
- Illegal Instruction例外: `a0`レジスタの内容に応じて`ECREATE`、`EADD`、`EENTER`、`EEXIT`命令を実行
  - `ECREATE()`:
    - Enclaveの実行コンテキストを作成し、Enclave IDを返す
    - S-modeから実行
  - `EADD(id, epc_pa, va)`:
    - 通常の物理メモリページをEnclaveに割り当てる
    - S-modeから実行
    - `id`: Enclave ID
    - `epc_pa`: 割り当てる物理メモリページのアドレス
    - `va`: マッピングする仮想アドレス
  - `EENTER(id, pc)`:
    - Enclaveの実行を開始
    - U-modeから実行
    - `id`: 実行するEnclaveのID
    - `pc`: ジャンプするコードの仮想アドレス
  - `EEXIT()`
    - Enclaveの実行を終了し、通常のアプリに戻る
    - U-modeから実行

### システムコール (`kernel/enclave.c`)
- `u64 ecreate(void)`
- `void eadd(enclave_id, va)`
  - プロセスにおいて`va`にマッピングされている物理ページを、`EADD`命令によってEnclaveに割り当てる

### テストアプリケーション (`user/etest.c`)
- `ecreate()` システムコールでEnclaveを作成
- `eadd()` システムコールで、Enclaveで実行するプログラム及びスタック領域を割り当て
- `EENTER`命令で`enclave_entry()`にジャンプし、Enclaveの実行を開始
- `enclave_entry()`は使用するスタックを切り替えた後`enclave_main()`にジャンプ
- `enclave_main()`はフィボナッチ数列を計算し、32番の要素を`fib_result`に保存
- `enclave_entry()`が`EEXIT`命令を実行し、通常のアプリにジャンプ
- `fib_result`の内容を出力
