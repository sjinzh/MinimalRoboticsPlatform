# Embedded Robotics Kernel

## Goal

The goal is to build a minimalistic robotic platform for embedded projects. The idea is to enable applications to run on this kernel with std support as well as a kernel-provided, robotics-specific toolset. Such a toolset includes communication, control, state handling, and other critical robotic domains. This would enable an ultra-light, simplistic and highly integrated robotic platform.
The whole project is designed to support multiple boards, as for example a Raspberry Pi or a NVIDIA Jetson Nano. To begin with, basic kernel features are implemented on a virtual machine (qemu virt armv7).

The end product is meant to be a compromise between a Real Time Operating system and a Microcontroller, to offer the best of both worlds on a modern Soc.

## Why not Rust?

I began this project in Rust but decided to switch to Zig (equally modern). Here is why.
The prime argument for Rust is safety, which is also important for embedded development but has a different nature. The thing is that I very rarely (wrote) saw embedded code that really made use (at least to an extent to which it would be relevant) of Rusts safety. This is due to the fact that embedded code is mostly procedural and linear and not overly complex (opposing to higher level code). Zig on the other hand, is a real improvement compared to Rust because it does not try to solve the problem through abstraction but concepts and rules. I really tried rust at the start of this project. That lead me to this conclusion.

The Rust code can still be found in the separate [rust branch](https://github.com/luickk/rust-rtos/tree/rust_code) and includes a proper Cargo build process(without making use of an external build tools) for the Raspberry, as well as basic serial(with print! macro implementation) and interrupt controller utils.

## Compatibility

| generic int. cont. | generic timer | boot with rom | boot without rom | bcm2835 interrupt controller | bcm2835 timer |             |
|--------------------|---------------|---------------|------------------|------------------------------|---------------|-------------|
| ✅                  | ✅             | ✅             | ❌                | ❌                            | ❌             | qemu virt   |
| ❌                  | ❌             | ❌             | ✅                | ✅                            | ✅             | raspberry3b |
| ✅                  | ✅             | ❌             | ✅                | ❌                            | ❌             | raspberry 4 |

The Generic interrupt controler, generic timer, booting with/out rom, bcm2835 interrupt controller are all supported, thus all of the three boards are bootable. 
The bcm2835 timer is making problems though, I think the issue is stemming from qemu. I created an [issue on the gh](https://gitlab.com/qemu-project/qemu/-/issues/1651).


## Features

### Topics

A way to share data streams with other processes, similar to pipes but optimized for sensor data and data distribution and access over many processes.

Currently, the interfaces for topics are implemented via Syscalls which isn't very effective, but future versions will support push/pop operations with zero kernel overhead through memory mapping in the user-space.

### Services

// todo

### Actions

// todo

## Bootloader and kernel separation

Because it simplifies linking and building the kernel as a whole. Linking both the kernel and bootloader is difficult(and error-prone) because it requires the linker to link symbols with VMA offsets that are not supported in size and causes more issues when it comes to relocation of the kernel. 
Both the bootloader and kernel are compiled&linked separately, then their binaries are concatenated(all in build.zig). The bootloader then prepares the exception vectors, mmu, memory drivers and relocates the kernel code.

The bootloader is really custom and does a few things differently. One of the primary goals is to keep non static memory allocations to an absolute minimum. This is also true for the stack/ paging tables, which have to be loaded at runtime. At the moment both, bootloader stack and page tables are allocated on the ram, to be more specific in the specified userspace section. This allows to boot from rom(non writable memory...) whilst still supporting boot from ram.

## MMU

I wrote a mmu "composer" with which one can simply configure and then generate/ write the pagetables. The page table generation supports 3 lvls and 4-16k granule. 64k is also possible but another level has to be added to the `TransLvl` enum in `src/board/boardConfig.zig` and it's not fully tested yet.
Ideally I wanted the page tables to be generated at comptime, but in order to have multiple translation levels, the mmu needs absolute physical addresses, which cannot be known at compile time(only relative addresses). Alternative the memory can be statically reserved and written at runtime, which is not an option for the bootloader though because it is possibly located in rom, and cannot write to statically reserved memory, leaving the only option, allocating the bootloader page table on the ram (together with the stack). The kernel on the other hand could reserve at least the kernel space page tables, since they are static in size, but for consistency reasons kernel and userspace have linker-reserved memory.

### Addresses

The Arm mmu is really powerful and complex in order to be flexible. For this project the mmu is not required to be flexible, but safe and simple. For an embedded robotics platform it's neither required to have a lot of storage, nor to control the granularity in an extremely fine scope since most of the memory is static anyways.

Additionally devices as for example the Raspberry Pi forbid Lvl 0 translation at all since it's 512gb at 4k granule which is unnecessary for such a device.

With those constraints in place, this project only supports translation tables beginning at lvl 1, which is also why, `vaStart` is `0xFFFFFF8000000000`, since that's the lowest possible virtual address in lvl 1.

### Qemu Testing

In order to test the bootloader/ kernel, qemu offers `-kernel` but that includes a number of abstractions that are not wanted since I want to keep the development at least somewhat close to a real board. Instead, the booloader (which includes the kernel) is loaded with `-device loader`.

## Implementations

### CPU
#### Interrupt controller

The Raspberry ships with the BCM2835, which is based on the Arm A53 but does not adapt its interrupt controller. More about the BCM2835s ic can be found [here](https://www.raspberrypi.org/app/uploads/2012/02/BCM2835-ARM-Peripherals.pdf)(p109) and [here](https://xinu.cs.mu.edu/index.php/BCM2835_Interrupt_Controller). The [linux driver implementation](https://github.com/torvalds/linux/blob/master/drivers/irqchip/irq-bcm2835.c) comments are also worth looking at.


#### MMU

The best lecture to understand the MMU is probably the [official Arm documentation](https://developer.arm.com/documentation/100940/0101), which does a very good job of explaining the concepts of the mmu.
Since this project requires multiple applications running at the same time, virtual memory is indispensable for safety and performance.

## Installation

### Dependencies:

- zig (last tested version 0.10.1)
- qemu (for testing)

### Run

- `zig build qemu`
Builds and runs the project. The environment and board as well as all the other parameters for the build can be configured in build.zig
