# .bashrc

# ── pyenv ────────────────────────────────────────────────────────────────
# ~/.pyenv установлен вручную (pyenv-installer), пакета в Void нет.
# Строки инициализации когда-то пропали из этого файла — возвращаем.
# PATH выставляем до проверки интерактивности: если .bashrc подключают
# из неинтерактивного контекста (например .bash_profile при старте сессии),
# pyenv и шимы всё равно попадут в окружение. Проверка на дубль — чтобы
# повторный вход в шелл не удлинял PATH.
export PYENV_ROOT="$HOME/.pyenv"
case ":$PATH:" in
    *":$PYENV_ROOT/bin:"*) ;;
    *) export PATH="$PYENV_ROOT/bin:$PATH" ;;
esac

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
PS1='[\u@\h \W]\$ '
export PATH=$HOME/.local/bin:$PATH
export EDITOR=nano
export VISUAL=nano
if ! pgrep -u "$USER" ssh-agent > /dev/null; then eval "$(ssh-agent -s)"; fi
export PATH="@HOME@/.npm-global/bin:$PATH"

# ── Автодополнение по Tab ─────────────────────────────────────────────────
# bash сам по себе умеет дополнять только имена файлов. Команды вроде
# `git bran<Tab> → git branch` работают через пакет bash-completion:
# он подгружает /usr/share/bash-completion/completions/* (git, ssh, tar,
# xbps-install, mount, ...). В Void автозагрузки нет — подключаем здесь.
if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
fi

# Удобства дополнения:
#   show-all-if-ambiguous — сразу показывать список, а не заставлять жать Tab дважды
#   completion-ignore-case — `git BRA<Tab>` тоже сработает
#   colored-stats          — файлы раскрашены как в ls
#   mark-directories       — каталоги с завершающим слэшем
bind 'set show-all-if-ambiguous on' 2>/dev/null
bind 'set completion-ignore-case on' 2>/dev/null
bind 'set colored-stats on' 2>/dev/null
bind 'set mark-directories on' 2>/dev/null
bind 'set mark-symlinked-directories on' 2>/dev/null

# ── Инициализация pyenv (только для интерактивных шеллов) ─────────────────
# `pyenv init -` добавляет каталог шимов в PATH и включает переключение
# версии по .python-version; virtualenv-init — автоактивация окружений
# (плагин pyenv-virtualenv установлен).
if command -v pyenv >/dev/null 2>&1; then
    case ":$PATH:" in
        *":$PYENV_ROOT/shims:"*) ;;   # уже инициализирован (вложенный шелл)
        *)
            eval "$(pyenv init - bash)"
            eval "$(pyenv virtualenv-init - bash)"
            ;;
    esac
fi

