#!/bin/zsh
# Salve este script em um local como ~/.config/hypr/scripts/lock_and_run.sh

# 1. Executa o hyprlock e espera ele terminar.
# O script ficará pausado nesta linha até que a tela seja desbloqueada ou o hyprlock seja cancelado.
hyprlock

# 2. Verifica o código de saída do comando anterior ($?).
# Para o hyprlock, um código de saída 0 significa que o desbloqueio foi bem-sucedido.
if [ $? -eq 0 ]; then
    # 3. Se o desbloqueio foi bem-sucedido, execute o script desejado.
    # Por exemplo, um script que atualiza seus widgets ou envia uma notificação.
    # Adicione uma pequena pausa para garantir que a sessão esteja totalmente visível.
    ~/.config/hypr/scripts/random_wallpaper.sh
fi
