#pragma once

#include <cstdint>
#include <cstddef>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <memoryapi.h>
#else
#include <sys/mman.h>
#include <unistd.h>
#endif

// Atomic sparse memory page size specified in WSM architecture
#define WSM_VMEM_PAGE_SIZE 4096

struct wsm_vmem_region {
    void * addr;
    size_t size;
    bool is_mapped;
};

// Allocate virtual address space reservation without committing physical memory
static inline void * wsm_vmem_reserve(size_t size) {
#if defined(_WIN32)
    return VirtualAlloc(NULL, size, MEM_RESERVE, PAGE_NOACCESS);
#else
    void * addr = mmap(NULL, size, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    return (addr == MAP_FAILED) ? NULL : addr;
#endif
}

// Commit physical pages for an atomic block
static inline bool wsm_vmem_commit(void * addr, size_t size) {
#if defined(_WIN32)
    void * res = VirtualAlloc(addr, size, MEM_COMMIT, PAGE_READWRITE);
    return res != NULL;
#else
    return mprotect(addr, size, PROT_READ | PROT_WRITE) == 0;
#endif
}

// Paged Prefetch: Pushes pages into active physical RAM
// On Windows: uses PrefetchVirtualMemory (Win8 / Server 2012+)
// On POSIX: uses madvise(..., MADV_WILLNEED)
static inline bool wsm_vmem_prefetch(void * addr, size_t size) {
#if defined(_WIN32)
    WIN32_MEMORY_RANGE_ENTRY entry;
    entry.VirtualAddress = addr;
    entry.NumberOfBytes  = size;
    // PrefetchVirtualMemory is in Kernel32.lib / MinGW
    return PrefetchVirtualMemory(GetCurrentProcess(), 1, &entry, 0) != 0;
#else
    return madvise(addr, size, MADV_WILLNEED) == 0;
#endif
}

// Paged Evict / Decommit: Releases physical RAM back to system without losing address reservation
static inline bool wsm_vmem_evict(void * addr, size_t size) {
#if defined(_WIN32)
    // MEM_DECOMMIT frees physical pages while retaining reservation
    return VirtualFree(addr, size, MEM_DECOMMIT) != 0;
#else
    #if defined(MADV_DONTNEED)
    return madvise(addr, size, MADV_DONTNEED) == 0;
    #else
    return false;
    #endif
#endif
}

// Free entire virtual memory region
static inline void wsm_vmem_free(void * addr, size_t size) {
    if (!addr) return;
#if defined(_WIN32)
    (void)size;
    VirtualFree(addr, 0, MEM_RELEASE);
#else
    munmap(addr, size);
#endif
}
