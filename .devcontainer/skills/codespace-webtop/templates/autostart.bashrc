# selkies-native autostart hook
# Appended to ~/.bashrc or ~/.zshrc by: selkies-native.sh autostart enable
# Guards prevent duplicate entries and double-start

# selkies-native autostart
[[ -x "$HOME/.selkies/selkies-native.sh" ]] && { "$HOME/.selkies/selkies-native.sh" start; } &>/dev/null &
