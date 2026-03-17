# RLM-Mem Troubleshooting Guide

Common issues and solutions for RLM-Mem installation and usage.

## 🔍 Quick Diagnostics

Run these checks first:

```bash
# 1. Check Python version
python3 --version  # macOS/Linux
python --version   # Windows

# 2. Check RLM script exists
ls ~/.claude/rlm_scripts/rlm_repl.py  # macOS/Linux
dir %USERPROFILE%\.claude\rlm_scripts\rlm_repl.py  # Windows

# 3. Test RLM script
python3 ~/.claude/rlm_scripts/rlm_repl.py --help

# 4. Check commands installed
ls ~/.claude/commands/rlm-mem/  # macOS/Linux
dir %USERPROFILE%\.claude\commands\rlm-mem\  # Windows
```

---

## 🐛 Installation Issues

### Issue: Python not found

**Symptoms:**
```
command not found: python3
# or
'python3' is not recognized as an internal or external command
```

**Solutions:**

**macOS:**
```bash
# Install Python via Homebrew
brew install python3

# Or download from python.org
# Verify installation
python3 --version
```

**Windows:**
```powershell
# Download from python.org and install
# Add Python to PATH during installation
# Verify:
python --version
# Or:
py -3 --version

# If still not found, add to PATH:
# 1. Search "Environment Variables" in Start menu
# 2. Edit PATH
# 3. Add: C:\Users\YourName\AppData\Local\Programs\Python\Python3xx\
```

**Linux:**
```bash
# Ubuntu/Debian
sudo apt install python3 python3-pip

# Fedora/RHEL
sudo dnf install python3 python3-pip

# Verify
python3 --version
```

---

### Issue: Permission denied on rlm_repl.py

**Symptoms:**
```
Permission denied: ~/.claude/rlm_scripts/rlm_repl.py
```

**Solution (macOS/Linux):**
```bash
chmod +x ~/.claude/rlm_scripts/rlm_repl.py
```

**Solution (Windows):**
Usually not needed. If issues persist:
```powershell
# Run as administrator
# Or check file properties → Security → Allow execution
```

---

### Issue: Commands not appearing in Claude Code

**Symptoms:**
- Type `/rlm-mem:` and nothing appears
- Commands don't autocomplete

**Solutions:**

1. **Verify files copied correctly:**
```bash
# macOS/Linux
ls -R ~/.claude/commands/rlm-mem/

# Windows
dir /S %USERPROFILE%\.claude\commands\rlm-mem\
```

Should show all command .md files.

2. **Restart Claude Code:**
```bash
# Exit Claude Code completely
# Start again
claude
```

3. **Check command file format:**
```bash
# Files must end in .md
# Files must be in correct directory structure
# Example: ~/.claude/commands/rlm-mem/discover/init.md
```

4. **Check Claude Code version:**
```bash
claude --version
# Update if needed
```

---

### Issue: Directory already exists error

**Symptoms:**
```
mkdir: cannot create directory '~/.claude/commands/rlm-mem': File exists
```

**Solution:**
```bash
# Backup existing if needed
mv ~/.claude/commands/rlm-mem ~/.claude/commands/rlm-mem.backup

# Then re-run installation
cp -r .claude/commands/rlm-mem ~/.claude/commands/
```

---

## 🚀 Runtime Issues

### Issue: RLM initialization fails

**Symptoms:**
```
/rlm-mem:discover:init
Error: No such file or directory
```

**Solutions:**

1. **Check you're in a git repository:**
```bash
git status
# If not a git repo:
git init
```

2. **Check Python path in commands:**

**macOS/Linux:**
Commands use `python3 ~/.claude/rlm_scripts/rlm_repl.py`

**Windows:**
You may need to edit commands to use:
- `python %USERPROFILE%\.claude\rlm_scripts\rlm_repl.py`
- Or: `py -3 %USERPROFILE%\.claude\rlm_scripts\rlm_repl.py`

3. **Test REPL script directly:**
```bash
python3 ~/.claude/rlm_scripts/rlm_repl.py init-repo .
```

---

### Issue: exec command fails with argument errors

**Symptoms:**
```
rlm_repl: error: unrecognized arguments:
# Multiple lines of code shown as separate arguments
```

**Cause:**
Multiline code passed incorrectly.

**Solution:**

Always use `-c` flag for single-line OR heredoc for multiline:

**Single-line:**
```bash
python3 ~/.claude/rlm_scripts/rlm_repl.py exec -c "print(repo_index['total_files'])"
```

**Multi-line (use heredoc):**
```bash
python3 ~/.claude/rlm_scripts/rlm_repl.py exec <<'PY'
total = repo_index['total_files']
print(f"Total: {total}")
PY
```

**WRONG (don't do this):**
```bash
# ❌ This will fail
python3 ~/.claude/rlm_scripts/rlm_repl.py exec "print('hello')
print('world')"
```

---

### Issue: State file corrupt or missing

**Symptoms:**
```
ERROR: No state found at .claude/rlm_state/state.pkl
# or
ERROR: Corrupt state file
```

**Solutions:**

1. **Re-initialize:**
```bash
python3 ~/.claude/rlm_scripts/rlm_repl.py reset
python3 ~/.claude/rlm_scripts/rlm_repl.py init-repo .
```

2. **Check .gitignore includes state directory:**
```bash
# Add to .gitignore
echo ".claude/rlm_state/" >> .gitignore
```

3. **Verify permissions:**
```bash
# macOS/Linux
ls -la .claude/rlm_state/
# Should show read/write permissions
```

---

### Issue: Binary file errors

**Symptoms:**
```
UnicodeDecodeError: 'utf-8' codec can't decode byte
```

**Cause:**
RLM trying to read binary files as text.

**Solution:**
This should be handled automatically, but if issues persist:

1. **Check binary detection:**
Binary files should be marked `is_binary: true` in index.

2. **Add extension to BINARY_EXTENSIONS in rlm_repl.py:**
```python
BINARY_EXTENSIONS = {
    '.your_ext',  # Add your extension
    # ... existing ones
}
```

3. **Re-index:**
```bash
python3 ~/.claude/rlm_scripts/rlm_repl.py reset
python3 ~/.claude/rlm_scripts/rlm_repl.py init-repo .
```

---

### Issue: Git files not found

**Symptoms:**
```
WARNING: git not found, falling back to directory walk
# or
No files discovered
```

**Solutions:**

1. **Install git:**

**macOS:**
```bash
# Usually pre-installed
# Or install via Homebrew
brew install git
```

**Windows:**
Download from git-scm.com

**Linux:**
```bash
sudo apt install git  # Ubuntu/Debian
sudo dnf install git  # Fedora/RHEL
```

2. **Verify git works:**
```bash
git --version
git status
```

3. **If not a git repo:**
```bash
git init
```

---

## 🔌 Claude-Mem Integration Issues

### Issue: Claude-mem tools not available

**Symptoms:**
```
Tool 'mcp__plugin_claude-mem_mcp-search__search' not found
```

**Solution:**

Claude-mem is **optional**. RLM-Mem will work without it, but with reduced functionality.

To enable claude-mem:
1. Install claude-mem plugin separately
2. Configure in Claude Code settings
3. Restart Claude Code

**Working without claude-mem:**
- RLM analysis still works
- Pattern discovery still works
- Historical context features disabled

---

### Issue: Claude-mem search returns empty

**Symptoms:**
```
mcp__plugin_claude-mem_mcp-search__search returned 0 results
```

**Solutions:**

1. **Initialize project in claude-mem:**
```
/coding:discover:init
```

2. **Check claude-mem is running:**
Look for claude-mem worker process.

3. **Manually save some data:**
```
mcp__plugin_claude-mem_mcp-search__save_memory(
  text="Test observation",
  title="Test",
  project="your-project"
)
```

---

## ⚡ Performance Issues

### Issue: Initialization is very slow

**Symptoms:**
```
/rlm-mem:discover:init
# Takes 5+ minutes
```

**Causes & Solutions:**

1. **Very large repository:**
   - Normal for 10,000+ files
   - Consider excluding large directories via .gitignore

2. **Slow disk:**
   - SSD recommended
   - Check disk speed

3. **Many binary files:**
   - Add to .gitignore if not needed

**Optimization:**
```bash
# Check file count before init
git ls-files | wc -l

# Exclude large directories
echo "node_modules/" >> .gitignore
echo "vendor/" >> .gitignore
echo "build/" >> .gitignore
```

---

### Issue: Commands timeout

**Symptoms:**
```
Command execution timeout
```

**Solutions:**

1. **Increase timeout in Claude Code settings**

2. **Reduce analysis scope:**
   - Limit file search in RLM exec calls
   - Use more specific patterns

3. **Use simpler commands for quick tasks:**
   - Use `/coding:*` commands for trivial changes
   - Reserve `/rlm-mem:*` for complex features

---

## 🖥️ Platform-Specific Issues

### macOS: Gatekeeper blocking rlm_repl.py

**Symptom:**
```
"rlm_repl.py" cannot be opened because it is from an unidentified developer
```

**Solution:**
```bash
# Remove quarantine attribute
xattr -d com.apple.quarantine ~/.claude/rlm_scripts/rlm_repl.py

# Or: System Preferences → Security & Privacy → Allow
```

---

### Windows: Path length limit

**Symptom:**
```
The filename or extension is too long
```

**Solution:**
```powershell
# Enable long paths (requires admin)
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" `
  -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force

# Restart required
```

---

### Linux: Missing dependencies

**Symptom:**
```
ModuleNotFoundError: No module named 'xyz'
```

**Solution:**
```bash
# Install Python dependencies
# (rlm_repl.py is dependency-free, but check for system Python issues)

# Ubuntu/Debian
sudo apt install python3-full

# Fedora/RHEL
sudo dnf install python3-devel
```

---

## 📊 Debugging Tips

### Enable verbose output

**Check what RLM is doing:**
```bash
# Add debug prints to rlm_repl.py
# Or run with Python in debug mode
python3 -v ~/.claude/rlm_scripts/rlm_repl.py status
```

### Inspect state manually

**macOS/Linux:**
```bash
python3 -c "
import pickle
with open('.claude/rlm_state/state.pkl', 'rb') as f:
    state = pickle.load(f)
    print('Files indexed:', len(state.get('repo_index', {}).get('files', {})))
    print('Languages:', state.get('repo_index', {}).get('languages', {}).keys())
"
```

### Check git integration

```bash
# What files does git see?
git ls-files | head -20

# What files does RLM see?
python3 ~/.claude/rlm_scripts/rlm_repl.py exec -c "
for path in list(repo_index['files'].keys())[:20]:
    print(path)
"
```

---

## 🆘 Still Having Issues?

### Collect debug information:

```bash
# 1. Python version
python3 --version

# 2. Git version
git --version

# 3. Claude Code version
claude --version

# 4. OS details
uname -a  # macOS/Linux
systeminfo  # Windows

# 5. File structure
ls -R ~/.claude/ | head -50

# 6. RLM status
python3 ~/.claude/rlm_scripts/rlm_repl.py status 2>&1

# 7. Recent error logs
# Check Claude Code logs for errors
```

### Reset everything and start fresh:

```bash
# 1. Backup existing
mv ~/.claude/commands/rlm-mem ~/.claude/commands/rlm-mem.backup
mv ~/.claude/rlm_scripts ~/.claude/rlm_scripts.backup
mv ~/.claude/agents/rlm-subcall.md ~/.claude/agents/rlm-subcall.md.backup

# 2. Remove state
rm -rf .claude/rlm_state/

# 3. Re-install from scratch
cd ~/rlm-mem
# Follow installation steps in README.md

# 4. Re-initialize
claude
/rlm-mem:discover:init
```

---

## 📖 Additional Resources

- **Main README**: Installation and quick start
- **Command Docs**: `README.md` (top-level)
- **RLM Paper**: https://arxiv.org/abs/2512.24601

---

**If you've tried everything and still stuck, please file an issue with:**
1. Your OS and versions (Python, Git, Claude Code)
2. Full error message
3. Steps to reproduce
4. Debug information from above

We'll help you get it working! 🚀
