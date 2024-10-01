# E-Z Linux Recorder [<img src="https://r2.e-z.host/9e3dd702-42ab-4d6b-a8a0-b1a4ab53af33/35jx47l1.png" width="225" align="left" alt="E-Z Record Logo">](https://github.com/verysillycat/e-z-recorder-linux)

#### Screen Recording & Uploading to [e-z.host](https://e-z.host) with region, GIF and sound support.

[![Total Commits](https://img.shields.io/github/commit-activity/t/verysillycat/e-z-recorder-linux?style=flat&logo=github&label=Commits&labelColor=%230f0f0f&color=%23191919)](https://github.com/verysillycat/e-z-recorder-linux/commits/)
<br><br><br>

## Dependencies

- **Wayland**: `jq`, `wl-clipboard`, `slurp` & `wf-recorder`
- \***\*COSMIC & GNOME / KDE Wayland\*\***: `jq`, `wl-clipboard` & `kooha`
- **X11**: `jq`, `xclip`, `slop` & `ffmpeg`

<details>
<summary>How to install them?</summary>

Go to your prefered terminal and execute this command depending on your Distro.
| Compositor | Distribution | Instructions |
| ------------------- | ----------------------- | ----------------------------------------------------------------------------------------------------- |
| **Wayland** | **Debian/Ubuntu** | `sudo apt install wf-recorder jq wl-clipboard slurp` |
| **Wayland** | **Fedora** | `sudo dnf install wf-recorder jq wl-clipboard slurp` |
| **Wayland** | **Arch** | `sudo pacman -S wf-recorder jq wl-clipboard slurp` |
| **Wayland** | **Gentoo** | `sudo emerge -av gui-apps/wf-recorder app-misc/jq x11-misc/wl-clipboard gui-apps/slurp` |

| Compositor | Distribution      | Instructions                                                                  |
| ---------- | ----------------- | ----------------------------------------------------------------------------- |
| **X11**    | **Debian/Ubuntu** | `sudo apt install ffmpeg jq xclip slop`                                       |
| **X11**    | **Fedora**        | `sudo apt install ffmpeg jq xclip slop`                                       |
| **X11**    | **Arch**          | `sudo pacman -S ffmpeg jq xclip slop`                                         |
| **X11**    | **Gentoo**        | `sudo emerge -av media-video/ffmpeg app-misc/jq x11-misc/xclip x11-misc/slop` |

| Compositor                       | Distribution      | Instructions                                                          |
| -------------------------------- | ----------------- | --------------------------------------------------------------------- |
| **COSMIC & GNOME / KDE Wayland** | **Debian/Ubuntu** | `sudo apt install kooha jq wl-clipboard`                              |
| **COSMIC & GNOME / KDE Wayland** | **Fedora**        | `sudo dnf install kooha jq wl-clipboard`                              |
| **COSMIC & GNOME / KDE Wayland** | **Arch**          | `sudo pacman -S kooha jq wl-clipboard`                                |
| **COSMIC & GNOME / KDE Wayland** | **Gentoo**        | `sudo emerge -av media-video/kooha app-misc/jq x11-misc/wl-clipboard` |

 </details>

## Installation

[![e-z-recorder](https://img.shields.io/badge/AVAILABLE_ON_THE_AUR-333232?style=for-the-badge&logo=arch-linux&logoColor=3d67db&labelColor=%23171717)](https://aur.archlinux.org/packages/e-z-recorder)

```bash
git clone https://github.com/verysillycat/e-z-recorder-linux
cd e-z-recorder-linux
# [!] Start the Script to Create the Configuration file
./e-z-recorder.sh
```

<details>
<summary>How to get my API KEY?</summary>
Log in to E-Z, Click on your User Modal on the top right, Go to Account, and Copy your API KEY<br>
Now paste that API KEY into auth variable in the Config File
</details>

## Arguments

- `--help (-h)` show the list of arguments
- `--abort` abort recording and the upload
- `--sound` snip with sound
- `--fullscreen` full screen without sound
- `--fullscreen-sound` fullscreen with sound
- `--gif` snip with gif output
- `upload (-u)` upload specified video files (mp4, mkv, webm, gif)
- `--config` open the configuration file in the default text editor
- `--config-reinstall` reinstall the configuration file with default settings

##### ★ When using Kooha, you'll not see some of these arguments as they aren't needed.

## Configuration

- `fps` will be your Max FPS
- `pixelformat` set the pixel format, default is `yuv420p`
- `encoder` set the encoder, default is `libx264`
- `preset` set the preset profile
- `crf` set crf number
- `save` will save your Recorded Videos on `~/Videos`
- `failsave` if your Video Recording upload fails, it will be saved on `~/Videos/e-zfailed`
- `colorworkaround` re-encode videos on upload for color correction, might take longer to upload
- `startnotif` show the start notification or not
- `endnotif` show the end notification or not
- `directory` set directory to save videos in there will be ignored if using kooha
- `kooha_dir` set the kooha directory also save videos in here if using kooha

## Credits

This script was is based on [End's Dotfiles Record script](https://github.com/end-4/dots-hyprland/blob/main/.config/ags/scripts/record-script.sh) but to support alot more DEs, Configuration, allow GIF Output & more.
