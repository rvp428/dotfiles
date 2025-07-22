#!/usr/bin/env fish
#
# register‑fish.fish — safely add fish to /etc/shells and chsh to it

# 1. Locate Fish
set -l fish_path (command -v fish)
if test -z "$fish_path"
    echo "✖ Fish shell not found in your PATH." >&2
    exit 1
end
echo "✔ Found fish at: $fish_path"

# 2. Check that /etc/shells exists
if not test -f /etc/shells
    echo "✖ /etc/shells does not exist!" >&2
    exit 1
end

# 3. Add to /etc/shells if missing
if not grep -Fxq "$fish_path" /etc/shells
    echo "→ Fish is not listed in /etc/shells; adding it now."
    if test -w /etc/shells
        echo $fish_path >> /etc/shells
    else
        echo $fish_path | sudo tee -a /etc/shells >/dev/null
    end
    echo "✔ Added $fish_path to /etc/shells"
else
    echo "✔ $fish_path is already in /etc/shells"
end

# 4. Determine current login shell
if type -q getent
    set -l current_shell (getent passwd (id -un) | cut -d: -f7)
else
    set -l current_shell $SHELL
end

# 5. Change login shell if needed
if test "$current_shell" = "$fish_path"
    echo "✔ Your login shell is already fish."
else
    echo "→ Changing your login shell to fish..."
    chsh -s $fish_path
    echo "✔ Login shell changed to $fish_path"
end

echo
echo "All done! Log out and back in (or restart your session) to start using Fish by default."
