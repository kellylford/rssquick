# RSS Quick - How to Build and Distribute

This guide shows you how to build RSS Quick for distribution using File Explorer (double-clicking .cmd files).

## 🖱️ Easy File Explorer Usage (Just Double-Click!)

### For Self-Contained Distribution (162 MB, works everywhere):
**Double-click:** `distribute.cmd`
- Creates `dist/` folder with everything included
- Users don't need to install .NET
- Larger download but zero user setup

### For Small Distribution (400 KB, requires .NET):
**Double-click:** `distribute-small.cmd`  
- Creates `dist-small/` folder for your current architecture
- Much smaller download
- Users need .NET 8.0 Runtime installed first

### For Multi-Platform Small Distribution (750 KB, x64 + ARM64):
**Double-click:** `build-multi-small.cmd`
- Creates `dist-multi-small/` with both x64 and ARM64 versions
- Small download with maximum compatibility
- Users choose the right folder for their processor

## 📁 What Gets Created

### Self-Contained (`distribute.cmd`):
```
dist/
├── RSSQuick.exe (and 256 other files)
├── RSS.opml
├── README.md
└── Run-RSSQuick.cmd
```
**Size:** ~162 MB  
**User needs:** Nothing! Just extract and run

### Small Single-Platform (`distribute-small.cmd`):
```
dist-small/
├── RSSQuick.exe (and 5 other files)
├── RSS.opml
├── README.md
└── Run-RSSQuick.cmd
```
**Size:** ~400 KB  
**User needs:** .NET 8.0 Runtime for their architecture

### Small Multi-Platform (`build-multi-small.cmd`):
```
dist-multi-small/
├── win-x64/
│   ├── RSSQuick.exe (and 5 other files)
│   ├── RSS.opml
│   └── README.md
├── win-arm64/
│   ├── RSSQuick.exe (and 5 other files)  
│   ├── RSS.opml
│   └── README.md
└── README.txt (instructions)
```
**Size:** ~750 KB  
**User needs:** .NET 8.0 Runtime, choose right folder

## 🎯 Which Should You Use?

### For General Public Distribution:
**Recommended:** `distribute.cmd` (self-contained)
- **Pros:** Works for everyone, no technical knowledge needed
- **Cons:** Large download
- **Best for:** Non-technical users, corporate environments

### For Technical Users:
**Recommended:** `build-multi-small.cmd` (multi-platform small)
- **Pros:** Tiny download, works on both Intel and ARM
- **Cons:** Users must install .NET first
- **Best for:** Developers, tech-savvy users, GitHub releases

### For Your Own Testing:
**Recommended:** `distribute-small.cmd` (single platform)
- **Pros:** Quick to build, small size
- **Cons:** Only works on your architecture type
- **Best for:** Personal testing, same-architecture sharing

## 🖱️ Step-by-Step for File Explorer Users

### Step 1: Open File Explorer
Navigate to your RSS Quick project folder

### Step 2: Choose Your Script
- For everyone: Double-click `distribute.cmd`
- For tech users: Double-click `build-multi-small.cmd`  
- For testing: Double-click `distribute-small.cmd`

### Step 3: Wait for Build
The script will:
- Clean previous builds
- Build the application
- Create distribution folder(s)
- Show you the results

### Step 4: Check Results
The script will create a folder like:
- `dist/` (self-contained)
- `dist-small/` (small single)
- `dist-multi-small/` (small multi)

### Step 5: Distribute
- Zip the entire folder
- Upload to GitHub, email, cloud storage, etc.
- Users extract and run `RSSQuick.exe`

## ⚡ Quick Comparison

| Script | Click & Go | Size | User Setup | Best For |
|--------|------------|------|------------|----------|
| `distribute.cmd` | ✅ | 162 MB | None | Everyone |
| `distribute-small.cmd` | ✅ | 400 KB | Install .NET | Your platform |
| `build-multi-small.cmd` | ✅ | 750 KB | Install .NET | Public release |

## 🛠️ Troubleshooting

### "Build failed" errors:
- Make sure you have .NET 8.0 SDK installed
- Try: `dotnet --version` in Command Prompt
- Should show version 8.x.x

### Script won't run:
- Right-click the .cmd file → "Run as administrator"
- Or open Command Prompt in the folder and type the filename

### Can't find the script:
- Make sure you're in the RSS Quick project folder
- Look for files ending in `.cmd`

## 💡 Pro Tips

1. **Test first**: Use `distribute-small.cmd` to test on your machine
2. **Check sizes**: The script shows file sizes when done
3. **Open folder**: Most scripts ask if you want to open the result folder
4. **Documentation**: All distributions include README files for users

All the scripts are designed to be user-friendly with clear progress messages and automatic folder opening when complete!
