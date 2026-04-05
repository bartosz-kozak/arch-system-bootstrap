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
  neofetch
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
  ttf-meslo-nerd-font-powerlevel10k
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

readonly AUR_PACKAGES=(
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

cleanup() {
  if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
    kill "${SUDO_KEEPALIVE_PID}" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

run_as_target_user() {
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

  printf '%s\n' "${input_url}"

  if [[ "${input_url}" =~ ^https?://imgur\.com/([A-Za-z0-9]+)$ ]]; then
    local image_id="${BASH_REMATCH[1]}"
    printf 'https://i.imgur.com/%s.jpg\n' "${image_id}"
    printf 'https://i.imgur.com/%s.jpeg\n' "${image_id}"
    printf 'https://i.imgur.com/%s.png\n' "${image_id}"
    printf 'https://i.imgur.com/%s.webp\n' "${image_id}"
  fi
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

  tmp_file="$(run_as_target_user mktemp)"

  while IFS= read -r candidate; do
    [[ -n "${candidate}" ]] || continue
    log "Próbuję pobrać tapetę z ${candidate}."

    if run_as_target_user wget -q -O "${tmp_file}" "${candidate}" && run_as_target_user file --brief --mime-type -- "${tmp_file}" | grep -q '^image/'; then
      run_as_target_user install -m 0644 "${tmp_file}" "${wallpaper_target}"
      run_as_target_user rm -f -- "${tmp_file}"
      return 0
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
  installer_path="$(run_as_target_user mktemp)"

  log "Pobieram Miniforge3 z ${installer_url}."
  run_as_target_user wget -q -O "${installer_path}" "${installer_url}"

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
  log 'Instaluję pakiety z oficjalnych repozytoriów.'
  sudo pacman -Syu --needed --noconfirm "${PACMAN_PACKAGES[@]}"
}

ensure_yay() {
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

install_user_files() {
  local dotfiles_dir="${TARGET_REPO_ROOT}/dotfiles"
  local tmux_dir="${TARGET_HOME}/.config/tmux"
  local lf_dir="${TARGET_HOME}/.config/lf"
  local nvim_dir="${TARGET_HOME}/.config/nvim"

  log 'Instaluję pliki użytkownika.'
  run_as_target_user mkdir -p -- "${TARGET_HOME}/.config"
  run_as_target_user install -m 0644 "${dotfiles_dir}/x11/xinitrc" "${TARGET_HOME}/.xinitrc"
  run_as_target_user install -m 0644 "${dotfiles_dir}/zsh/arch/zshrc" "${TARGET_HOME}/.zshrc"

  copy_tree "${dotfiles_dir}/tmux" "${tmux_dir}"
  copy_tree "${dotfiles_dir}/lf" "${lf_dir}"
  copy_tree "${dotfiles_dir}/nvim" "${nvim_dir}"
}

install_tmux_plugins() {
  local plugin_root="${TARGET_HOME}/.config/tmux/plugins"

  log 'Instaluję TPM i pluginy tmux.'
  run_as_target_user mkdir -p -- "${plugin_root}"

  if [[ ! -d "${plugin_root}/tpm/.git" ]]; then
    run_as_target_user git clone https://github.com/tmux-plugins/tpm "${plugin_root}/tpm"
  fi

  run_as_target_user "${plugin_root}/tpm/bin/install_plugins"
}

install_suckless_tools() {
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
  local dotfiles_dir="${TARGET_REPO_ROOT}/dotfiles"
  ensure_repo "${DOTFILES_REPO_URL}" "${dotfiles_dir}"
}

configure_ly() {
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
  log 'Włączam podstawowe usługi systemowe.'
  sudo systemctl enable NetworkManager.service
  sudo systemctl enable bluetooth.service
}

configure_shell() {
  local zsh_path
  zsh_path="$(command -v zsh)"
  log "Ustawiam ${zsh_path} jako domyślną powłokę dla ${TARGET_USER}."
  sudo chsh -s "${zsh_path}" "${TARGET_USER}"
}

main() {
  ensure_supported_system
  prepare_sudo

  run_as_target_user mkdir -p -- "${TARGET_REPO_ROOT}"

  install_pacman_packages
  install_aur_packages
  install_dotfiles_repo
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
