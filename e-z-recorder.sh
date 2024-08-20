#!/bin/bash

if [[ $EUID -eq 0 ]]; then
    echo -e "\e[31mThis script should not be run as root.\e[0m"
    sleep 3
    echo
    read -p "Do you want to proceed anyway? (Y/N): " confirm
    if [[ ! "$confirm" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]; then
        echo "Exiting."
        exit 1
    fi
fi

if [[ "$XDG_SESSION_TYPE" == "wayland" && ("$XDG_CURRENT_DESKTOP" == "GNOME" || "$XDG_CURRENT_DESKTOP" == "KDE") ]]; then
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        echo "Usage: e-z-recorder(.sh) [ARGUMENTS]"
        echo ""
        echo "Arguments:"
        echo "  --help                 Show this help message and exit"
        echo "  --abort                Abort the current recording"
        echo "  --gif                  Record a Video and convert to GIF"
        echo "  upload, -u             Upload specified video files (mp4, mkv, webm, gif)"
        echo "  --config               Open the configuration file in the default text editor"
        echo "  --config-reinstall     Reinstall the configuration file with default settings"
        echo ""
        echo "Note: This help message is specific to Wayland sessions on GNOME and KDE."
        exit 0
    fi
fi

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: e-z-recorder(.sh) [ARGUMENTS]"
    echo ""
    echo "Arguments:"
    echo "  --help, -h             Show this help message and exit"
    echo "  --abort                Abort the current recording"
    echo "  --sound                Record a selected region with sound"
    echo "  --fullscreen           Record the entire screen without sound"
    echo "  --fullscreen-sound     Record the entire screen with sound"
    echo "  --gif                  Record a selected region and convert to GIF"
    echo "  upload, -u             Upload specified video files (mp4, mkv, webm, gif)"
    echo "  --config               Open the configuration file in the default text editor"
    echo "  --config-reinstall     Reinstall the configuration file with default settings"
    echo ""
    exit 0
fi

config_file="~/.config/e-z-recorder/config.conf"
create_default_config() {
    mkdir -p "$(dirname "$(eval echo $config_file)")"
    cat <<EOL > "$(eval echo $config_file)"
# On Kooba FPS, Encoder & Pixel Format doesn't work but you can change FPS on GUI Preferences.
## Aswell as the file extension, and directory in there.
auth=""
url="https://api.e-z.host/files"
fps=60
pixelformat=yuv420p
encoder=libx264
save=false
failsave=true
colorworkaround=false
startnotif=true
endnotif=true
directory="~/Videos"
kooha_dir="~/Videos/Kooha"

gif_pending_file="/tmp/gif_pending"
kooha_last_time="~/.config/e-z-recorder/last_time"
EOL
    echo "Default Configuration file created."
    printf "\e[30m\e[46m $(eval echo $config_file) \e[0m\n"
    printf "\e[1;34mEdit the configuration file to set your E-Z API KEY.\e[0m\n"
    printf "\e[1;31mOtherwise, the script will not work.\e[0m\n"
}

if [[ ! -f "$(eval echo $config_file)" ]]; then
    create_default_config
    exit 0
fi

source "$(eval echo $config_file)"

if [[ "$1" == "--config" ]]; then
    if command -v xdg-open > /dev/null; then
        xdg-open "$(eval echo $config_file)"
    elif command -v open > /dev/null; then
        open "$(eval echo $config_file)"
    elif command -v nvim > /dev/null; then
        nvim "$(eval echo $config_file)"
    elif command -v nano > /dev/null; then
        nano "$(eval echo $config_file)"
    else
        echo "No suitable text editor found. Please open $(eval echo $config_file) manually."
    fi
    exit 0
fi

if [[ "$1" == "--config-reinstall" ]]; then
    read -p "Do you want to reinstall the config file with default settings? (Y/N): " confirm
    if [[ "$confirm" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]; then
        create_default_config
        echo "Configuration file reinstalled with default settings."
    else
        echo "Reinstallation canceled."
    fi
    exit 0
fi

if [[ -z "$url" ]]; then
    echo "URL is not set."
    echo "Edit the configuration file with --config to add E-Z's API URL."
    notify-send "URL is not set." 'Edit the config file to add the E-Z API URL.' -a "E-Z Recorder"
    exit 1
fi

if [[ -z "$auth" ]]; then
    echo "API Key is not set."
    echo "Edit the configuration file with --config to add your E-Z API KEY."
    notify-send "API Key is not added." 'Edit the configuration file to add your E-Z API KEY.' -a "E-Z Recorder"
    exit 1
fi

if [[ -z "$encoder" && ! ("$XDG_SESSION_TYPE" == "wayland" && ("$XDG_CURRENT_DESKTOP" == "GNOME" || "$XDG_CURRENT_DESKTOP" == "KDE")) ]]; then
    echo "Encoder is not set."
    echo "Edit the configuration file with --config to add the encoder."
    notify-send "Encoder is not set." 'Edit the config file to add the encoder.' -a "E-Z Recorder"
    exit 1
fi

if [[ -z "$pixelformat" && ! ("$XDG_SESSION_TYPE" == "wayland" && ("$XDG_CURRENT_DESKTOP" == "GNOME" || "$XDG_CURRENT_DESKTOP" == "KDE")) ]]; then
    echo "Pixelformat is not set."
    echo "Edit the configuration file with --config to add the pixelformat."
    notify-send "Pixelformat is not set." 'Edit the config file to add the pixelformat.' -a "E-Z Recorder"
    exit 1
fi

getdate() {
    date '+%Y-%m-%d_%H.%M.%S'
}
getaudiooutput() {
    pactl list sources | grep 'Name' | grep 'monitor' | cut -d ' ' -f2
}
getactivemonitor() {
    if [[ "$XDG_SESSION_TYPE" == "x11" ]]; then
        active_monitor=$(xdpyinfo | grep dimensions | awk '{print $2}')
    else
        active_monitor=$(wlr-randr --json | jq -r '.[] | select(.enabled == true) | .name')
    fi
    echo "$active_monitor"
}

gif() {
    local video_file=$1
    local gif_file="${video_file%.mp4}.gif"
    ffmpeg -i "$video_file" -vf "fps=40,scale=960:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=256[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5" -c:v gif "$gif_file"
    rm "$video_file"
    echo "$gif_file"
}

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\\'
    tput civis && stty -echo
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        echo -ne "\033[36;6m[${spinstr:0:1}]\033[0m"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        echo -ne "\b\b\b"
    done
    echo -ne "\r"
    tput el
    stty echo && tput cnorm
}

upload() {
    local file=$1
    local is_gif=$2
    response_file="/tmp/uploadvideo.json"

    if [[ ! -f "$file" ]]; then
        notify-send "Error: File not found: $file" -a "E-Z Recorder"
        exit 1
    fi

    if [[ "$file" == *.mp4 ]]; then
        content_type="video/mp4"
    elif [[ "$file" == *.gif ]]; then
        content_type="image/gif"
    elif [[ "$file" == *.mkv ]]; then
        content_type="video/mkv"
    elif [[ "$file" == *.webm ]]; then
        content_type="video/webm"
    else
        content_type="application/octet-stream"
    fi

    curl -X POST -F "file=@${file};type=${content_type}" -H "key: ${auth}" -v "${url}" 2>/dev/null > $response_file

    if ! jq -e . >/dev/null 2>&1 < $response_file; then
        notify-send "Error occurred while uploading. Please try again later." -a "E-Z Recorder"
        rm $response_file
        [[ "$failsave" == true && "$1" != "--abort" && "$upload_mode" != true ]] && mkdir -p ~/Videos/e-zfailed && mv "$file" ~/Videos/e-zfailed/
        [[ "$is_gif" == "--gif" ]] && rm "$gif_pending_file"
        [[ "$upload_mode" == true ]] && printf "\033[1;5;31mERROR:\033[0m Upload failed for file: \033[1;34m$filename\033[0m\n"
        exit 1
    fi

    success=$(jq -r ".success" < $response_file)
    if [[ "$success" != "true" ]] || [[ "$success" == "null" ]]; then
        error=$(jq -r ".error" < $response_file)
        if [[ "$error" == "null" ]]; then
            notify-send "Error occurred while uploading. Please try again later." -a "E-Z Recorder"
        else
            notify-send "Error: $error" -a "E-Z Recorder"
        fi
        [[ "$failsave" == true && "$1" != "--abort" && "$upload_mode" != true ]] && mkdir -p ~/Videos/e-zfailed && mv "$file" ~/Videos/e-zfailed/
        [[ "$is_gif" == "--gif" ]] && rm "$gif_pending_file"
        [[ "$upload_mode" == true ]] && printf "\033[1;5;31mERROR:\033[0m Upload failed for file: \033[1;34m$filename\033[0m\n"
        rm $response_file
        exit 1
    fi

    file_url=$(jq -r ".imageUrl" < $response_file)
    if [[ "$file_url" != "null" ]]; then
        if [[ "$save" == true && "$XDG_SESSION_TYPE" == "wayland" && ("$XDG_CURRENT_DESKTOP" == "GNOME" || "$XDG_CURRENT_DESKTOP" == "KDE") ]]; then
            echo $(date +%s) > "$(eval echo $kooha_last_time)"
        fi
        if [[ "$XDG_SESSION_TYPE" == "x11" ]]; then
            echo "$file_url" | xclip -selection clipboard
        else
            echo "$file_url" | wl-copy
        fi
        if [[ "$is_gif" == "--gif" || "$file" == *.gif ]]; then
            if [[ "$XDG_SESSION_TYPE" != "wayland" || ("$XDG_CURRENT_DESKTOP" != "GNOME" && "$XDG_CURRENT_DESKTOP" != "KDE") ]]; then
                notify-send -i link "GIF URL copied to clipboard" -a "E-Z Recorder"
            fi
        [[ "$is_gif" == "--gif" && "$1" != "-u" && "$1" != "upload" ]] && rm "$gif_pending_file"
        else
            if [[ "$XDG_SESSION_TYPE" != "wayland" || ("$XDG_CURRENT_DESKTOP" != "GNOME" && "$XDG_CURRENT_DESKTOP" != "KDE") ]]; then
                notify-send -i link "Video URL copied to clipboard" -a "E-Z Recorder"
            fi
        fi
            if [[ "$save" == false && "$upload_mode" != true ]]; then
            rm "$file"
        fi
    else
        notify-send "Error: File URL is null" -a "E-Z Recorder"
    fi
    if [[ "$upload_mode" != true ]]; then
        rm $response_file
    fi
}

if [[ "$1" == "upload" || "$1" == "-u" ]]; then
    upload_mode=true
    lockfile="$(eval echo $HOME/.config/e-z-recorder/upload.lck)"
    if [[ -f "$lockfile" ]]; then
        other_pid=$(cat "$lockfile")
        if kill -0 "$other_pid" 2>/dev/null; then
            echo "Another upload process is already running."
            read -p "Do you want to terminate the other upload process? (Y/N): " confirm
            if [[ "$confirm" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]; then
                kill "$other_pid"
            else
                echo "Waiting for the other upload process to finish..."
                while [[ -f "$lockfile" ]] && kill -0 $(cat "$lockfile") 2>/dev/null; do
                    sleep 2.5
                done
            fi
        fi
    fi
    echo $$ > "$lockfile"
    trap 'rm -f "$lockfile"; exit' INT TERM EXIT

    shift
    files=("$@")
    if [[ ${#files[@]} -eq 0 ]]; then
        printf "\033[1m(?) \033[0mNo files specified for upload.\n"
        rm -f "$lockfile"
        exit 1
    fi

    if [[ ${#files[@]} -ge 5 ]]; then
        echo "Too many files specified for upload. Please upload fewer than 5 files at a time."
        rm -f "$lockfile"
        exit 1
    fi

    valid_extensions=("mp4" "mkv" "webm" "gif")
    declare -A processed_files
    file_count=0

    for file in "${files[@]}"; do
        filename=$(basename "$file")
        extension="${filename##*.}"
        file_key="${file}:${filename}"

        if [[ ! " ${valid_extensions[@]} " =~ " ${extension} " ]]; then
            printf "\033[1;5;33m(!)\033[0m Invalid file type: \033[1;34m${filename%.*}\033[4m.${extension}\033[0m\n"
            continue
        fi

        if [[ -n "${processed_files[$file_key]}" ]]; then
            printf "\033[1;5;33m(!)\033[0m Skipping Duplicated Video: \033[1;34m\033[7m$filename\033[0m\n"
            continue
        fi

        if [[ ! -f "$file" ]]; then
            printf "\033[1m[1/4] \033[0mChecking if\033[1;34m $filename \033[0mexists\n"
            sleep 0.3
            printf "\033[1;5;31mERROR:\033[0m File not found:\033[1;34m $filename\033[0m\n"
            continue
        fi
        sleep 0.1
        printf "\033[1m[1/4] \033[0mChecking if\033[1;34m $filename \033[0mexists\n"
        sleep 0.2
        printf "\033[1m[2/4]\033[0m\033[1;34m $filename \033[0mfound\n"
        sleep 0.2
        printf "\033[1m[3/4]\033[0m Uploading:\033[1;34m $filename \033[0m\n"
        ((file_count++))
        upload "$file" &
        spinner $!

        upload_url=$(jq -r ".imageUrl" < /tmp/uploadvideo.json)
        if [[ $? -eq 0 ]]; then
            if [[ "$XDG_SESSION_TYPE" == "x11" ]]; then
                echo "$upload_url" | xclip -selection clipboard
            else
                echo "$upload_url" | wl-copy
            fi
            processed_files["$file_key"]=1
        fi
        if [[ $? -eq 0 ]]; then
            printf "\033[1m[4/4]\033[0m Upload successful: \033[1;32m%s\033[0m\n" "$upload_url"
            rm /tmp/uploadvideo.json
        else
            printf "\033[1;5;31mERROR:\033[0m Failed to upload file: \033[1;34m%s\033[0m\n" "$filename"
        fi
        if (( file_count % 3 == 0 )); then
            sleep 3.2
        fi
    done

    rm -f "$lockfile"
    trap - INT TERM EXIT
    exit 0
fi

if [[ "$save" == true && ! ("$XDG_SESSION_TYPE" == "wayland" && ("$XDG_CURRENT_DESKTOP" == "GNOME" || "$XDG_CURRENT_DESKTOP" == "KDE")) ]]; then
    mkdir -p "$(eval echo $directory)"
    cd "$(eval echo $directory)" || exit
else
    cd /tmp || exit
fi

if [[ "$1" == "--abort" ]]; then
    if [[ "$XDG_SESSION_TYPE" == "x11" ]]; then
        if pgrep ffmpeg > /dev/null; then
            [[ "$endnotif" == true ]] && notify-send "Recording Aborted" "The upload has been canceled." -a "E-Z Recorder"
            pkill ffmpeg
            if [[ -f "$gif_pending_file" ]]; then
                rm "$gif_pending_file"
            fi
            if [[ "$save" == false ]]; then
                video_file=$(ls -t recording_*.mp4 | head -n 1)
                rm "$video_file"
            fi
            exit 0
        else
            notify-send "No Recording in Progress" "There is no recording to cancel." -a "E-Z Recorder"
            exit 0
        fi
    else
        if pgrep wf-recorder > /dev/null; then
            [[ "$endnotif" == true ]] && notify-send "Recording Aborted" "The upload has been canceled." -a "E-Z Recorder"
            pkill wf-recorder
            if [[ -f "$gif_pending_file" ]]; then
                rm "$gif_pending_file"
            fi
            if [[ "$save" == false ]]; then
                video_file=$(ls -t recording_*.mp4 | head -n 1)
                rm "$video_file"
            fi
            exit 0
        elif pgrep kooha > /dev/null; then
            [[ "$endnotif" == true ]] && notify-send "Recording Aborted" "The upload has been canceled." -a "E-Z Recorder"
            parent_pid=$(pgrep -f "kooha" | xargs -I {} ps -o ppid= -p {})
            if [[ -n "$parent_pid" ]]; then
            if [[ -d "$(eval echo $kooha_dir)" ]]; then
                if [[ -f "$(eval echo $kooha_last_time)" ]]; then
                    kooha_last_time=$(eval echo $kooha_last_time)
                    find "$(eval echo $kooha_dir)" -type f \( -name "*.mp4" -o -name "*.mkv" -o -name "*.webm" \) -newer "$kooha_last_time" -exec rm {} \;
                    rm "$(eval echo $kooha_last_time)"
                fi
            fi
            killall kooha && kill -KILL "$parent_pid"
            fi
            exit 0
        else
            notify-send "No Recording in Progress" "There is no recording to cancel." -a "E-Z Recorder"
            exit 0
        fi
    fi
fi

post_process_video() {
    local input_file=$1
    local output_file="${input_file%.mp4}_processed.mp4"
    ffmpeg -i "$input_file" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2,format=$pixelformat" -colorspace bt709 -color_primaries bt709 -color_trc bt709 -c:v $encoder -preset fast -crf 20 -movflags +faststart -c:a copy "$output_file"
    mv "$output_file" "$input_file"
}

if [[ -z "$1" || "$1" == "--sound" || "$1" == "--fullscreen-sound" || "$1" == "--fullscreen" || "$1" == "--gif" ]]; then
    if [[ "$1" == "--sound" || "$1" == "--fullscreen-sound" || "$1" == "--fullscreen" ]]; then
        if [[ "$XDG_SESSION_TYPE" == "wayland" && ("$XDG_CURRENT_DESKTOP" == "GNOME" || "$XDG_CURRENT_DESKTOP" == "KDE") ]]; then
            printf "\e[30m\e[46m$1\e[0m"
            printf "\e[1;32m is only for X11 or wlroots Compositors as its not needed. \e[0m\n"
            notify-send "This Argument is only for X11 or wlroots Compositors" "As its not needed." -a "E-Z Recorder"
            sleep 2
            exit 1
        fi
    fi
else
    if [[ "$XDG_SESSION_TYPE" == "wayland" && ("$XDG_CURRENT_DESKTOP" == "GNOME" || "$XDG_CURRENT_DESKTOP" == "KDE") ]]; then
        echo "Invalid argument: $1"
        notify-send "Invalid argument: $1" -a "E-Z Recorder"
        exit 1
    fi
fi

if [[ "$1" == "--gif" ]]; then
    touch "$gif_pending_file"
fi

if [[ "$XDG_SESSION_TYPE" == "wayland" && ("$XDG_CURRENT_DESKTOP" == "GNOME" || "$XDG_CURRENT_DESKTOP" == "KDE") ]]; then
    if pgrep -x "kooha" > /dev/null; then
        echo "Kooha is already running."
        echo "For the Videos to Upload, Simply just Close the Window."
        notify-send "Kooha is already running." -a "E-Z Recorder"
        exit 1
    fi
    echo $(date +%s) > "$(eval echo $kooha_last_time)"
    mkdir -p "$(eval echo $kooha_dir)"
    kooha &
    kooha_pid=$!
    wait $kooha_pid
else
    if [[ "$XDG_SESSION_TYPE" == "x11" ]]; then
        if pgrep ffmpeg > /dev/null; then
            if [[ -f "$gif_pending_file" || "$1" == "--gif" ]]; then
                [[ "$endnotif" == true ]] && notify-send -t 5000 "Recording is being converted to GIF" "Please Wait.." -a "E-Z Recorder" &
                pkill ffmpeg &
                wait
                sleep 1.5
                video_file=$(ls -t recording_*.mp4 | head -n 1)
                gif_file=$(gif "$video_file")
                upload "$gif_file" "--gif"
            else
                [[ "$endnotif" == true ]] && notify-send -t 2000 "Recording Stopped" "Stopped" -a "E-Z Recorder" &
                pkill ffmpeg &
                wait
                sleep 1.5
                video_file=$(ls -t recording_*.mp4 | head -n 1)
                upload "$video_file"
            fi
        else
            if [[ "$1" == "--sound" ]]; then
                [[ "$startnotif" == true ]] && notify-send "Screen Snip Recording" "Select the region to Start" -a "E-Z Recorder"
                region=$(slop -f "%x,%y %w,%h")
                if [[ -z "$region" ]]; then
                    notify-send "Recording Canceling" 'Canceled' -a "E-Z Recorder"
                    exit 1
                fi
                IFS=', ' read -r x y width height <<< "$region"
                ffmpeg -video_size "${width}x${height}" -framerate $fps -f x11grab -i $DISPLAY+"${x},${y}" -f pulse -i "$(getaudiooutput)" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v $encoder -preset fast -crf 20 -pix_fmt $pixelformat -movflags +faststart -c:a aac -b:a 128k './recording_'"$(getdate)"'.mp4' & disown
            elif [[ "$1" == "--fullscreen-sound" ]]; then
                if [[ "$save" == true ]]; then
                    [[ "$startnotif" == true ]] && notify-send "Starting Recording" 'recording_'"$(getdate)"'.mp4' -a "E-Z Recorder"
                else
                    [[ "$startnotif" == true ]] && notify-send "Starting Recording" 'Started' -a "E-Z Recorder"
                fi
                ffmpeg -video_size $(getactivemonitor) -framerate $fps -f x11grab -i $DISPLAY -f pulse -i "$(getaudiooutput)" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v $encoder -preset fast -crf 20 -pix_fmt $pixelformat -movflags +faststart -c:a aac -b:a 128k './recording_'"$(getdate)"'.mp4' & disown
            elif [[ "$1" == "--fullscreen" ]]; then
                if [[ "$save" == true ]]; then
                    [[ "$startnotif" == true ]] && notify-send "Starting Recording" 'recording_'"$(getdate)"'.mp4' -a "E-Z Recorder"
                else
                    [[ "$startnotif" == true ]] && notify-send "Starting Recording" 'Started' -a "E-Z Recorder"
                fi
                ffmpeg -video_size $(getactivemonitor) -framerate $fps -f x11grab -i $DISPLAY -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v $encoder -preset fast -crf 20 -pix_fmt $pixelformat -movflags +faststart './recording_'"$(getdate)"'.mp4' & disown
            elif [[ "$1" == "--gif" ]]; then
                touch "$gif_pending_file"
                [[ "$startnotif" == true ]] && notify-send "GIF Screen Snip Recording" "Select the region to Start" -a "E-Z Recorder"
                region=$(slop -f "%x,%y %w,%h")
                if [[ -z "$region" ]]; then
                    notify-send "Recording Canceling" 'Canceled' -a "E-Z Recorder"
                    exit 1
                fi
                IFS=', ' read -r x y width height <<< "$region"
                ffmpeg -video_size "${width}x${height}" -framerate $fps -f x11grab -i $DISPLAY+"${x},${y}" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v $encoder -preset fast -crf 20 -pix_fmt $pixelformat -movflags +faststart './recording_'"$(getdate)"'.mp4' & disown
            else
                [[ "$startnotif" == true ]] && notify-send "Screen Snip Recording" "Select the region to Start" -a "E-Z Recorder"
                region=$(slop -f "%x,%y %w,%h")
                if [[ -z "$region" ]]; then
                    notify-send "Recording Canceling" 'Canceled' -a "E-Z Recorder"
                    exit 1
                fi
                IFS=', ' read -r x y width height <<< "$region"
                ffmpeg -video_size "${width}x${height}" -framerate $fps -f x11grab -i $DISPLAY+"${x},${y}" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v $encoder -preset fast -crf 20 -pix_fmt $pixelformat -movflags +faststart './recording_'"$(getdate)"'.mp4' & disown
            fi
        fi
    else
        if pgrep wf-recorder > /dev/null; then
            if [[ -f "$gif_pending_file" || "$1" == "--gif" ]]; then
                [[ "$endnotif" == true ]] && notify-send -t 5000 "Recording is being converted to GIF" "Please Wait.." -a "E-Z Recorder" &
                pkill wf-recorder &
                wait
                sleep 1.5
                video_file=$(ls -t recording_*.mp4 | head -n 1)
                gif_file=$(gif "$video_file")
                upload "$gif_file" "--gif"
            else
                [[ "$endnotif" == true ]] && notify-send -t 2000 "Recording Stopped" "Stopped" -a "E-Z Recorder" &
                pkill wf-recorder &
                wait
                sleep 1.5
                video_file=$(ls -t recording_*.mp4 | head -n 1)
                [[ "$colorworkaround" == true ]] && post_process_video "$video_file"
                upload "$video_file"
            fi
        else
            if [[ "$1" == "--sound" ]]; then
                [[ "$startnotif" == true ]] && notify-send "Screen Snip Recording" "Select the region to Start" -a "E-Z Recorder"
                region=$(slurp)
                if [[ -z "$region" ]]; then
                    notify-send "Recording Canceling" 'Canceled' -a "E-Z Recorder"
                    exit 1
                fi
                wf-recorder --pixel-format $pixelformat -c "$encoder" -f './recording_'"$(getdate)"'.mp4' --geometry "$region" --audio="$(getaudiooutput)" -r $fps & disown
            elif [[ "$1" == "--fullscreen-sound" ]]; then
                if [[ "$save" == true ]]; then
                    [[ "$startnotif" == true ]] && notify-send "Starting Recording" 'recording_'"$(getdate)"'.mp4' -a "E-Z Recorder"
                else
                    [[ "$startnotif" == true ]] && notify-send "Starting Recording" 'Started' -a "E-Z Recorder"
                fi
                wf-recorder -o $(getactivemonitor) --pixel-format $pixelformat -c "$encoder" -f './recording_'"$(getdate)"'.mp4' --audio="$(getaudiooutput)" -r $fps & disown
            elif [[ "$1" == "--fullscreen" ]]; then
                if [[ "$save" == true ]]; then
                    [[ "$startnotif" == true ]] && notify-send "Starting Recording" 'recording_'"$(getdate)"'.mp4' -a "E-Z Recorder"
                else
                    [[ "$startnotif" == true ]] && notify-send "Starting Recording" 'Started' -a "E-Z Recorder"
                fi
                wf-recorder -o $(getactivemonitor) --pixel-format $pixelformat -c "$encoder" -f './recording_'"$(getdate)"'.mp4' -r $fps & disown
            elif [[ "$1" == "--gif" ]]; then
                touch "$gif_pending_file"
                [[ "$startnotif" == true ]] && notify-send "GIF Screen Snip Recording" "Select the region to Start" -a "E-Z Recorder"
                region=$(slurp)
                if [[ -z "$region" ]]; then
                    notify-send "Recording Canceling" 'Canceled' -a "E-Z Recorder"
                    exit 1
                fi
                wf-recorder --pixel-format $pixelformat -c "$encoder" -f './recording_'"$(getdate)"'.mp4' --geometry "$region" -r $fps & disown
            else
                [[ "$startnotif" == true ]] && notify-send "Screen Snip Recording" "Select the region to Start" -a "E-Z Recorder"
                region=$(slurp)
                if [[ -z "$region" ]]; then
                    notify-send "Recording Canceling" 'Canceled' -a "E-Z Recorder"
                    exit 1
                fi
                wf-recorder --pixel-format $pixelformat -c "$encoder" -f './recording_'"$(getdate)"'.mp4' --geometry "$region" -r $fps & disown
            fi
        fi
    fi
fi

if [[ "$XDG_SESSION_TYPE" == "wayland" && ("$XDG_CURRENT_DESKTOP" == "GNOME" || "$XDG_CURRENT_DESKTOP" == "KDE") ]]; then
    if [[ -z "$new_files" ]]; then
        echo "NOTE: If you Recorded something in Kooha Before Closing, and the Recording doesn't try to upload"
        echo "Then Kooha's Directory Location is mismatched with the config's kooha directory."
    fi

    if [[ "$save" == true ]]; then
        last_upload_time=$(cat "$(eval echo $kooha_last_time)" 2>/dev/null || echo 0)
        new_files=$(find "$(eval echo $kooha_dir)" -type f -newer "$(eval echo $kooha_last_time)" | sort -n)
        if [[ -n "$new_files" ]]; then
            file_count=0
            for file_path in $new_files; do
                ((file_count++))
                if [[ -f "$file_path" && -s "$file_path" ]]; then
                    if [[ "$colorworkaround" == true && "${file_path##*.}" != "gif" ]]; then
                        post_process_video "$file_path"
                    fi

                    if [[ -f "$file_path" ]]; then
                        if [[ "$1" == "--gif" || "${file_path##*.}" == "gif" ]]; then
                            gif_file=$(gif "$file_path")
                            upload "$gif_file" "--gif"
                            if [[ $(echo $new_files | wc -w) -gt 1 ]]; then
                                notify-send -i link "#$file_count GIF Recording uploaded" "$file_count of $(echo $new_files | wc -w) URLs have been Copied." -a "E-Z Recorder"
                            fi
                        else
                            upload "$file_path"
                            if [[ $(echo $new_files | wc -w) -gt 1 ]]; then
                                notify-send -i link "#$file_count Recording uploaded" "$file_count of $(echo $new_files | wc -w) URLs have been Copied." -a "E-Z Recorder"
                            fi
                        fi
                    else
                        echo "Error: Encoded file not found: $file_path"
                        notify-send "Error: Encoded file not found: $file_path" -a "E-Z Recorder"
                    fi
                fi
                if (( file_count % 2 == 0 )); then
                    sleep 4
                fi
            done
            if [[ $(echo $new_files | wc -w) -eq 1 ]]; then
                if [[ "$1" == "--gif" || "${file_path##*.}" == "gif" ]]; then
                    notify-send -i link "GIF URL copied to clipboard" -a "E-Z Recorder"
                else
                    notify-send -i link "Video URL copied to clipboard" -a "E-Z Recorder"
                fi
            fi
            rm "$(eval echo $kooha_last_time)"
        else
            notify-send "Recording Aborted" 'Aborted' -a "E-Z Recorder"
        fi
    fi

    if [[ "$save" == false ]]; then
        last_upload_time=$(cat "$(eval echo $kooha_last_time)" 2>/dev/null || echo 0)
        new_files=$(find "$(eval echo $kooha_dir)" -type f -newer "$(eval echo $kooha_last_time)" | sort -n)
        if [[ -n "$new_files" ]]; then
            file_count=0
            for file_path in $new_files; do
                ((file_count++))
                if [[ -f "$file_path" && -s "$file_path" ]]; then
                    if [[ "$colorworkaround" == true && "${file_path##*.}" != "gif" ]]; then
                        post_process_video "$file_path"
                    fi

                    if [[ -f "$file_path" ]]; then
                        if [[ "$1" == "--gif" || "${file_path##*.}" == "gif" ]]; then
                            gif_file=$(gif "$file_path")
                            upload "$gif_file" "--gif"
                            if [[ $(echo $new_files | wc -w) -gt 1 ]]; then
                                notify-send -i link "#$file_count GIF Recording uploaded" "$file_count of $(echo $new_files | wc -w) URLs have been Copied" -a "E-Z Recorder"
                            fi
                        else
                            upload "$file_path"
                            if [[ $(echo $new_files | wc -w) -gt 1 ]]; then
                                notify-send -i link "#$file_count Recording uploaded" "$file_count of $(echo $new_files | wc -w) URLs have been Copied." -a "E-Z Recorder"
                            fi
                        fi
                    else
                        echo "Error: Encoded file not found: $file_path"
                        notify-send "Error: Encoded file not found: $file_path" -a "E-Z Recorder"
                    fi
                fi
                if (( file_count % 2 == 0 )); then
                    sleep 3.5
                fi
            done
            if [[ $(echo $new_files | wc -w) -eq 1 ]]; then
                if [[ "$1" == "--gif" || "${file_path##*.}" == "gif" ]]; then
                    notify-send -i link "GIF URL copied to clipboard" -a "E-Z Recorder"
                else
                    notify-send -i link "Video URL copied to clipboard" -a "E-Z Recorder"
                fi
            fi
            rm "$(eval echo $kooha_last_time)"
        else
            notify-send "Recording Aborted" 'Aborted' -a "E-Z Recorder"
        fi
        recording_count=$(find "$(eval echo $kooha_dir)" -type f \( -name "*.mp4" -o -name "*.webm" -o -name "*.mkv" -o -name "*.gif" \) | wc -l)
        if (( recording_count <= 1 )); then
            rm -rf "$(eval echo $kooha_dir)"
        fi
    fi
fi

exit 0

