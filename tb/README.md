# Học môi trường UVM này từ tổng quan đến chi tiết

## 1. Hai thế giới: static HDL và dynamic UVM

`top/hw_top.sv` instantiate clock/reset interface, các bus interface và DUT.
Các module/interface tồn tại từ elaboration, nối với nhau bằng tín hiệu thật.

`top/tb_top.sv` tạo config object, gán virtual interface handles, đặt config cho
`uvm_test_top`, rồi gọi `run_test()`. Từ đây UVM factory tạo test và component tree.
Một virtual interface không phải bản sao bus; nó là handle trỏ đến interface HDL.

Hierarchy chính:

```text
uvm_test_top : router_base_test hoặc lớp kế thừa
└── env : router_env
    ├── yapp : yapp_agent
    │   ├── sequencer
    │   ├── driver
    │   └── monitor
    ├── channel0, channel1, channel2 : channel_agent
    │   └── mỗi agent có sequencer + driver suspend + monitor dữ liệu
    ├── hbus : hbus_agent
    ├── control : clock_reset_agent
    ├── virtual_sequencer
    ├── predictor : uvm_reg_predictor #(hbus_item)
    ├── bus_coverage
    └── router : router_module_env
        ├── reference_model
        ├── scoreboard
        ├── coverage
        ├── output_coverage
        └── error_checker

env.regs : router_reg_block (uvm_object, KHÔNG phải component trong tree)
```

Clock được sinh ở HDL. Clock/reset agent chỉ điều khiển reset và quan sát sự kiện
reset; không dùng class để giả lập một clock generator không cần thiết.

## 2. Lần theo một packet

Ví dụ `router_smoke_test` dùng `scenario()` của base test, gửi length=8 tới ba
channel. Để theo dõi chi tiết, chạy với `--verbosity UVM_HIGH`.

1. Test gọi `send(ch,8)` → tạo `yapp_packet_sequence`.
2. Sequence tạo `yapp_packet` bằng factory, `start_item()`, randomize có kiểm tra
   kết quả, rồi `finish_item()`.
3. Sequencer phân phối item cho driver. Driver `get_next_item()` và chuyển các
   byte qua `vif.drv_cb`. Sau từng byte phải chờ cạnh nhận không bị suspend.
4. Driver hoàn tất hoặc bị reset hủy rồi gọi `item_done()` để sequence tiếp tục.
5. Input monitor tự tái tạo packet từ bus. Nó không lấy packet trực tiếp từ driver.
6. Reference model nhận packet **đã quan sát được**, kết hợp config đọc từ HBUS
   monitor để quyết định route/drop, cập nhật trạng thái chức năng và counters.
7. Packet được route vào expected queue của đúng channel trong scoreboard.
8. Output monitor quan sát từng byte đã được receiver nhận và ghép thành packet.
9. Scoreboard pop một expectation và compare addr, length, payload, parity.
   Nếu đúng, phát `matched_ap` để đo checked-output coverage.

```text
sequence → sequencer → driver → input pins → DUT → output pins → channel monitor
                                      │                              │
                                 input monitor                       │ actual
                                      │                              ▼
                              reference model ── expected ──→ scoreboard
                                      │                              │
                               route coverage                 checked coverage

HBUS monitor ──→ reference model + explicit RAL predictor + bus coverage
Reset monitor ─→ reference reset + scoreboard flush + error-checker flush
```

Không nối stimulus sequence trực tiếp vào scoreboard. Cách đó có thể bỏ qua lỗi
driver/handshake: stimulus dự định gửi chưa chắc là stimulus DUT thật sự nhận.

## 3. Trách nhiệm từng lớp

| Thành phần | Có trách nhiệm | Không nên làm |
|---|---|---|
| Transaction | Mô tả packet, constraints, copy/compare/pack | Chờ clock, drive pin |
| Sequence | Chọn stimulus, phối hợp item | Truy cập FIFO nội bộ DUT |
| Driver | Chuyển item thành waveform hợp protocol | Tự quyết định expected output |
| Monitor | Tái tạo dữ liệu đã transfer | Sửa parity để packet luôn đúng |
| Agent | Đóng gói protocol + cấu hình active/passive | Chứa policy end-to-end router |
| Reference | Mô hình chức năng route/registers | Sao chép FSM hoặc FIFO implementation |
| Scoreboard | Match actual với expected, phát hiện thiếu/thừa/sai | Tự tạo stimulus |
| Coverage | Ghi nhận tình huống đã quan sát | Kết luận correctness thay scoreboard |
| Test | Cấu hình, objection, scenario, tiêu chí hoàn tất | Chứa chi tiết drive từng chân |

Các agent hỗ trợ active/passive ở cấp protocol. System env mặc định dùng tất cả
active; base test có stimulus trên các sequencer nên không thể chỉ đổi cờ sang
passive rồi mong mọi test vẫn chạy. Muốn passive observation phải có nguồn drive
bên ngoài và test phù hợp. Chưa có regression passive integration riêng.

## 4. Phases, factory, config

- `build_phase`: lấy config; factory-create các component con. Không nối TLM
  trước khi các con được tạo.
- `connect_phase`: nối driver/sequencer, analysis ports, RAL predictor/map.
- `end_of_elaboration_phase`: in topology để kiểm tra hierarchy.
- `run_phase`: test giữ objection qua reset, responders, scenario và drain.
- `check_phase`: phát hiện queue chưa rỗng, partial packet và test không có dữ liệu.
- `report_phase`: thống kê và sentinel PASS/FAIL; runner còn kiểm tra SVA/tool errors.

Sequence là object có lifetime ngắn; agent/driver/monitor là component sống theo
phase. Package chỉ là namespace và thứ tự compile, không phải component hierarchy.

Config gồm các object có kiểu rõ ràng; mỗi agent có virtual interface và active
mode riêng. Tránh rải nhiều string/integer keys khó tìm. Factory dùng cho cả
component và transaction. `router_factory_test` thay `yapp_packet` bằng
`short_yapp_packet` trước khi environment build.

Ở đây start sequence tường minh, không phụ thuộc `default_sequence` hoặc
`uvm_do` để người học nhìn được create → randomize → handshake. Không có quy tắc
UVM bắt buộc phải dùng hoặc cấm tuyệt đối những macro đó trong mọi project.

## 5. Timing không race

Driver clocking block: negedge, output skew #0. Monitor clocking block: posedge,
input skew #1step. DUT nhận cạnh lên; monitor thấy dữ liệu trước NBA update, tức
dữ liệu mà DUT thật sự nhận tại cạnh đó.

Ví dụ FIFO chứa một byte: monitor đọc byte trước khi pop ở cùng cạnh làm pointer
tiến sang byte tiếp theo. Đọc pin trực tiếp sau NBA có thể vô tình quan sát byte
sau và làm scoreboard lệch một byte.

`error` là output registered. Pulse gây ra tại cạnh nhận parity sẽ được clocking
monitor nhìn thấy ở cạnh kế tiếp. `router_error_checker` lưu timestamp packet
kết thúc và chỉ kiểm tra expectation cũ hơn `$time`, tránh phụ thuộc thứ tự gọi
các callback trong cùng timestep. Checker chờ reset đầu tiên trước khi kiểm tra.

SVA kiểm tra giữ dữ liệu khi stalled, known data và HBUS read hai chu kỳ. Chúng
có marker `SVA_FAILURE`; đây là lỗi simulation dù UVM report server không đếm
trực tiếp `$error` từ HDL.

## 6. Scoreboard và reset

Mỗi channel có queue expected riêng. Packet trong cùng channel phải đúng thứ tự;
không áp một thứ tự hoàn tất toàn cục lên cả ba channel độc lập.

- Có actual, không có expected → `UNEXPECTED_PACKET`.
- Có expected nhưng nội dung khác → `PACKET_MISMATCH`, vẫn consume expectation.
- Kết thúc còn expected → `MISSING_PACKET` hoặc drain timeout.
- Monitor còn packet dở dang → lỗi partial packet.
- Reset → flush pending queue và partial monitor packet; ghi nhận số expectation
  bị hủy vì reset, không báo missing cho những packet reset đã hủy hợp lệ.
- Điều kiện accounting: expected nhận vào = matched + mismatched + reset-flushed
  + pending. Unexpected được thống kê riêng.

Monitor tạo object mới mỗi packet; scoreboard clone expectation trước khi lưu.
Dynamic payload array được copy theo giá trị. `expected_parity()` là pure function,
không sửa `parity` thu được. Nếu hàm kiểm tra tự tính rồi ghi đè parity quan sát,
test parity âm rất dễ trở thành false pass.

Drain không chỉ `#1000`: base test đòi queue rỗng, không partial input/output,
không output valid trong bốn lần quan sát idle liên tiếp. Có watchdog 4.000 chu
kỳ drain và 100.000 chu kỳ toàn test. Khi mất packet, test phải fail có giới hạn.

## 7. RAL: abstraction, không phải bản sao phần cứng

`router_reg_model.svh` có `uvm_reg_block`, các `uvm_reg_field`, map 1 byte/address,
hai `uvm_mem` và `hbus_reg_adapter`. Model viết tay để thấy rõ configure/build;
project lớn thường sinh model từ một register specification duy nhất.

Luồng frontdoor:

```text
regs.ctrl.write() → default_map → adapter.reg2bus() → HBUS sequencer/driver → DUT
DUT/HBUS pins → HBUS monitor → predictor.bus_in → adapter.bus2reg() → RAL mirror
```

`set_auto_predict(0)`: mirror được cập nhật bởi một predictor quan sát bus. Cả
truy cập RAL lẫn raw HBUS đều được phản ánh; không bật thêm auto-predict gây
double prediction. `provides_responses=0`: driver trả dữ liệu read qua request
ban đầu trước `item_done()`, không tạo response queue không ai tiêu thụ.

Counter tăng do packet, không do HBUS write. Reference model dự đoán side effect
và gọi `predict()` cho counter trước khi test đọc. Monitor HBUS vẫn kiểm tra giá
trị bus đối chiếu mô hình chức năng độc lập. Memories dùng so sánh dữ liệu rõ ràng,
không giả định `uvm_mem` duy trì mirror đầy đủ như `uvm_reg`.

Giới hạn quan trọng: reference model cập nhật packet ở lúc thu đủ parity, còn
RTL tăng một số counter ở header. Test chỉ truy cập trạng thái sau packet/drain.
Muốn verify read/write đồng thời packet đang chạy, cần mở rộng input monitor
thành header/byte/completion events và chốt config đúng thời điểm; không chỉ bật
thêm một thread đọc register rồi dùng nguyên model hiện tại.

Backdoor dùng HDL root `tb_top.hardware.dut`. Test backdoor ghi bằng frontdoor,
đọc lại bằng `peek()` để kiểm tra HDL path và cross-check. Nó cần DPI/HDL access
thật của simulator. Không dùng backdoor để đưa expected data vào scoreboard.

## 8. Lộ trình học tương ứng các lab

| Chặng | File/chỗ đọc chính | Test hoặc bài tập |
|---|---|---|
| 1. Data object | `common/router_types.svh` | `router_packet_api_test`: clone, compare, pure parity, pack/unpack |
| 2. Test/phases | `tests/router_tests.svh`, `top/tb_top.sv` | In topology, tìm ai giữ objection |
| 3. UVC | `agents/yapp_agent.svh`, `common/router_config.svh` | Tách vai trò sequencer/driver/monitor |
| 4. Factory | `short_yapp_packet`, `router_factory_test` | Override type và kiểm tra constraint length |
| 5. Sequences | `sequences/router_sequences.svh` | Tự tạo directed payload sequence |
| 6. VIF/driver | `interfaces`, `top`, YAPP driver | Theo một packet length=1 trong waveform |
| 7. Integration | `env/router_env.svh` | YAPP + HBUS + 3 channel + reset |
| 8. Virtual sequence | `router_virtual_sequence` | Program max length rồi gửi legal/illegal packets |
| 9. TLM/scoreboard | `env/router_reference.svh`, `router_scoreboard.svh` | Chạy scoreboard negative test |
| 10. Module UVC | `router_module_env`, coverage subscribers | Theo các analysis exports và coverage sampling |
| 11. RAL | `ral/router_reg_model.svh`, register/memory tests | Frontdoor, explicit prediction, backdoor, memory walk |

Học từng chặng, không cần đọc hết mọi test class trong lần đầu. Tên lab trong
tài liệu cũ là lộ trình khái niệm; đây không phải bản chép lời giải từng file lab.

## 9. Thêm test mới đúng cách

1. Kế thừa `router_base_test`, đăng ký factory, override `scenario()`.
2. Nếu cần cấu hình khác, đặt trong `build_phase()` trước khi child env build.
3. Tái sử dụng `send`, `write_register`, `raw_access`, `wait_for_drain`.
4. Thêm case/seed vào `sim/regression.json`, gắn requirement trong verification plan.
5. Chạy static check, test mới, rồi `core` và `negative` regression trên simulator.
6. Nếu đổi protocol/DUT, cập nhật specification, reference và tests theo review;
   không sửa expectation chỉ để chạy xanh.

Debug theo thứ tự: `RANDOMIZE` → `YAPP_OBSERVED` → `HBUS_OBSERVED` → route decision
→ `SCOREBOARD_STATS`/`REFERENCE_STATS` → error ID cụ thể. Khi lỗi timing, mở VCD
trước khi chỉnh compare. Khi lỗi RAL, xác minh map, byte address, read latency,
adapter response convention, predictor connection và HDL path.
