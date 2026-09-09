# Báo cáo kiểm chứng — 2026-09-09

## Kết luận trung thực

Đã kiểm tra ngữ nghĩa SystemVerilog/UVM với thư viện Accellera thật và chạy RTL
simulation có kiểm tra dữ liệu/counter/memory. **Chưa có UVM runtime regression
trên Xcelium hoặc Questa** tại host này. Do đó chưa xác nhận hành vi scheduler
của các UVM sequence/driver, constraints tại runtime, coverage database, DPI hoặc
RAL backdoor trên simulator thương mại. Các test đó đã có code, chưa có runtime PASS.

## 1. Static SystemVerilog/UVM

- Tool: `pyslang 11.0.0`.
- Library: Accellera `uvm-core 2020.3.1`, gồm `uvm_pkg.sv` thật.
- Top: `tb_top`; parse/elaborate tất cả nguồn trong `sim/files.f` và include tree.
- DPI tắt bằng `UVM_NO_DPI` chỉ trong checker, không phải cấu hình runtime.
- Kết quả: **0 errors, 1 warning**.
- Warning nằm trong `uvm_config_db_implementation.svh` của thư viện UVM:
  unknown escape `\.`. Không sửa source thư viện để che warning.

Static success không phải bằng chứng không còn race/deadlock, cũng không thay
cho compile/elaborate/run bằng Xcelium trên host được cấp license.

## 2. RTL-only simulation đã thực sự chạy

Tool: Icarus Verilog 13.0, local native executable. Testbench:
`tools/rtl_selftest.sv`. Chạy clean DUT và FIFO; không compile UVM class,
clocking-block interfaces hoặc SVA của project.

| Seed | Packet hoàn tất | Packet drop | Output byte đã compare | Error pulse đã check | Input stalled cycles | Kết quả |
|---|---:|---:|---:|---:|---:|---|
| 1 | 499 | 68 | 6.359 | 81 | 3.105 | PASS |
| 7 | 499 | 70 | 6.056 | 77 | 2.978 | PASS |
| 42 | 499 | 77 | 5.695 | 63 | 2.722 | PASS |
| 2026 | 499 | 63 | 6.539 | 73 | 3.482 | PASS |

Mỗi run gồm routing 3 channel, length boundaries, illegal/zero/oversize/disabled,
bad parity forward + pulse, random receiver stalls, long forced stall, 200 random
packets, counter checks, RO-write-ignore, last packet window, scratch sweep256,
counter wrap260→4, reset giữa packet và traffic sau reset. Số 499 không tính
packet được cố tình reset hủy khi mới gửi một phần.

Icarus có hai thông báo về constant selects trong `always_comb`: tool mở rộng
sensitivity list sang toàn vector. Không có compile errors; mô phỏng chạy đến
sentinel `RTL_SELFTEST_PASS` với exit code 0.

## 3. Checker/fault-injection tests đã thực sự chạy

| Ca RTL-only | Injection | Lỗi quan sát | Kết quả |
|---|---|---|---|
| scoreboard_fault | Đảo expected parity packet đầu | DATA_MISMATCH channel0, byte9 | EXPECTED_FAIL, exit1 |
| memory_fault | INJECT_ERROR đảo write tại 0x110f | HBUS_MISMATCH expected=aa actual=55 | EXPECTED_FAIL, exit1 |

Đây là kiểm chứng checker của **RTL self-test**, không phải tuyên bố các UVM
negative test đã chạy. UVM negative tests có cơ chế tương tự và vẫn cần chạy
bằng `run.py --suite negative` trên Xcelium.

Các bước kiểm tra và review đã giúp sửa: enum assignment để phù hợp Icarus, checker
không kiểm tra state chưa reset, các tên coverage bins trùng keyword và syntax
coverage, và khởi tạo tường minh các bộ đếm thống kê UVM. Không sửa RTL Cadence gốc.

## 4. Regression tooling

`tools/test_runner.py`: **11 unit tests PASS**, kiểm tra phân loại PASS/FAIL/EXPECTED_FAIL: không false-pass
khi chỉ có exit0, thiếu sentinel, có UVM_ERROR, có SVA_FAILURE, lỗi compile,
timeout, UVM_FATAL hoặc summary lỗi. Cũng kiểm tra ID manifest không trùng và
mọi class test được tham chiếu đều tồn tại.

`run.py --suite all --dry-run` tạo lệnh cho toàn bộ test/seed mà không chạy simulator.
Dry-run không chứng minh các cờ CLI/DPI tương thích mọi phiên bản Xcelium.

RTL result runner lưu command và log thật trong `sim/results/rtl_*` cùng
`summary.json`. Kết quả sinh ra bị `.gitignore`, không được đưa vào source build.
Project không vendor UVM hoặc simulator binaries; dependencies dùng kiểm tra
được đặt riêng ngoài folder project.

## 5. Chạy lại

Từ root project trên host đã có tool/dependency tương ứng:

```bash
python3 tb/tools/check_sv.py --uvm-home /path/to/uvm-core
python3 tb/tools/test_runner.py
python3 tb/tools/run_rtl_checks.py --seeds 1,7,42,2026
python3 tb/tools/run.py --suite all --uvm-home /path/to/uvm --dry-run
```

`pyslang` có thể được chỉ định từ thư mục dependency riêng bằng `--python-deps`.
Icarus có thể được chỉ định bằng `--iverilog-dir`. Các runner không tải lên dữ
liệu và không tự sửa code.

## 6. Việc cần xác nhận trên host Xcelium

1. Smoke chạy đến `[TEST_PASS]`, topology đúng và không protocol/SVA errors.
2. Core regression qua các seed, counters/memory không mismatch.
3. Hai negative cases được runner báo `EXPECTED_FAIL`, không phải compile fail.
4. Extended suite xác nhận DPI/backdoor và built-in memory walk.
5. Coverage database thực sự được tạo; review uncovered bins, không suy tỷ lệ
   coverage từ số test được viết.
6. Lưu simulator/UVM versions, log và source hashes của lần chạy đó trước khi
   gọi project đã runtime-validated.

Nguồn công cụ công khai dùng để kiểm tra:
[Accellera UVM 2020.3.1](https://github.com/accellera-official/uvm-core/releases/tag/2020.3.1),
[MSYS2 Icarus package](https://packages.msys2.org/packages/mingw-w64-ucrt-x86_64-iverilog).
Chỉ tải dependency công khai về local; không gửi source/doc Cadence đến dịch vụ
EDA online. Source tham khảo riêng tư không nằm trong compile list.
