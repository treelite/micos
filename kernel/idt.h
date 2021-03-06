/**
 * @file Interrupt Descriptor Table
 * @author treelite(c.xinle@gmail.com)
 */

#ifndef _IDT_H_
#define _IDT_H_

#include <stdint.h>
#include <string.h>
#include "kernel.h"
#include "console.h"

void init_idt();
void int_keyboard();
void sys_exception(uint32_t id, uint32_t error_code, uint32_t eip, uint32_t cs, uint32_t eflags);

#endif
