# arch-system-bootstrap

Bootstrap nowej maszyny Arch. Skrypt jest uniwersalny — obsługuje zarówno stare maszyny z samym `dwm`, jak i nowsze z `Hyprland` (flaga `--with-hyprland`).

Co instaluje w wariancie bazowym:

- `ly` na `tty2`
- `dwm`, `st` z repozytoriów GitHub, `dmenu` z oficjalnego repo suckless
- `.xinitrc` z `dotfiles` (wykonywalny `0755`), z `picom`, `feh` i tapetą pobieraną z Imgur
- Miniforge3 lokalnie w `~/miniforge3`
- konfigurację `tmux`, `lf`, `nvim` i `zsh` (`zsh/arch/zshrc`)
- podstawowe pakiety desktopowe, audio, Bluetooth i przeglądarki (`chromium`, `qutebrowser`, `zen-browser-bin`)
- narzędzia CLI: `neofetch` (AUR), `cmatrix`, `lolcat`, `cowsay`, `sl`

Dodatkowe z `--with-hyprland`:

- pakiety: `hyprland`, `hyprpaper`, `kitty`, `waybar`, `xdg-desktop-portal-hyprland`
- pliki konfiguracyjne: `hypr`, `kitty`, `waybar`

## Wymagania

- Działający Arch Linux z `git`
- Uruchamiasz jako zwykły użytkownik z prawem do `sudo`
- Repozytoria klonowane po HTTPS — klucz SSH nie jest wymagany

## Użycie

```bash
mkdir -p ~/repos
cd ~/repos
git clone https://github.com/bartosz-kozak/arch-system-bootstrap.git
cd arch-system-bootstrap

# Stary komputer — tylko dwm/X11
sudo ./install.sh

# Nowy komputer — dwm + Hyprland
sudo ./install.sh --with-hyprland
```

### Tryby pomocnicze (bez sudo)

```bash
# Sprawdź i doinstaluj brakujące/zmienione dotfiles (dwm)
./install.sh --check-dotfiles

# Sprawdź i doinstaluj brakujące/zmienione dotfiles (dwm + Hyprland)
./install.sh --with-hyprland --check-dotfiles

# Przetestuj pobieranie tapety
./install.sh --download-wallpaper

# Własny URL tapety
WALLPAPER_URL="https://..." ./install.sh --download-wallpaper
```

`--with-hyprland` można łączyć z każdą z opcji powyżej.

## Struktura repozytoriów

Skrypt traktuje katalog nadrzędny instalatora jako katalog roboczy. Jeśli bootstrap leży w `~/repos/arch-system-bootstrap`, to obok niego zostaną sklonowane lub zaktualizowane:

```
~/repos/
├── arch-system-bootstrap/   ← ten skrypt
├── dotfiles/                ← klonowane z GitHub
├── dwm/                     ← klonowane z GitHub, budowane i instalowane
├── st/                      ← klonowane z GitHub, budowane i instalowane
└── dmenu/                   ← klonowane z suckless, budowane i instalowane
```

## Zmienne środowiskowe

```bash
TARGET_REPO_ROOT="$HOME/repos"              # domyślnie parent katalogu instalatora
TARGET_WALLPAPER_RELATIVE_PATH="Obrazy/tapety/arch_wallpaper1.jpg"
WALLPAPER_URL="https://i.imgur.com/Vm83FeC.jpg"
INSTALL_AUR_PACKAGES=true                   # false = pomiń pakiety AUR
```

## Co robi skrypt krok po kroku

1. Waliduje środowisko (Arch Linux, wymagane polecenia, katalog domowy)
2. Instaluje pakiety z `pacman` (+ pakiety Hyprland jeśli `--with-hyprland`)
3. Instaluje `yay`, potem pakiety AUR
4. Klonuje lub aktualizuje repozytorium `dotfiles`
5. Instaluje Miniforge3 lokalnie w `~/miniforge3`
6. Pobiera tapetę z `WALLPAPER_URL` przez `curl` z browser user-agent
7. Kopiuje pliki użytkownika z `dotfiles` (`.xinitrc` z uprawnieniami `0755`, `.zshrc`, `tmux`, `lf`, `nvim` oraz opcjonalnie `hypr`, `kitty`, `waybar`)
8. Instaluje pluginy `tmux` przez TPM
9. Buduje i instaluje `dwm`, `st`, `dmenu`
10. Konfiguruje `ly` (animacja matrix, tty2), włącza `NetworkManager` i `bluetooth`
11. Ustawia `zsh` jako domyślny shell

## Tryb --check-dotfiles

Porównuje SHA-256 każdego pliku z repozytorium `dotfiles` z wersją zainstalowaną na maszynie. Kopiuje tylko te pliki, które się różnią lub których brakuje. Nie wymaga `sudo` — dotfiles trafiają do `~/.config/` i `~/.*`.

## Uwagi

- `.xinitrc` musi być wykonywalny (`0755`) — inaczej `ly` nie odpali `dwm`
- Tapeta pobierana jest przez `curl` z Firefox user-agent (wget był blokowany przez Imgur z kodem 429)
- `fzf` jest instalowany przez `pacman`; integracja z Zsh przez `source <(fzf --zsh)` w `zshrc`
- Jeśli krok się wywali, skrypt wypisze nazwę kroku, numer linii i polecenie które zakończyło się błędem
