# RSS Quick - Multi-Platform Build Guide

This guide shows you how to build RSS Quick for multiple platforms when using the small (framework-dependent) distribution option.

## Quick Multi-Platform Build

**Use the automated script:**
```bash
distribute-multi-small.cmd
```

**Creates distributions for:**
- `win-x64` - Intel/AMD processors (most common)
- `win-arm64` - ARM64 processors (Surface, newer laptops)

## Manual Multi-Platform Builds

### For Intel/AMD Systems (x64)
```bash
dotnet publish RSSReaderWPF.csproj --configuration Release --runtime win-x64 --self-contained false --output "dist-x64"
```

### For ARM64 Systems  
```bash
dotnet publish RSSReaderWPF.csproj --configuration Release --runtime win-arm64 --self-contained false --output "dist-arm64"
```

### For 32-bit Systems (rare)
```bash
dotnet publish RSSReaderWPF.csproj --configuration Release --runtime win-x86 --self-contained false --output "dist-x86"
```

## Platform Identification Guide

### How Users Know Which Version They Need:

| System Type | Architecture | Use This Version |
|-------------|--------------|------------------|
| **Most desktop PCs** | x64 | `win-x64` |
| **Most laptops (Intel/AMD)** | x64 | `win-x64` |
| **Surface Pro X, Surface Laptop (ARM)** | ARM64 | `win-arm64` |
| **M1/M2 Mac with Windows** | ARM64 | `win-arm64` |
| **Very old computers** | x86 | `win-x86` |

### User Detection Methods:

**Method 1: Try x64 First**
- Most users have x64 systems
- If it works, they're done
- If .NET prompt appears, try ARM64 version

**Method 2: Check System Info**
- Windows Key + Pause → System type
- "x64-based processor" = use win-x64
- "ARM64-based processor" = use win-arm64

**Method 3: Command Line**
```cmd
echo %PROCESSOR_ARCHITECTURE%
```
- `AMD64` = win-x64
- `ARM64` = win-arm64

## Distribution Strategy Options

### Option 1: Separate Downloads
Create separate ZIP files:
- `RSSQuick-Small-x64.zip` (~325 KB)
- `RSSQuick-Small-ARM64.zip` (~325 KB)

**Pros:** Smaller individual downloads
**Cons:** Users must choose correctly

### Option 2: Combined Package (Recommended)
One ZIP with both architectures:
- `RSSQuick-Small-Multi.zip` (~650 KB)
- Contains folders: `win-x64/` and `win-arm64/`
- Includes instructions on which to use

**Pros:** Foolproof, one download
**Cons:** Slightly larger (but still tiny)

### Option 3: Auto-Detecting Installer
Create a batch script that:
1. Detects user's architecture
2. Downloads correct version
3. Installs automatically

## .NET Runtime Requirements by Platform

### All platforms need .NET 8.0 Runtime:

| Platform | .NET Runtime Download |
|----------|----------------------|
| **win-x64** | [.NET 8.0 Runtime x64](https://dotnet.microsoft.com/download/dotnet/8.0) |
| **win-arm64** | [.NET 8.0 Runtime ARM64](https://dotnet.microsoft.com/download/dotnet/8.0) |
| **win-x86** | [.NET 8.0 Runtime x86](https://dotnet.microsoft.com/download/dotnet/8.0) |

**Important:** Users need the **Runtime**, not the SDK. The SDK is much larger and includes development tools.

## Build Script Comparison

| Script | Platforms | Output | Best For |
|--------|-----------|--------|----------|
| `distribute-small.cmd` | Auto-detect current | One platform | Testing on your machine |
| `distribute-multi-small.cmd` | x64 + ARM64 | Multi-platform | Public distribution |
| Manual commands | Any specific | Custom | Specific needs |

## File Size Expectations

### Small (Framework-Dependent) Distribution:
- **Per platform:** ~325 KB (6 files)
- **Multi-platform:** ~650 KB total
- **User needs:** .NET 8.0 Runtime (~55 MB, one-time install)

### Combined User Experience:
- **Download:** 650 KB (your app)
- **Install .NET:** 55 MB (Microsoft, one-time)
- **Total:** ~56 MB vs 162 MB for self-contained

## Troubleshooting Platform Issues

### "Application won't start" Errors:

**Wrong architecture:**
- x64 app on ARM64 system → Download prompt → Use ARM64 version
- ARM64 app on x64 system → Error → Use x64 version

**Missing .NET:**
- Prompt to download .NET → Install correct architecture
- Use the auto-detecting installer script

**Mixed architectures:**
- Some users have both x64 and ARM64 .NET → Either version works
- Recommend x64 for consistency

## Best Practices for Public Distribution

### Recommended Approach:
1. **Use `distribute-multi-small.cmd`** for public releases
2. **Create one ZIP** with both architectures
3. **Include clear instructions** on platform selection
4. **Provide .NET installer helper** script
5. **Test on both architectures** before release

### User Instructions Template:
```
RSS Quick - Choose Your Version

1. Try the win-x64/ folder first (works for most people)
2. If Windows asks to download .NET, run Install-DotNet-Runtime.cmd
3. If still having issues, try win-arm64/ folder
4. Need help? Check README-CHOOSE-YOUR-PLATFORM.txt
```

This approach gives you maximum compatibility with minimal user confusion while keeping download sizes small!
