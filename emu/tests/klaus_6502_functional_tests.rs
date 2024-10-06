use rustella::{cmn, cpu, riot};
use std::{cell::Cell, fs, path::PathBuf, rc::Rc};

/* NOTE: This is not complete yet. ADC/SBC bin & dec part of the tests are not done. */

/// Test suite from https://github.com/Klaus2m5/6502_65C02_functional_tests.
#[test]
fn klaus_6502_65c02_functional_tests_main() {
    log::set_logger(&win_dbg_logger::DEBUGGER_LOGGER).unwrap();
    log::set_max_level(log::LevelFilter::Debug);

    let bin_path: PathBuf = [
        env!("CARGO_MANIFEST_DIR"),
        "tests",
        "bins",
        "klaus_6502_functional_test.bin",
    ]
    .iter()
    .collect();

    let buffer = fs::read(bin_path).unwrap();
    let mut mem =
        riot::Memory::new_with_rom(&buffer, 0x0000.into(), riot::mm_6502, None, None, true);
    let rdy = Rc::new(Cell::new(cmn::LineState::High));
    let mut cpu = cpu::NMOS6502::new(rdy.clone(), &mem);
    cpu.set_pc(cmn::LoHi(0x00, 0x04));

    loop {
        cpu.tick(&mut mem);
        if cpu.instructions() == 54483 {
            break;
        }
    }

    assert_eq!(mem.get(cmn::LoHi(0x00, 0x02), 0), 0x29, "CPU: {cpu:?}"); // NOTE: This indicates the number of tests ran.
    assert_eq!(cpu.cycles(), 125200);
    assert_eq!(cpu.pc(), cmn::LoHi(0x08, 0x33));
    assert_eq!(cpu.a(), 0x29);
    assert_eq!(cpu.x(), 0xFE);
    assert_eq!(cpu.y(), 0xFF);
    assert_eq!(cpu.psr(), 0x49);
    assert_eq!(cpu.s(), 0xFF);
}
