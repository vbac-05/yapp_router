# YAPP Router — UVM learning implementation

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
