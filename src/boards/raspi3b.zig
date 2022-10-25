pub const boardConfig = @import("boardConfig.zig");

// mmu starts at lvl1 for which 0xFFFFFF8000000000 is the lowest possible va
const vaStart: usize = 0xFFFFFF8000000000;
pub const config = boardConfig.BoardConfig{
    .board = .raspi3b,
    .mem = boardConfig.BoardConfig.BoardMemLayout{
        .va_start = vaStart,

        .bl_stack_size = 0x1000,
        .k_stack_size = 0x1000,

        .has_rom = false,
        // the kernel is loaded by into 0x8000 ram by the gpu, so no relocation (or rom) required
        .rom_start_addr = null,
        .rom_size = null,
        // address to which the bl is loaded if there is NO rom(which is the case for the raspberry 3b)!
        // if there is rom, the bootloader must be loaded to 0x0 (and bl_load_addr = null!)
        .bl_load_addr = 0x80000,

        // the raspberries addressable memory is all ram
        .ram_start_addr = 0,
        .ram_size = 0x40000000,

        .ram_layout = .{
            .kernel_space_size = 0x20000000,
            // !kernel_space_phys already includes the offset to the kernel space!
            .kernel_space_phys = 0,
            .kernel_space_gran = boardConfig.Granule.FourkSection,

            .user_space_size = 0x20000000,
            // !user_space_phys already includes the offset to the user space!
            .user_space_phys = 0,
            .user_space_gran = boardConfig.Granule.Fourk,
        },
        .storage_start_addr = 0,
        .storage_size = 0,
    },
    .qemu_launch_command = &[_][]const u8{ "qemu-system-aarch64", "-machine", "raspi3b", "-device", "loader,addr=0x80000,file=zig-out/bin/mergedKernel,cpu-num=0,force-raw=on", "-serial", "stdio", "-display", "none" },
};

pub fn PeriphConfig(addr_space: boardConfig.AddrSpace) type {
    comptime var device_base_tmp: usize = 0x3f000000;

    if (addr_space.isKernelSpace())
        device_base_tmp = config.mem.va_start + 0x40000000;

    return struct {
        pub const device_base_size: usize = 0x400000;
        pub const device_base: usize = device_base_tmp;

        pub const Pl011 = struct {
            pub const base_address: u64 = device_base + 0x201000;

            // config
            pub const base_clock: u64 = 0x124f800;
            // 9600 slower baud
            pub const baudrate: u32 = 115200;
            pub const data_bits: u32 = 8;
            pub const stop_bits: u32 = 1;
        };

        pub const Timer = struct {
            pub const base_address: usize = device_base + 0x00003000;
        };

        pub const InterruptController = struct {
            pub const base_address: usize = device_base + 0x0000b200;
        };
    };
}
