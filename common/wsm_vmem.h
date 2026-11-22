#pragma once

#include <cstdint>
#include <cstddef>

#if defined(_WIN32)
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0602
#endif
#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <memoryapi.h>

typedef struct _WIN32_MEMORY_RANGE_ENTRY_WSM {
    PVOID  VirtualAddress;
    SIZE_T NumberOfBytes;
} WIN32_MEMORY_RANGE_ENTRY_WSM;

typedef BOOL (WINAPI *PFN_PrefetchVirtualMemory)(
    HANDLE hProcess,
    ULONG_PTR NumberOfEntries,
    WIN32_MEMORY_RANGE_ENTRY_WSM * VirtualAddresses,
    ULONG Flags
);
#else
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#endif

// Atomic sparse memory page size specified in WSM architecture (4 KB)
#define WSM_VMEM_PAGE_SIZE 4096

struct wsm_vmem_mapped_file {
    void * addr;
    size_t size;
#if defined(_WIN32)
    HANDLE hFile;
    HANDLE hMapping;
#else
    int fd;
#endif
};

// 1. File-backed sparse mapping in NVMe (Section 5 Sparse Holographic Memory)
static inline bool wsm_vmem_map_file(const char * path, size_t size, bool read_only, wsm_vmem_mapped_file * out_map) {
    if (!path || !out_map) return false;
    out_map->addr = nullptr;
    out_map->size = size;

#if defined(_WIN32)
    DWORD desired_access = read_only ? GENERIC_READ : (GENERIC_READ | GENERIC_WRITE);
    DWORD share_mode     = FILE_SHARE_READ;
    DWORD creation_disp  = OPEN_EXISTING;
    DWORD protect_flags  = read_only ? PAGE_READONLY : PAGE_READWRITE;
    DWORD map_access     = read_only ? FILE_MAP_READ : FILE_MAP_ALL_ACCESS;

    out_map->hFile = CreateFileA(path, desired_access, share_mode, NULL, creation_disp, FILE_ATTRIBUTE_NORMAL, NULL);
    if (out_map->hFile == INVALID_HANDLE_VALUE) {
        return false;
    }

    if (size == 0) {
        LARGE_INTEGER li;
        if (GetFileSizeEx(out_map->hFile, &li)) {
            out_map->size = static_cast<size_t>(li.QuadPart);
        }
    }

    out_map->hMapping = CreateFileMappingA(out_map->hFile, NULL, protect_flags, 0, 0, NULL);
    if (out_map->hMapping == NULL) {
        CloseHandle(out_map->hFile);
        out_map->hFile = INVALID_HANDLE_VALUE;
        return false;
    }

    out_map->addr = MapViewOfFile(out_map->hMapping, map_access, 0, 0, out_map->size);
    if (out_map->addr == NULL) {
        CloseHandle(out_map->hMapping);
        CloseHandle(out_map->hFile);
        out_map->hMapping = NULL;
        out_map->hFile = INVALID_HANDLE_VALUE;
        return false;
    }
    return true;
#else
    int flags = read_only ? O_RDONLY : O_RDWR;
    out_map->fd = open(path, flags);
    if (out_map->fd < 0) return false;

    if (size == 0) {
        struct stat st;
        if (fstat(out_map->fd, &st) == 0) {
            out_map->size = static_cast<size_t>(st.st_size);
        }
    }

    int prot = read_only ? PROT_READ : (PROT_READ | PROT_WRITE);
    out_map->addr = mmap(NULL, out_map->size, prot, MAP_SHARED, out_map->fd, 0);
    if (out_map->addr == MAP_FAILED) {
        close(out_map->fd);
        out_map->fd = -1;
        out_map->addr = nullptr;
        return false;
    }
    return true;
#endif
}

// Unmap file-backed NVMe region
static inline void wsm_vmem_unmap_file(wsm_vmem_mapped_file * map) {
    if (!map || !map->addr) return;
#if defined(_WIN32)
    UnmapViewOfFile(map->addr);
    if (map->hMapping) CloseHandle(map->hMapping);
    if (map->hFile != INVALID_HANDLE_VALUE) CloseHandle(map->hFile);
    map->addr = nullptr;
    map->hMapping = NULL;
    map->hFile = INVALID_HANDLE_VALUE;
#else
    munmap(map->addr, map->size);
    if (map->fd >= 0) close(map->fd);
    map->addr = nullptr;
    map->fd = -1;
#endif
}

// 2. Anonymous virtual address reservation for volatile state buffers
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

// Paged Prefetch: Pushes 4 KB pages into active physical RAM
// Guaranteed 4 KB alignment enforcement for Win32 and POSIX
static inline bool wsm_vmem_prefetch(void * addr, size_t size) {
    if (!addr || size == 0) return false;
    uintptr_t uaddr = reinterpret_cast<uintptr_t>(addr);
    uintptr_t aligned_addr = uaddr & ~(static_cast<uintptr_t>(WSM_VMEM_PAGE_SIZE - 1));
    size_t aligned_size = ((uaddr + size + WSM_VMEM_PAGE_SIZE - 1) & ~(static_cast<uintptr_t>(WSM_VMEM_PAGE_SIZE - 1))) - aligned_addr;

#if defined(_WIN32)
    WIN32_MEMORY_RANGE_ENTRY_WSM entry;
    entry.VirtualAddress = reinterpret_cast<void *>(aligned_addr);
    entry.NumberOfBytes  = aligned_size;

    static PFN_PrefetchVirtualMemory pfnPrefetch = []() -> PFN_PrefetchVirtualMemory {
        HMODULE hKernel = GetModuleHandleA("kernel32.dll");
        if (!hKernel) return nullptr;
        return reinterpret_cast<PFN_PrefetchVirtualMemory>(GetProcAddress(hKernel, "PrefetchVirtualMemory"));
    }();

    if (pfnPrefetch) {
        return pfnPrefetch(GetCurrentProcess(), 1, &entry, 0) != 0;
    }
    return false;
#else
    return madvise(reinterpret_cast<void *>(aligned_addr), aligned_size, MADV_WILLNEED) == 0;
#endif
}

// Paged Evict / Decommit: Releases physical RAM back to system without losing address reservation
static inline bool wsm_vmem_evict(void * addr, size_t size) {
    if (!addr || size == 0) return false;
    uintptr_t uaddr = reinterpret_cast<uintptr_t>(addr);
    uintptr_t aligned_addr = uaddr & ~(static_cast<uintptr_t>(WSM_VMEM_PAGE_SIZE - 1));
    size_t aligned_size = ((uaddr + size + WSM_VMEM_PAGE_SIZE - 1) & ~(static_cast<uintptr_t>(WSM_VMEM_PAGE_SIZE - 1))) - aligned_addr;

#if defined(_WIN32)
    return VirtualFree(reinterpret_cast<void *>(aligned_addr), aligned_size, MEM_DECOMMIT) != 0;
#else
    #if defined(MADV_DONTNEED)
    return madvise(reinterpret_cast<void *>(aligned_addr), aligned_size, MADV_DONTNEED) == 0;
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
