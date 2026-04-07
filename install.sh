#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly DEFAULT_REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly DEFAULT_WALLPAPER_RELATIVE_PATH="Obrazy/tapety/arch_wallpaper1.jpg"
readonly DEFAULT_WALLPAPER_URL="https://i.imgur.com/Vm83FeC.jpg"
readonly MINIFORGE_BASE_URL="https://github.com/conda-forge/miniforge/releases/latest/download"

readonly DWM_REPO_URL="https://github.com/bartosz-kozak/dwm_arch.git"
readonly ST_REPO_URL="https://github.com/bartosz-kozak/st_arch.git"
readonly DOTFILES_REPO_URL="https://github.com/bartosz-kozak/dotfiles.git"
readonly DMENU_REPO_URL="https://git.suckless.org/dmenu"

readonly PACMAN_PACKAGES=(
  alsa-utils
  arandr
  base-devel
  bluetui
  bluez
  bluez-utils
  brightnessctl
  chromium
  cmatrix
  cowsay
  fd
  feh
  fzf
  git
  htop
  imagemagick
  less
  lf
  libx11
  libxft
  libxinerama
  lolcat
  ly
  neovim
  networkmanager
  nodejs
  noto-fonts
  npm
  openssh
  pavucontrol
  picom
  pipewire
  pipewire-alsa
  pipewire-pulse
  pulsemixer
  qutebrowser
  ripgrep
  sudo
  sl
  tmux
  tree-sitter-cli
  ttf-dejavu
  ttf-jetbrains-mono-nerd
  ttf-liberation
  ttf-meslo-nerd
  unzip
  webp-pixbuf-loader
  wget
  wireplumber
  xdg-utils
  xf86-video-intel
  xorg-server
  xorg-xinit
  xorg-xrandr
  zoxide
  zsh
  zsh-autosuggestions
  zsh-syntax-highlighting
)

readonly HYPRLAND_PACKAGES=(
  hyprland
  hyprpaper
  kitty
  waybar
  xdg-desktop-portal-hyprland
)

readonly AUR_PACKAGES=(
  neofetch
  nordvpn-bin
  oh-my-posh-bin
  zen-browser-bin
)

TARGET_USER="${SUDO_USER:-${USER}}"
TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
TARGET_REPO_ROOT="${TARGET_REPO_ROOT:-${DEFAULT_REPO_ROOT}}"
TARGET_WALLPAPER_RELATIVE_PATH="${TARGET_WALLPAPER_RELATIVE_PATH:-${DEFAULT_WALLPAPER_RELATIVE_PATH}}"
WALLPAPER_URL="${WALLPAPER_URL:-${DEFAULT_WALLPAPER_URL}}"
INSTALL_AUR_PACKAGES="${INSTALL_AUR_PACKAGES:-true}"
WITH_HYPRLAND=false
CURRENT_STEP='inicjalizacja'
LAST_RUN_COMMAND=''

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

format_command() {
  local formatted=''
  local arg

  for arg in "$@"; do
    printf -v formatted '%s%q ' "${formatted}" "${arg}"
  done

  printf '%s\n' "${formatted% }"
}

handle_error() {
  local exit_code="$1"
  local line_no="$2"
  local command_text="$3"

  if [[ "${command_text}" == '"$@"' || -z "${command_text}" ]]; then
    command_text="${LAST_RUN_COMMAND:-${command_text}}"
  fi

  printf '[ERROR] Instalacja przerwana w kroku: %s\n' "${CURRENT_STEP}" >&2
  printf '[ERROR] Linia: %s\n' "${line_no}" >&2
  printf '[ERROR] Polecenie: %s\n' "${command_text}" >&2
  exit "${exit_code}"
}

cleanup() {
  if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
    kill "${SUDO_KEEPALIVE_PID}" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT
trap 'handle_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

run_as_target_user() {
  LAST_RUN_COMMAND="$(format_command "$@")"

  if [[ "${USER}" == "${TARGET_USER}" ]]; then
    "$@"
    return
  fi

  sudo -u "${TARGET_USER}" "$@"
}

require_command() {
  local command_name="$1"
  command -v "${command_name}" >/dev/null 2>&1 || die "Brakuje wymaganego polecenia: ${command_name}"
}

build_wallpaper_candidates() {
  local input_url="$1"
  local image_id

  # imgur.com/ID  ->  generuj warianty bezpośrednie
  if [[ "${input_url}" =~ ^https?://imgur\.com/([A-Za-z0-9]+)$ ]]; then
    image_id="${BASH_REMATCH[1]}"
    printf 'https://i.imgur.com/%s.jpg\n' "${image_id}"
    printf 'https://i.imgur.com/%s.png\n' "${image_id}"
    printf 'https://i.imgur.com/%s.jpeg\n' "${image_id}"
    printf 'https://i.imgur.com/%s.webp\n' "${image_id}"
    return
  fi

  # i.imgur.com/ID.ext  ->  próbuj też pozostałe rozszerzenia
  if [[ "${input_url}" =~ ^https?://i\.imgur\.com/([A-Za-z0-9]+)(\.[a-zA-Z]+)?$ ]]; then
    image_id="${BASH_REMATCH[1]}"
    printf 'https://i.imgur.com/%s.jpg\n' "${image_id}"
    printf 'https://i.imgur.com/%s.png\n' "${image_id}"
    printf 'https://i.imgur.com/%s.jpeg\n' "${image_id}"
    printf 'https://i.imgur.com/%s.webp\n' "${image_id}"
    return
  fi

  # dowolny inny URL — próbuj tak jak podano
  printf '%s\n' "${input_url}"
}

get_miniforge_arch() {
  case "$(uname -m)" in
    x86_64)
      printf 'x86_64\n'
      ;;
    aarch64 | arm64)
      printf 'aarch64\n'
      ;;
    ppc64le)
      printf 'ppc64le\n'
      ;;
    s390x)
      printf 's390x\n'
      ;;
    *)
      return 1
      ;;
  esac
}

download_wallpaper() {
  local wallpaper_target="$1"
  local tmp_file
  local candidate
  local mime

  tmp_file="$(run_as_target_user mktemp)"

  while IFS= read -r candidate; do
    [[ -n "${candidate}" ]] || continue
    log "Próbuję pobrać tapetę z ${candidate}."

    if run_as_target_user curl -fsSL \
        --user-agent 'Mozilla/5.0 (X11; Linux x86_64; rv:124.0) Gecko/20100101 Firefox/124.0' \
        --max-time 30 \
        -o "${tmp_file}" \
        "${candidate}"; then
      mime="$(file --brief --mime-type -- "${tmp_file}")"
      if [[ "${mime}" == image/* ]]; then
        run_as_target_user install -m 0644 "${tmp_file}" "${wallpaper_target}"
        run_as_target_user rm -f -- "${tmp_file}"
        log "Tapeta pobrana pomyślnie (${mime})."
        return 0
      else
        log "Pobrany plik nie jest obrazem (${mime}), próbuję następny URL."
      fi
    fi
  done < <(build_wallpaper_candidates "${WALLPAPER_URL}")

  run_as_target_user rm -f -- "${tmp_file}"
  return 1
}

install_miniforge() {
  local miniforge_dir="${TARGET_HOME}/miniforge3"
  local installer_path
  local arch
  local installer_url

  if [[ -x "${miniforge_dir}/bin/conda" ]]; then
    log "Miniforge3 jest już zainstalowany w ${miniforge_dir}."
    return
  fi

  arch="$(get_miniforge_arch)" || {
    warn "Nieobsługiwana architektura dla Miniforge3: $(uname -m). Pomijam instalację Miniforge3."
    return
  }

  installer_url="${MINIFORGE_BASE_URL}/Miniforge3-Linux-${arch}.sh"
  installer_path="$(run_as_target_user mktemp --suffix=.sh)"

  log "Pobieram Miniforge3 z ${installer_url}."
  run_as_target_user wget -O "${installer_path}" "${installer_url}"

  if ! run_as_target_user grep -q 'Miniforge' "${installer_path}"; then
    die "Pobrany plik instalatora Miniforge3 nie wygląda poprawnie: ${installer_path}"
  fi

  log "Instaluję Miniforge3 w ${miniforge_dir}."
  run_as_target_user bash "${installer_path}" -b -p "${miniforge_dir}"
  run_as_target_user rm -f -- "${installer_path}"
}

ensure_supported_system() {
  [[ -r /etc/arch-release ]] || die 'Ten instalator zakłada Arch Linux.'
  require_command pacman
  require_command git
  require_command file
  [[ -n "${TARGET_HOME}" ]] || die "Nie udało się ustalić katalogu domowego użytkownika ${TARGET_USER}."
}

prepare_sudo() {
  log "Pobieram uprawnienia sudo dla dalszych kroków."
  sudo -v
  while true; do
    sudo -n true
    sleep 50
    kill -0 "$$" >/dev/null 2>&1 || exit
  done &
  SUDO_KEEPALIVE_PID="$!"
}

install_pacman_packages() {
  CURRENT_STEP='instalacja pakietow pacman'
  log 'Instaluję pakiety z oficjalnych repozytoriów.'
  local packages=("${PACMAN_PACKAGES[@]}")
  if [[ "${WITH_HYPRLAND}" == 'true' ]]; then
    log 'Dodaję pakiety Hyprland.'
    packages+=("${HYPRLAND_PACKAGES[@]}")
  fi
  sudo pacman -Syu --needed --noconfirm "${packages[@]}"
}

ensure_yay() {
  CURRENT_STEP='instalacja yay'
  if command -v yay >/dev/null 2>&1; then
    log 'yay jest już dostępny.'
    return
  fi

  log 'Instaluję yay.'
  local build_dir
  build_dir="$(run_as_target_user mktemp -d)"
  run_as_target_user git clone https://aur.archlinux.org/yay.git "${build_dir}/yay"
  (
    cd "${build_dir}/yay"
    run_as_target_user makepkg -si --noconfirm
  )
  rm -rf -- "${build_dir}"
}

install_aur_packages() {
  CURRENT_STEP='instalacja pakietow AUR'
  if [[ "${INSTALL_AUR_PACKAGES}" != "true" ]]; then
    warn 'Pomijam pakiety AUR, bo INSTALL_AUR_PACKAGES != true.'
    return
  fi

  ensure_yay
  log 'Instaluję pakiety z AUR.'
  run_as_target_user yay -S --needed --noconfirm "${AUR_PACKAGES[@]}"
}

ensure_repo() {
  local repo_url="$1"
  local destination="$2"

  if [[ -d "${destination}/.git" ]]; then
    log "Aktualizuję repozytorium ${destination}."
    run_as_target_user git -C "${destination}" pull --ff-only
    return
  fi

  log "Klonuję ${repo_url} do ${destination}."
  run_as_target_user mkdir -p -- "$(dirname -- "${destination}")"
  run_as_target_user git clone "${repo_url}" "${destination}"
}

copy_tree() {
  local source_dir="$1"
  local destination_dir="$2"

  run_as_target_user mkdir -p -- "${destination_dir}"
  run_as_target_user cp -a "${source_dir}/." "${destination_dir}/"
}

install_wallpaper() {
  CURRENT_STEP='pobieranie tapety'
  local wallpaper_target="${TARGET_HOME}/${TARGET_WALLPAPER_RELATIVE_PATH}"
  local wallpaper_dir
  wallpaper_dir="$(dirname -- "${wallpaper_target}")"

  log "Przygotowuję tapetę w ${wallpaper_target}."
  run_as_target_user mkdir -p -- "${wallpaper_dir}"

  if [[ -n "${WALLPAPER_URL}" ]]; then
    if download_wallpaper "${wallpaper_target}"; then
      return
    fi

    warn "Nie udało się pobrać poprawnej tapety z ${WALLPAPER_URL}. Kontynuuję bez pliku tapety."
    return
  fi

  warn "Nie ustawiono WALLPAPER_URL. .xinitrc będzie wskazywał na ${wallpaper_target}."
}

dotfiles_check_file() {
  local src="$1"
  local dst="$2"
  local updated_ref="$3"
  local up_to_date_ref="$4"
  local mode="${5:-0644}"

  if [[ ! -f "${src}" ]]; then
    warn "Brak pliku źródłowego w dotfiles: ${src}. Pomijam."
    return
  fi

  if [[ ! -f "${dst}" ]]; then
    log "Instaluję nowy plik: ${dst}"
    run_as_target_user mkdir -p -- "$(dirname -- "${dst}")"
    run_as_target_user install -m "${mode}" "${src}" "${dst}"
    printf -v "${updated_ref}" '%d' "$(( ${!updated_ref} + 1 ))"
    return
  fi

  local src_hash dst_hash
  src_hash="$(sha256sum "${src}" | cut -d' ' -f1)"
  dst_hash="$(sha256sum "${dst}" | cut -d' ' -f1)"

  if [[ "${src_hash}" != "${dst_hash}" ]]; then
    log "Aktualizuję: ${dst}"
    run_as_target_user install -m "${mode}" "${src}" "${dst}"
    printf -v "${updated_ref}" '%d' "$(( ${!updated_ref} + 1 ))"
  else
    printf -v "${up_to_date_ref}" '%d' "$(( ${!up_to_date_ref} + 1 ))"
  fi
}

dotfiles_check_dir() {
  local src_dir="$1"
  local dst_dir="$2"
  local updated_ref="$3"
  local up_to_date_ref="$4"

  if [[ ! -d "${src_dir}" ]]; then
    warn "Brak katalogu źródłowego w dotfiles: ${src_dir}. Pomijam."
    return
  fi

  run_as_target_user mkdir -p -- "${dst_dir}"

  local src_file rel_path dst_file
  while IFS= read -r -d '' src_file; do
    rel_path="${src_file#${src_dir}/}"
    dst_file="${dst_dir}/${rel_path}"
    dotfiles_check_file "${src_file}" "${dst_file}" "${updated_ref}" "${up_to_date_ref}"
  done < <(find "${src_dir}" -type f -print0 | sort -z)
}

check_and_update_dotfiles() {
  CURRENT_STEP='sprawdzanie aktualnosci dotfiles'
  local dotfiles_dir="${TARGET_REPO_ROOT}/dotfiles"
  local updated=0
  local up_to_date=0

  [[ -d "${dotfiles_dir}" ]] || die "Nie znaleziono repozytorium dotfiles w ${dotfiles_dir}."

  log "Sprawdzam aktualność dotfiles (porównanie SHA-256)."

  dotfiles_check_file "${dotfiles_dir}/x11/xinitrc"      "${TARGET_HOME}/.xinitrc"        updated up_to_date 0755
  dotfiles_check_file "${dotfiles_dir}/zsh/arch/zshrc"   "${TARGET_HOME}/.zshrc"          updated up_to_date
  dotfiles_check_dir  "${dotfiles_dir}/tmux"             "${TARGET_HOME}/.config/tmux"    updated up_to_date
  dotfiles_check_dir  "${dotfiles_dir}/lf"               "${TARGET_HOME}/.config/lf"      updated up_to_date
  dotfiles_check_dir  "${dotfiles_dir}/nvim"             "${TARGET_HOME}/.config/nvim"    updated up_to_date

  if [[ "${WITH_HYPRLAND}" == 'true' ]]; then
    dotfiles_check_dir "${dotfiles_dir}/hypr"   "${TARGET_HOME}/.config/hypr"   updated up_to_date
    dotfiles_check_dir "${dotfiles_dir}/kitty"  "${TARGET_HOME}/.config/kitty"  updated up_to_date
    dotfiles_check_dir "${dotfiles_dir}/waybar" "${TARGET_HOME}/.config/waybar" updated up_to_date
  fi

  log "Dotfiles: ${updated} zaktualizowanych, ${up_to_date} aktualnych."
}

install_user_files() {
  CURRENT_STEP='instalacja plikow uzytkownika'
  local dotfiles_dir="${TARGET_REPO_ROOT}/dotfiles"

  log 'Instaluję pliki użytkownika.'
  run_as_target_user mkdir -p -- "${TARGET_HOME}/.config"
  run_as_target_user install -m 0755 "${dotfiles_dir}/x11/xinitrc"    "${TARGET_HOME}/.xinitrc"
  run_as_target_user install -m 0644 "${dotfiles_dir}/zsh/arch/zshrc" "${TARGET_HOME}/.zshrc"

  copy_tree "${dotfiles_dir}/tmux" "${TARGET_HOME}/.config/tmux"
  copy_tree "${dotfiles_dir}/lf"   "${TARGET_HOME}/.config/lf"
  copy_tree "${dotfiles_dir}/nvim" "${TARGET_HOME}/.config/nvim"

  if [[ "${WITH_HYPRLAND}" == 'true' ]]; then
    log 'Instaluję pliki konfiguracyjne Hyprland.'
    copy_tree "${dotfiles_dir}/hypr"   "${TARGET_HOME}/.config/hypr"
    copy_tree "${dotfiles_dir}/kitty"  "${TARGET_HOME}/.config/kitty"
    copy_tree "${dotfiles_dir}/waybar" "${TARGET_HOME}/.config/waybar"
  fi
}

install_tmux_plugins() {
  CURRENT_STEP='instalacja pluginow tmux'
  local plugin_root="${TARGET_HOME}/.config/tmux/plugins"

  log 'Instaluję TPM i pluginy tmux.'
  run_as_target_user mkdir -p -- "${plugin_root}"

  if [[ ! -d "${plugin_root}/tpm/.git" ]]; then
    run_as_target_user git clone https://github.com/tmux-plugins/tpm "${plugin_root}/tpm"
  fi

  run_as_target_user "${plugin_root}/tpm/bin/install_plugins"
}

install_suckless_tools() {
  CURRENT_STEP='budowanie i instalacja suckless tools'
  local dwm_dir="${TARGET_REPO_ROOT}/dwm"
  local st_dir="${TARGET_REPO_ROOT}/st"
  local dmenu_dir="${TARGET_REPO_ROOT}/dmenu"

  log 'Klonuję repozytoria dwm, st i dmenu.'
  ensure_repo "${DWM_REPO_URL}" "${dwm_dir}"
  ensure_repo "${ST_REPO_URL}" "${st_dir}"
  ensure_repo "${DMENU_REPO_URL}" "${dmenu_dir}"

  log 'Buduję i instaluję dwm.'
  sudo make -C "${dwm_dir}" clean install

  log 'Buduję i instaluję st.'
  sudo make -C "${st_dir}" clean install

  log 'Buduję i instaluję dmenu.'
  sudo make -C "${dmenu_dir}" clean install
}

install_dotfiles_repo() {
  CURRENT_STEP='klonowanie dotfiles'
  local dotfiles_dir="${TARGET_REPO_ROOT}/dotfiles"
  ensure_repo "${DOTFILES_REPO_URL}" "${dotfiles_dir}"
}

configure_ly() {
  CURRENT_STEP='konfiguracja ly'
  local config_file='/etc/ly/config.ini'

  log 'Konfiguruję ly zgodnie z obecną maszyną.'
  sudo sed -i \
    -e 's/^animation = .*/animation = matrix/' \
    -e 's/^battery_id = .*/battery_id = BAT0/' \
    -e 's/^bigclock = .*/bigclock = en/' \
    "${config_file}"

  sudo systemctl enable ly@tty2.service
}

configure_services() {
  CURRENT_STEP='konfiguracja uslug systemowych'
  log 'Włączam podstawowe usługi systemowe.'
  sudo systemctl enable NetworkManager.service
  sudo systemctl enable bluetooth.service
}

configure_shell() {
  CURRENT_STEP='konfiguracja powloki'
  local zsh_path
  zsh_path="$(command -v zsh)"
  log "Ustawiam ${zsh_path} jako domyślną powłokę dla ${TARGET_USER}."
  sudo chsh -s "${zsh_path}" "${TARGET_USER}"
}

main() {
  local check_dotfiles_only=false
  local download_wallpaper_only=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --with-hyprland)
        WITH_HYPRLAND=true
        shift
        ;;
      --check-dotfiles)
        check_dotfiles_only=true
        shift
        ;;
      --download-wallpaper)
        download_wallpaper_only=true
        shift
        ;;
      *)
        die "Nieznana opcja: $1. Użycie: $0 [--with-hyprland] [--check-dotfiles|--download-wallpaper]"
        ;;
    esac
  done

  if [[ "${check_dotfiles_only}" == 'true' ]]; then
    [[ -n "${SUDO_USER}" ]] && warn "Tryb --check-dotfiles nie wymaga sudo — uruchom jako zwykły użytkownik."
    [[ -n "${TARGET_HOME}" ]] || die "Nie udało się ustalić katalogu domowego użytkownika ${TARGET_USER}."
    check_and_update_dotfiles
    log 'Sprawdzanie dotfiles zakończone.'
    return
  fi

  if [[ "${download_wallpaper_only}" == 'true' ]]; then
    [[ -n "${TARGET_HOME}" ]] || die "Nie udało się ustalić katalogu domowego użytkownika ${TARGET_USER}."
    log "URL tapety: ${WALLPAPER_URL}"
    log "Cel: ${TARGET_HOME}/${TARGET_WALLPAPER_RELATIVE_PATH}"
    install_wallpaper
    return
  fi

  CURRENT_STEP='walidacja srodowiska'
  ensure_supported_system
  CURRENT_STEP='pobranie sudo'
  prepare_sudo

  CURRENT_STEP='tworzenie katalogu repozytoriow'
  run_as_target_user mkdir -p -- "${TARGET_REPO_ROOT}"

  install_pacman_packages
  install_aur_packages
  install_dotfiles_repo
  CURRENT_STEP='instalacja miniforge3'
  install_miniforge
  install_wallpaper
  install_user_files
  install_tmux_plugins
  install_suckless_tools
  configure_ly
  configure_services
  configure_shell

  log 'Instalacja zakończona.'
  log 'Na nowym systemie możesz zalogować się przez ly lub uruchomić startx ręcznie.'
}

main "$@"
