# .bash_profile

# Get the aliases and functions
[ -f $HOME/.bashrc ] && . $HOME/.bashrc

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
# ВАЖНО: PipeWire/WirePlumber здесь НЕ запускаем.
# Они стартуют один раз за сессию из niri:
#   spawn-at-startup "@HOME@/.local/bin/start-session-audio"
# (это user-runit сервисы в ~/.config/sv, с автоперезапуском).
# Раньше здесь были строки "pipewire &" и "wireplumber &" — они запускались
# при каждом логин-шелле и создавали дубликаты (5 wireplumber, висящий pactl).
# Автозапуск Niri на tty1
if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
    exec dbus-run-session niri --session > ${HOME}/.niri.log 2>&1
fi
export PATH="$HOME/.npm-global/bin:$PATH"
