# YAPP Router — UVM learning implementation

Project này là một môi trường verification hoàn chỉnh về cấu trúc để học UVM:
transaction, constraints, factory, agent, virtual interface, sequence, virtual
sequence, reference model, scoreboard, coverage, assertions và register model.

**Trạng thái:** đã viết code và kiểm tra ngữ nghĩa toàn bộ hierarchy với thư viện
UVM thật; RTL đã chạy self-test độc lập. **Chưa chạy regression UVM trên Xcelium**
vì máy hiện tại không có simulator/license phù hợp. Không coi đây là sign-off IP.
Chi tiết bằng chứng nằm trong [báo cáo kiểm chứng](tb/VALIDATION.md).

## Bắt đầu đọc từ đâu?

1. Đọc [đặc tả RTL](RTL/README.md) để biết DUT cần làm gì.
2. Đọc [hướng dẫn kiến trúc và lộ trình học](tb/README.md).
3. Mở `tb/tests/router_tests.svh`, tìm `router_smoke_test` và `router_base_test`.
4. Lần theo một packet qua `sequences`, `agents/yapp_agent.svh`, DUT,
   `agents/channel_agent.svh`, rồi `env/router_scoreboard.svh`.
5. Đọc [verification plan](tb/VERIFICATION_PLAN.md) trước khi xem các test nâng cao.

## Cấu trúc

```text
yapp_router_implement/
├── README.md
├── RTL/
│   ├── yapp_router.sv          DUT học tập mới, mặc định được compile
│   ├── yapp_fifo.sv            Ba FIFO đầu ra, mỗi FIFO 16 byte
│   ├── README.md              Đặc tả và khác biệt với Cadence
│   └── reference/
│       └── cadence_yapp_router.sv  Bản tham khảo riêng tư, KHÔNG compile
└── tb/
    ├── router_tb_pkg.sv        Thứ tự include/dependency của các class
    ├── common/                Transaction và config objects
    ├── interfaces/            Pin-level interfaces, clocking blocks, SVA
    ├── agents/                YAPP, channel, HBUS, clock/reset
    ├── sequences/             Stimulus và virtual sequence
    ├── env/                   Reference model, scoreboard, coverage, env
    ├── ral/                   Register block, memories, bus adapter
    ├── tests/                 Các test kế thừa base test
    ├── top/                   Static hardware top + UVM startup
    ├── sim/                   File list, regression manifest, local results
    ├── tools/                 Runners, static checker, RTL-only self-test
    ├── README.md
    ├── VERIFICATION_PLAN.md
    └── VALIDATION.md
```

## Chạy UVM bằng Xcelium

Chạy trên máy Linux đã được cấu hình Xcelium và license của bạn. Python 3.10+
chỉ dùng thư viện chuẩn cho runner. Chỉ định thư viện UVM tương thích với bản
Xcelium đang cài; không trộn hai thư viện `uvm_pkg` vào cùng lần compile.

Ví dụ, từ thư mục project trên máy simulator:

```bash
export UVMHOME=/path/to/simulator-compatible/uvm
python3 tb/tools/run.py --list
python3 tb/tools/run.py --test router_smoke_test --seed 1
python3 tb/tools/run.py --suite core
python3 tb/tools/run.py --suite negative
python3 tb/tools/run.py --suite extended
```

`UVMHOME` là thư mục có `src/uvm_pkg.sv`, không phải chính thư mục `src`.
Project dùng API theo IEEE 1800.2; static validation dùng Accellera UVM
`2020.3.1`. Xcelium CLI/DPI integration vẫn cần được xác nhận trên host thật.

Các lựa chọn hữu ích:

```bash
python3 tb/tools/run.py --test router_virtual_test --seed 42 --verbosity UVM_HIGH
python3 tb/tools/run.py --test router_smoke_test --waves
python3 tb/tools/run.py --suite core --coverage --timeout 600
python3 tb/tools/run.py --suite all --dry-run
```

Runner hoạt động từ bất kỳ working directory nào. Mỗi lần chạy tạo một thư mục
riêng trong `tb/sim/results/`, có command, log, seed, source hashes và summary.
Không xóa hoặc ghi đè kết quả lần trước. `--dry-run` chỉ in lệnh, không chạy
simulator, không tạo thư mục kết quả. `--coverage` yêu cầu simulator ghi coverage
database; nó không tự merge database hay khẳng định coverage closure.

Muốn chạy lệnh trực tiếp, đứng tại `tb/sim`:

```bash
xrun -64bit -sv -uvmhome "$UVMHOME" -timescale 1ns/1ps \
  -access +rwc -f files.f -top tb_top -seed 1 \
  +UVM_TESTNAME=router_smoke_test +UVM_VERBOSITY=UVM_LOW
```

Sau một test dương phải có `[TEST_PASS]`, không có UVM_ERROR/UVM_FATAL,
`SVA_FAILURE`, timeout hoặc lỗi simulator. Đừng dùng exit code 0 làm tiêu chí
duy nhất. Hai test âm phải báo `EXPECTED_FAIL` với đúng error IDs mà manifest
quy định; compile fail không phải một ca negative test thành công.

## Khi chưa có simulator UVM

RTL self-test dùng Icarus; không thay thế UVM simulation:

```bash
python3 tb/tools/run_rtl_checks.py
python3 tb/tools/test_runner.py
```

Trên Windows có thể chỉ định thư mục chứa `iverilog.exe` và `vvp.exe`:

```powershell
python tb/tools/run_rtl_checks.py --iverilog-dir C:\path\to\iverilog\bin
```

Static check cần `pyslang==11.0.0` và source UVM riêng:

```bash
python3 tb/tools/check_sv.py --uvm-home /path/to/uvm-core
```

Không dùng Icarus để compile `tb/router_tb_pkg.sv`: script RTL chỉ compile DUT
và `rtl_selftest.sv`. Static checker tắt DPI bằng `UVM_NO_DPI` cho mục đích phân
tích; lệnh Xcelium không tắt DPI vì backdoor RAL cần chức năng này.

## Phạm vi và nguồn gốc

- `RTL/yapp_router.sv` là RTL học tập **mới**, với contract được ghi rõ trong
  `RTL/README.md`. Không phải RTL Cadence đã được chứng nhận hoặc bản vá của nó.
- `RTL/reference/cadence_yapp_router.sv` giữ nội dung nguồn tham khảo bạn cung
  cấp, gồm thông báo bản quyền; chỉ khác chuẩn xuống dòng. File bị loại khỏi
  `files.f` và được `.gitignore` để giảm nguy cơ commit nhầm. `.gitignore` không
  phải biện pháp kiểm soát truy cập hay giấy phép phân phối.
- Không sửa folder lab gốc ở ổ D. Không chép PDF, tên người học hay watermark
  từ bài giảng vào tài liệu project. Không có bước upload, deploy, push hoặc
  public project. Nguồn tham khảo Cadence vẫn chịu điều kiện sử dụng ban đầu;
  không công bố project có chứa file đó nếu chưa có quyền.
- Project ưu tiên khả năng học và debug. Chưa có chứng nhận tái sử dụng VIP,
  formal proof, synthesis/timing sign-off hoặc regression đa simulator.

Thư viện chuẩn tham chiếu:
[Accellera UVM downloads](https://www.accellera.org/downloads/standards/uvm),
[Accellera UVM 2020.3.1](https://github.com/accellera-official/uvm-core/releases/tag/2020.3.1).
Đây là phiên bản dùng kiểm tra trong project, không phải tuyên bố phiên bản mới nhất.
