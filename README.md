# arch-system-bootstrap

Bootstrap nowej maszyny Arch:

- `ly` na `tty2`
- `dwm` i `st` z  repozytoriów GitHub
- `dmenu` z oficjalnego repo suckless
- `.xinitrc` z `dotfiles`, z `picom`, `feh` i tapetą pobieraną z Imgur
- Miniforge3 instalowany lokalnie w `~/miniforge3`
- konfigurację `tmux`, `lf`, `nvim` i `zsh`
- podstawowe pakiety desktopowe, audio, Bluetooth i przeglądarki
- narzędzia CLI, w tym `neofetch`, `cmatrix`, `lolcat`, `cowsay` i `sl`

## Wymagania

- System bazowy ma już działający Arch Linux i `git`
- Instalator uruchamiasz jako zwykły użytkownik z prawem do `sudo`
- Repozytoria są klonowane po HTTPS, żeby nie wymagać od razu skonfigurowanego klucza SSH

## Użycie

```bash
mkdir -p ~/repos
cd ~/repos
# skopiuj tutaj katalog arch-system-bootstrap
git clone 
```

Domyślnie skrypt traktuje katalog nadrzędny instalatora jako katalog roboczy na repozytoria. Jeśli więc bootstrap leży w `~/repos/arch-system-bootstrap`, to obok niego zostaną sklonowane lub zaktualizowane:

- `~/repos/dotfiles`
- `~/repos/dwm`
- `~/repos/st`
- `~/repos/dmenu`

## Konfiguracja

Zmienne środowiskowe przed uruchomieniem:

```bash
TARGET_REPO_ROOT="$HOME/repos"              # opcjonalny override; domyślnie parent katalogu instalatora
TARGET_WALLPAPER_RELATIVE_PATH="Obrazy/tapety/arch_wallpaper1.jpg"
WALLPAPER_URL="https://i.imgur.com/Vm83FeC.jpg"
INSTALL_AUR_PACKAGES=true                   # ustaw na false, jeśli chcesz pominąć AUR
```

## Co robi skrypt

1. Instaluje pakiety z `pacman`
2. Instaluje `yay`, a potem pakiety AUR
3. Instaluje Miniforge3 lokalnie w katalogu domowym użytkownika
4. Klonuje lub aktualizuje `dotfiles`, `dwm`, `st` i `dmenu` w tym samym katalogu nadrzędnym co bootstrap
5. Kopiuje tapetę i pliki użytkownika z `dotfiles`, w tym `zsh/arch/zshrc` jako `~/.zshrc` oraz konfigurację `lf` do `~/.config/lf`
6. Instaluje pluginy `tmux`
7. Buduje `dwm`, `st` i `dmenu`
8. Ustawia konfigurację `ly`, włącza usługi i przełącza shell na `zsh`

## Uwagi konfiguracyjne

- Na Archu instalator używa `dotfiles/zsh/arch/zshrc`
- `fzf` jest instalowany przez `pacman`, a jego integracja z Zsh jest włączana przez `source <(fzf --zsh)` w `zsh/arch/zshrc`
- Font Meslo jest instalowany jako `ttf-meslo-nerd`; pakiet `ttf-meslo-nerd-font-powerlevel10k` nie jest używany
- Jeśli któryś krok instalacji się wywali, skrypt wypisze nazwę kroku, numer linii i polecenie, które zakończyło się błędem
