/*
 * bl31_services.c -- Bare-metal, libc-free SMC handler for BL31
 *
 * Features:
 * - PING / VERSION
 * - Secure store read/write
 * - Key management + demo XOR crypto (in-place)
 * - PSCI-like stubs (cpu_on, cpu_off, system_reset)
 * - All memory functions are firmware-safe (fw_memcpy, fw_memset, fw_strcpy)
 *
 * NOTES:
 * 1. Replace demo_crypto_xor with a real AES or HW crypto for real use.
 * 2. Update NS_RAM_START/END to match your non-secure RAM range.
 * 3. Platform hooks for reset/cpu_on/off should be implemented for real PSCI.
 */

#include <stdint.h>

/* ------------------------------------------------------------------------
 * Firmware-safe memory helpers
 * ------------------------------------------------------------------------ */
static void *fw_memcpy(void *dst, const void *src, unsigned long n)
{
    uint8_t *d = (uint8_t *)dst;
    const uint8_t *s = (const uint8_t *)src;
    for (unsigned long i = 0; i < n; i++)
        d[i] = s[i];
    return dst;
}

static void *fw_memset(void *dst, int value, unsigned long n)
{
    uint8_t *d = (uint8_t *)dst;
    for (unsigned long i = 0; i < n; i++)
        d[i] = (uint8_t)value;
    return dst;
}

static char *fw_strcpy(char *dst, const char *src)
{
    char *d = dst;
    while ((*d++ = *src++) != 0)
        ;
    return dst;
}

/* ------------------------------------------------------------------------
 * SMC FIDs (vendor range: 0x8200_0000)
 * ------------------------------------------------------------------------ */
#define SMC_FID_PING              0x82000000ULL
#define SMC_FID_GET_VERSION       0x82000001ULL
#define SMC_FID_SECSTORE_WRITE    0x82001000ULL
#define SMC_FID_SECSTORE_READ     0x82001001ULL
#define SMC_FID_KEY_IMPORT        0x82002000ULL
#define SMC_FID_CRYPTO_ENCRYPT    0x82002010ULL
#define SMC_FID_CRYPTO_DECRYPT    0x82002011ULL
#define SMC_FID_CPU_ON            0x82003000ULL
#define SMC_FID_CPU_OFF           0x82003001ULL
#define SMC_FID_SYSTEM_RESET      0x82003002ULL

/* Return codes */
#define SMC_OK                    0ULL
#define SMC_ERROR                 ((uint64_t)-1)
#define SMC_INVALID_PARAM         ((uint64_t)-2)
#define SMC_NOT_SUPPORTED         ((uint64_t)-3)
#define SMC_ACCESS_DENIED         ((uint64_t)-4)
#define SMC_INSUFFICIENT_SPACE    ((uint64_t)-5)

/* Version */
#define BL31_SVC_VER_MAJOR 1
#define BL31_SVC_VER_MINOR 0

/* ------------------------------------------------------------------------
 * Non-secure RAM range for pointer validation
 * ------------------------------------------------------------------------ */
#define NS_RAM_START 0x40000000ULL
#define NS_RAM_END   0x47FFFFFFULL

static inline int is_nonsecure_ptr(uint64_t addr, uint64_t len)
{
    if (len == 0) return 0;
    if (addr < NS_RAM_START) return 0;
    if ((addr + len - 1) > NS_RAM_END) return 0;
    return 1;
}

/* ------------------------------------------------------------------------
 * Secure store (demo)
 * ------------------------------------------------------------------------ */
#define SECSTORE_SIZE 4096
static uint8_t secure_store[SECSTORE_SIZE];

static uint64_t secure_store_write(uint64_t ns_ptr, uint64_t len)
{
    if (len > SECSTORE_SIZE) return SMC_INSUFFICIENT_SPACE;
    if (!is_nonsecure_ptr(ns_ptr, len)) return SMC_ACCESS_DENIED;

    fw_memcpy(secure_store, (void *)(uintptr_t)ns_ptr, (unsigned long)len);
    return SMC_OK;
}

static uint64_t secure_store_read(uint64_t ns_ptr, uint64_t len)
{
    if (len > SECSTORE_SIZE) return SMC_INSUFFICIENT_SPACE;
    if (!is_nonsecure_ptr(ns_ptr, len)) return SMC_ACCESS_DENIED;

    fw_memcpy((void *)(uintptr_t)ns_ptr, secure_store, (unsigned long)len);
    return SMC_OK;
}

/* ------------------------------------------------------------------------
 * Key store + demo crypto (XOR)
 * ------------------------------------------------------------------------ */
#define MAX_KEYS 8
#define KEY_SIZE 32
static uint8_t key_store[MAX_KEYS][KEY_SIZE];
static uint8_t key_len[MAX_KEYS];

static uint64_t import_key(uint64_t key_id, uint64_t src_ptr, uint64_t len)
{
    if (key_id >= MAX_KEYS) return SMC_INVALID_PARAM;
    if (len == 0 || len > KEY_SIZE) return SMC_INVALID_PARAM;
    if (!is_nonsecure_ptr(src_ptr, len)) return SMC_ACCESS_DENIED;

    fw_memcpy(key_store[key_id], (void *)(uintptr_t)src_ptr, (unsigned long)len);
    key_len[key_id] = (uint8_t)len;
    return SMC_OK;
}

/* XOR in-place crypto (demo only, replace with real AES/GCM) */
static uint64_t demo_crypto_xor(uint64_t ptr, uint64_t len, uint64_t key_id)
{
    if (key_id >= MAX_KEYS) return SMC_INVALID_PARAM;
    if (key_len[key_id] == 0) return SMC_INVALID_PARAM;
    if (!is_nonsecure_ptr(ptr, len)) return SMC_ACCESS_DENIED;
    if (len == 0) return SMC_INVALID_PARAM;

    uint8_t *buf = (uint8_t *)(uintptr_t)ptr;
    uint8_t *k   = key_store[key_id];
    uint64_t klen = key_len[key_id];

    for (uint64_t i = 0; i < len; i++)
        buf[i] ^= k[i % klen];

    return SMC_OK;
}

/* ------------------------------------------------------------------------
 * PSCI-like stubs
 * ------------------------------------------------------------------------ */
static uint64_t handle_cpu_on(uint64_t cpu, uint64_t entry_phys) { return SMC_NOT_SUPPORTED; }
static uint64_t handle_cpu_off(void) { return SMC_NOT_SUPPORTED; }
static uint64_t handle_system_reset(void) { return SMC_NOT_SUPPORTED; }

/* ------------------------------------------------------------------------
 * Main SMC dispatcher
 * saved_regs[0..7] = x0..x7
 * ------------------------------------------------------------------------ */
uint64_t smc_dispatch_c(uint64_t *saved_regs)
{
    uint64_t fid = saved_regs[0];
    uint64_t a1  = saved_regs[1];
    uint64_t a2  = saved_regs[2];
    uint64_t a3  = saved_regs[3];

    uint64_t ret = SMC_OK;

    switch (fid) {
        case SMC_FID_PING:
            saved_regs[0] = 0xBADC0FFEE0DDF00DULL; // magic pong
            saved_regs[1] = 0;
            saved_regs[2] = 0;
            saved_regs[3] = 0;
            return 0;

        case SMC_FID_GET_VERSION:
            saved_regs[0] = ((uint64_t)BL31_SVC_VER_MAJOR << 16) |
                             (uint64_t)BL31_SVC_VER_MINOR;
            return 0;

        case SMC_FID_SECSTORE_WRITE:
            ret = secure_store_write(a1, a2);
            saved_regs[0] = ret;
            return 0;

        case SMC_FID_SECSTORE_READ:
            ret = secure_store_read(a1, a2);
            saved_regs[0] = ret;
            return 0;

        case SMC_FID_KEY_IMPORT:
            ret = import_key(a1, a2, a3);
            saved_regs[0] = ret;
            return 0;

        case SMC_FID_CRYPTO_ENCRYPT:
        case SMC_FID_CRYPTO_DECRYPT:
            ret = demo_crypto_xor(a1, a2, a3);
            saved_regs[0] = ret;
            return 0;

        case SMC_FID_CPU_ON:
            ret = handle_cpu_on(a1, a2);
            saved_regs[0] = ret;
            return 0;

        case SMC_FID_CPU_OFF:
            ret = handle_cpu_off();
            saved_regs[0] = ret;
            return 0;

        case SMC_FID_SYSTEM_RESET:
            ret = handle_system_reset();
            saved_regs[0] = ret;
            return 0;

        default:
            saved_regs[0] = SMC_NOT_SUPPORTED;
            saved_regs[1] = 0;
            saved_regs[2] = 0;
            saved_regs[3] = 0;
            return 0;
    }
}