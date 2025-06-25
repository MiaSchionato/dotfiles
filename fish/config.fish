function fish_greeting
end
# ssh-agent


if not set -q SSH_AUTH_SOCK
  eval (ssh-agent -c)
end
