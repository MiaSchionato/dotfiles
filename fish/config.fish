function fish_greeting
end

# Inicia o ssh-agent via keychain, mas apenas se não estiver em execução
if not set -q SSH_AUTH_SOCK
    keychain --quiet --eval id_ed25519_sk | while read -l line
        if string match -q "SSH_AUTH_SOCK=*" $line
            set -gx SSH_AUTH_SOCK (echo $line | sed 's/SSH_AUTH_SOCK=\(.*\);.*/\1/')
        else if string match -q "SSH_AGENT_PID=*" $line
            set -gx SSH_AGENT_PID (echo $line | sed 's/SSH_AGENT_PID=\(.*\);.*/\1/')
        end
    end
end

set -x TERM "xterm-256color"
zoxide init fish | source

set -x EDITOR 'vim'
set -x XCURSOR_PATH "$XCURSOR_PATH:~/.icons:~/.local/share/icons"
set -x LIBVIRT_DEFAULT_URI "qemu:///system"
set -x QT_QPA_PLATFORM "xcb"
set -gx LC_ALL "en_US.UTF-8"
