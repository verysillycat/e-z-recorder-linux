# E-Z Linux Recorder [<img src="https://r2.e-z.host/9e3dd702-42ab-4d6b-a8a0-b1a4ab53af33/35jx47l1.png" width="225" align="left" alt="E-Z Record Logo">](https://github.com/verysillycat/e-z-recorder-linux)
[![.gg/ez](https://img.shields.io/discord/811321950953406534.svg?color=768AD4&label=.gg/ez&logo=discord&logoColor=white)](https://discord.gg/ez)
#### Recording Videos & Uploading them to [e-z.host](https://e-z.host) with region, GIF, and sound support.
<br><br>
## Wayland Dependencies
`jq`, `wl-clipboard`, `slurp` & `wf-recorder`

<details>
<summary>How to install them?</summary>
Go to your prefered terminal and execute this command depending on your Distro.

- **Debian/Ubuntu**: `sudo apt install wf-recorder jq wl-clipboard slurp`
- **Fedora**: `sudo dnf install wf-recorder jq wl-clipboard slurp`
- **Arch**: `sudo pacman -S wf-recorder jq wl-clipboard slurp`
- **Gentoo**: `sudo emerge -av gui-apps/wf-recorder app-misc/jq x11-misc/wl-clipboard gui-apps/slurp`

</details>

## X11 Dependencies
`jq`, `xclip`, `slop` & `ffmpeg`

<details>
<summary>How to install them?</summary>
Go to your prefered terminal and execute this command depending on your Distro.

- **Debian/Ubuntu**: `sudo apt install ffmpeg jq xclip slop`
- **Fedora**: `sudo dnf install ffmpeg jq xclip slop`
- **Arch**: `sudo pacman -S ffmpeg jq xclip slop`
- **Gentoo**: `sudo emerge -av media-video/ffmpeg app-misc/jq x11-misc/xclip x11-misc/slop`

</details>

## Installation
   ```bash
   git clone https://github.com/verysillycat/e-z-recorder-linux
   cd e-z-wfrecorder-linux
   # [!] Replace the auth variable with your E-Z API KEY 
   ./e-z-recorder.sh 
   ```
<details>
<summary>How to get my API KEY?</summary>
Log in to E-Z, Click on your User Modal on the top right, Go to Account, and Copy your API KEY<br>
Now paste that API KEY into the Script
</details>

## Arguments
* `--help (-h)` show the list of arguments
* `--abort` abort recording and the upload
* `--sound` snip with sound 
* `--fullscreen` full screen without sound
* `--fullscreen-sound` fullscreen with sound
* `--gif` snip with gif output

## Variables
* `fps` will be your Max FPS
* `save` will save your Recorded Videos on `~/Videos`
* `failsave` if your Video Recording upload fails, it will be saved on `~/Videos/e-zfailed`


## Credits
This script was is based on [End's Dotfiles Record script](https://github.com/end-4/dots-hyprland/blob/main/.config/ags/scripts/record-script.sh) but also to detect active monitor support all Wayland DEs, and GIF Output.
