# RSS Quick - Distribution Guide

This guide explains how to create and distribute standalone versions of RSS Quick that don't require .NET to be installed on users' machines.

## Quick Start

**To create a distribution package:**
```bash
distribute.cmd
```

This creates a complete, ready-to-distribute package in the `dist/` folder.

## Distribution Methods

### Method 1: Simple Distribution Script (Recommended)

**Command:** `distribute.cmd`

**What it creates:**
- `dist/RSSQuick.exe` - Standalone executable (no .NET required)
- `dist/Run-RSSQuick.cmd` - Convenient launcher for users
- `dist/RSS.opml` - Sample RSS feeds
- `dist/README.md` - Full documentation
- `dist/DISTRIBUTION-README.txt` - Simple user instructions

**Features:**
- ✅ Single-file executable (everything bundled)
- ✅ Trimmed for smaller size
- ✅ No .NET required on user machines
- ✅ Complete user package with instructions
- ✅ Automatic testing and folder opening options

### Method 2: Advanced Build Script

**Command:** `build.cmd publish`

**What it creates:**
- `bin/Release/net8.0-windows/win-x64/publish/RSSQuick.exe`
- Standalone executable only (no additional files)

### Method 3: Manual dotnet Command

**Command:**
```bash
dotnet publish RSSReaderWPF.csproj --configuration Release --runtime win-x64 --self-contained true /p:PublishSingleFile=true /p:PublishTrimmed=true
```

## Distribution Package Contents

When you run `distribute.cmd`, you get a complete package in the `dist/` folder:

```
dist/
├── RSSQuick.exe              # Main application (standalone)
├── Run-RSSQuick.cmd          # Launcher script for users
├── RSS.opml                  # Sample RSS feeds to import
├── README.md                 # Full documentation
└── DISTRIBUTION-README.txt   # Simple user instructions
```

## For End Users (Distribution Instructions)

### System Requirements
- **Windows 10 or Windows 11**
- **No .NET installation required**
- **Internet connection** for RSS feed fetching
- **Default web browser** for opening articles

### How to Run
1. **Extract** the distribution package to any folder
2. **Double-click** `RSSQuick.exe` OR
3. **Double-click** `Run-RSSQuick.cmd` (convenient launcher)

### Getting Started
1. **Launch** the application
2. **Import feeds**: Click "Import OPML File" → Select `RSS.opml`
3. **Navigate**: Use Tab to move between panels, arrows within panels
4. **Read articles**: Select feed → Select headline → Press Enter or Alt+B

## Distribution Workflow

### For Developers

1. **Development**:
   ```bash
   run.cmd                    # Quick test
   build.cmd debug           # Debug build
   ```

2. **Testing**:
   ```bash
   build.cmd release         # Release build and test
   ```

3. **Distribution**:
   ```bash
   distribute.cmd            # Create distribution package
   ```

4. **Share**:
   - Zip the `dist/` folder
   - Upload to GitHub releases, website, etc.
   - Users extract and run `RSSQuick.exe`

### Quality Checklist

Before distributing, verify:
- ✅ Application starts without errors
- ✅ OPML import works (`RSS.opml` loads correctly)
- ✅ Feed selection loads headlines
- ✅ Headlines open in browser (Enter or Alt+B)
- ✅ Keyboard navigation works (Tab, arrows)
- ✅ Accessibility features function properly

## File Size Optimization

The `distribute.cmd` script uses these optimizations:

- **PublishSingleFile=true**: Bundles everything into one executable
- **PublishTrimmed=true**: Removes unused .NET code
- **TrimMode=partial**: Safer trimming (preserves WPF requirements)

**Typical file sizes:**
- Debug build: ~200+ MB (with .NET runtime)
- Release trimmed: ~50-80 MB (standalone)
- Original source: <1 MB

## Troubleshooting Distribution

### Build Issues

**"SDK not found"**:
- Ensure .NET 8.0 SDK is installed: `dotnet --version`

**"Build failed"**:
- Check error messages
- Try: `dotnet clean && dotnet restore && dotnet build`

**"Publish failed"**:
- Verify Windows 10/11 target
- Check disk space (needs ~500MB during build)

### Runtime Issues

**"Application won't start on user machine"**:
- Verify Windows 10/11 compatibility
- Ensure complete `dist/` folder was copied
- Check antivirus isn't blocking executable

**"Feeds won't load"**:
- Verify internet connection
- Test with included `RSS.opml` file
- Check firewall settings

## Advanced Distribution Options

### Custom OPML Files

Replace `RSS.opml` with your own feed collection:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <head><title>Custom Feeds</title></head>
  <body>
    <outline text="News" title="News">
      <outline text="Your Feed" title="Your Feed" 
               type="rss" xmlUrl="https://example.com/feed.xml"/>
    </outline>
  </body>
</opml>
```

### Branding Customization

To customize for specific organizations:
1. Modify the application title in `MainWindow.xaml`
2. Replace `RSS.opml` with organization-specific feeds
3. Update `DISTRIBUTION-README.txt` with custom instructions
4. Rebuild with `distribute.cmd`

### Automated Distribution

For CI/CD pipelines:
```bash
# Build distribution without prompts
distribute.cmd < nul

# Copy to distribution server
robocopy dist/ \\server\releases\rssquick\ /E
```

## Support and Updates

### For Users
- **Issues**: Check `DISTRIBUTION-README.txt` in package
- **Updates**: Download new distribution package
- **Source**: https://github.com/kellylford/rssquick

### For Developers
- **Development**: Use `run.cmd` and `build.cmd`
- **Distribution**: Use `distribute.cmd`
- **Documentation**: This file and `README.md`

---

**RSS Quick Distribution Guide v1.0**  
*Created for efficient, accessible RSS reading on Windows*
