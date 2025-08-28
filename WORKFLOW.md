# RSS Quick - Complete Development & Distribution Workflow

This document outlines everything you need to know for ongoing development and distribution of RSS Quick.

## 🎯 Quick Reference - What to Use When

| Task | File to Double-Click | Output | Best For |
|------|---------------------|--------|----------|
| **Testing locally** | `run.cmd` | Builds and runs | Development |
| **Quick distribution** | `build-multi-small.cmd` | 750KB package | Public release |
| **Single platform** | `distribute-small.cmd` | 400KB package | Same architecture |
| **Maximum compatibility** | `distribute.cmd` | 162MB package | Non-technical users |

## 🛠️ Development Workflow

### Daily Development:
1. **Edit code** in VS Code or Visual Studio
2. **Test quickly**: Double-click `run.cmd`
3. **Debug**: Use `build.cmd debug` for debug mode
4. **Clean**: Use `build.cmd clean` to reset

### Before Committing:
1. **Test build**: `run.cmd` or `build.cmd release`
2. **Check for errors**: Fix any build warnings
3. **Test functionality**: Import OPML, browse feeds
4. **Commit source only**: Build outputs are ignored

## 📦 Distribution Workflow

### For GitHub Releases (Recommended):
1. **Build multi-platform**: Double-click `build-multi-small.cmd`
2. **Verify output**: Check `dist-multi-small/` folder
3. **Test both platforms**: Try both `win-x64/` and `win-arm64/` folders
4. **Create ZIP**: Zip the entire `dist-multi-small/` folder
5. **Upload to GitHub**: Create release with ZIP file

### For Enterprise/Corporate Distribution:
1. **Build self-contained**: Double-click `distribute.cmd`
2. **Test on clean machine**: Verify no .NET installation needed
3. **Create installer**: Package `dist/` folder into MSI/setup.exe
4. **Distribute**: Via corporate software center

### For Developer/Technical Users:
1. **Build small**: Double-click `distribute-small.cmd`
2. **Include .NET instructions**: Point to dotnet.microsoft.com
3. **Provide support**: Help with .NET installation if needed

## 📁 Repository Structure (What's Tracked)

### ✅ Source Files (Committed):
```
├── *.cs, *.xaml, *.csproj     # Application source code
├── *.cmd, *.sh               # Build scripts
├── *.md                      # Documentation
├── RSS.opml                  # Sample RSS feeds
├── .gitignore               # Git configuration
└── README.md                # Main documentation
```

### ❌ Build Outputs (Ignored):
```
├── bin/                     # Build outputs
├── obj/                     # Intermediate files
├── dist*/                   # Distribution packages
└── publish-test/            # Test builds
```

## 🚀 Release Process

### 1. Prepare Release:
```bash
# Ensure clean working directory
git status                   # Should show "working tree clean"

# Test current build
run.cmd                      # Verify app works

# Build distribution
build-multi-small.cmd        # Creates dist-multi-small/
```

### 2. Create GitHub Release:
1. **Go to**: https://github.com/kellylford/rssquick/releases
2. **Click**: "Create a new release"
3. **Tag**: `v1.0`, `v1.1`, etc.
4. **Title**: "RSS Quick v1.0 - Accessible RSS Reader"
5. **Description**:
   ```
   Small, accessible RSS reader for Windows 10/11.
   
   **Requirements:** .NET 8.0 Runtime
   **Download:** Choose win-x64 for Intel/AMD, win-arm64 for ARM processors
   **Size:** 750 KB total
   
   Features:
   - Screen reader optimized
   - Keyboard navigation
   - OPML import support
   - Fast and lightweight
   ```
6. **Attach**: Zip file of `dist-multi-small/`
7. **Publish release**

### 3. Update Documentation:
- Update README.md with new features
- Update version numbers if needed
- Commit and push changes

## 🔧 Build System Reference

### Build Scripts Available:

| Script | Type | Platforms | Size | User Needs | Use When |
|--------|------|-----------|------|------------|----------|
| `run.cmd` | Development | Current | N/A | .NET SDK | Daily testing |
| `build.cmd` | Development | Current | N/A | .NET SDK | Development builds |
| `distribute.cmd` | Self-contained | Auto-detect | 162MB | Nothing | Max compatibility |
| `distribute-small.cmd` | Framework-dependent | Auto-detect | 400KB | .NET Runtime | Current platform |
| `build-multi-small.cmd` | Framework-dependent | x64 + ARM64 | 750KB | .NET Runtime | **Public release** |

### Architecture Support:
- **x64**: Intel/AMD processors (most common)
- **ARM64**: Surface Pro X, ARM-based laptops
- **Auto-detection**: Scripts detect your processor type

## 📋 Troubleshooting Guide

### Build Issues:
**"SDK not found"**:
- Install .NET 8.0 SDK from Microsoft
- Restart VS Code/terminal after installation

**"Build failed"**:
- Check error messages in build output
- Try `build.cmd clean` then rebuild
- Verify all source files are saved

### Distribution Issues:
**"Package too large"**:
- Use `build-multi-small.cmd` instead of `distribute.cmd`
- Small version is 200x smaller

**"Won't run on user machine"**:
- User needs .NET 8.0 Runtime installed
- Provide download link: https://dotnet.microsoft.com/download/dotnet/8.0
- They need the Runtime, not SDK

**"Architecture mismatch"**:
- User downloaded wrong folder (x64 vs ARM64)
- Most users need win-x64
- ARM64 is for Surface Pro X and ARM laptops

## 🎯 Best Practices

### Development:
- ✅ **Test frequently**: Use `run.cmd` for quick testing
- ✅ **Clean builds**: Use `build.cmd clean` before important tests
- ✅ **Version control**: Only commit source files, not build outputs
- ✅ **Document changes**: Update README.md with new features

### Distribution:
- ✅ **Use multi-platform**: `build-multi-small.cmd` for public releases
- ✅ **Test both architectures**: Verify x64 and ARM64 versions work
- ✅ **Clear instructions**: Include README in distributions
- ✅ **Version releases**: Use semantic versioning (v1.0, v1.1, etc.)

### User Support:
- ✅ **Provide .NET links**: Include installation instructions
- ✅ **Architecture guidance**: Help users choose x64 vs ARM64
- ✅ **Test scenarios**: Verify on clean machines without .NET
- ✅ **Error handling**: Help with common runtime issues

## 📞 Support Workflow

### User Reports Issue:
1. **Determine platform**: x64 or ARM64?
2. **Check .NET**: Do they have .NET 8.0 Runtime?
3. **Verify download**: Did they use the right folder?
4. **Test locally**: Can you reproduce the issue?
5. **Fix if needed**: Update code and create new release

### Common User Issues:
- **App won't start** → Missing .NET Runtime
- **Download too large** → They got self-contained by mistake
- **Wrong architecture** → Used x64 on ARM64 or vice versa

## 🔄 Maintenance Tasks

### Monthly:
- Check for .NET updates
- Test builds on Windows Updates
- Review GitHub issues/feedback

### When .NET Updates:
- Update project to newest .NET version
- Test all build scripts
- Update documentation with new .NET version
- Create new release if needed

## 📈 Future Enhancements

### Potential Improvements:
- **Auto-updater**: Check for new versions
- **More themes**: Light/dark mode support
- **Export features**: Export to different formats
- **Plugin system**: Extensible architecture
- **Cross-platform**: Consider Avalonia for Linux/Mac

### Build System Improvements:
- **Automated testing**: Run tests before builds
- **CI/CD**: GitHub Actions for automatic builds
- **Code signing**: Sign executables for security
- **Chocolatey package**: Windows package manager support

---

**This workflow ensures reliable, professional distribution of RSS Quick while maintaining a simple development experience.**
