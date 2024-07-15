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

show_help() {
    echo "Usage: e-z-recorder.sh [ARGUMENTS]"
    echo ""
    echo "Arguments:"
    echo "  --help                 Show this help message and exit"
    echo "  --abort                Abort the current recording"
    echo "  --sound                Record a selected region with sound"
    echo "  --fullscreen           Record the entire screen without sound"
    echo "  --fullscreen-sound     Record the entire screen with sound"
    echo "  --gif                  Record a selected region and convert to GIF"
    echo "  --config               Open the configuration file in the default text editor"
    echo "  --config-reinstall     Reinstall the configuration file with default settings"
    echo ""
}

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
    exit 0
fi

config_file="$HOME/.config/e-z-recorder/config.conf"

create_default_config() {
    mkdir -p "$(dirname "$config_file")"
    cat <<EOL > "$config_file"
auth=""
url="https://api.e-z.host/files"
fps=60
save=false
failsave=true
gif_pending_file="/tmp/gif_pending"
EOL
    echo "Default Configuration file created."
    printf "\e[30m\e[46m $config_file \e[0m\n"
    printf "\e[1;34mEdit the configuration file to set your E-Z API KEY.\e[0m\n"
    printf "\e[1;31mOtherwise, the script will not work.\e[0m\n"
}

if [[ ! -f "$config_file" ]]; then
    create_default_config
    exit 0
fi

source "$config_file"

if [[ "$1" == "--config" ]]; then
    if command -v xdg-open > /dev/null; then
        xdg-open "$config_file"
    elif command -v open > /dev/null; then
        open "$config_file"
    elif command -v nvim > /dev/null; then
        nvim "$config_file"
    elif command -v nano > /dev/null; then
        nano "$config_file"
    else
        echo "No suitable text editor found. Please open $config_file manually."
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

if [[ -z "$auth" ]]; then
    echo "API Key is not set."
    echo "Edit the configuration file with --config to add your E-Z API KEY."
    notify-send "API Key is not added." 'Edit the configuration file to add your E-Z API KEY.' -a "e-z-recorder.sh"
    exit 1
fi

if [[ -z "$url" ]]; then
    echo "URL is not set."
    echo "Edit the configuration file with --config to add E-Z's API URL."
    notify-send "URL is not set." 'Edit the config file to add E-Z's API URL.' -a "e-z-recorder.sh"
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
        active_monitor=$(xrandr --query | grep " connected" | grep -o '^[^ ]*')
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

upload() {
    local file=$1
    local is_gif=$2
    response_file="/tmp/uploadvideo.json"

    if [[ ! -f "$file" ]]; then
        notify-send "Error: File not found: $file" -a "e-z-recorder.sh"
        exit 1
    fi

    if [[ "$file" == *.mp4 ]]; then
        content_type="video/mp4"
    elif [[ "$file" == *.gif ]]; then
        content_type="image/gif"
    else
        content_type="application/octet-stream"
    fi

    curl -X POST -F "file=@${file};type=${content_type}" -H "key: ${auth}" -v "${url}" 2>/dev/null > $response_file

    if ! jq -e . >/dev/null 2>&1 < $response_file; then
        notify-send "Error occurred while uploading. Please try again later." -a "e-z-recorder.sh"
        rm $response_file
        [[ "$failsave" == true && "$1" != "--abort" ]] && mkdir -p ~/Videos/e-zfailed && mv "$file" ~/Videos/e-zfailed/
        [[ "$is_gif" == "--gif" ]] && rm "$gif_pending_file"
        exit 1
    fi

    success=$(jq -r ".success" < $response_file)
    if [[ "$success" != "true" ]] || [[ "$success" == "null" ]]; then
        error=$(jq -r ".error" < $response_file)
        if [[ "$error" == "null" ]]; then
            notify-send "Error occurred while uploading. Please try again later." -a "e-z-recorder.sh"
        else
            notify-send "Error: $error" -a "e-z-recorder.sh"
        fi
        [[ "$failsave" == true && "$1" != "--abort" ]] && mkdir -p ~/Videos/e-zfailed && mv "$file" ~/Videos/e-zfailed/
        [[ "$is_gif" == "--gif" ]] && rm "$gif_pending_file"
        rm $response_file
        exit 1
    fi

    file_url=$(jq -r ".imageUrl" < $response_file)
    if [[ "$file_url" != "null" ]]; then
        if [[ "$XDG_SESSION_TYPE" == "x11" ]]; then
            echo "$file_url" | xclip -selection clipboard
        else
            echo "$file_url" | wl-copy
        fi
        if [[ "$is_gif" == "--gif" ]]; then
            notify-send -i link "GIF URL copied to clipboard" -a "e-z-recorder.sh"
            rm "$gif_pending_file"
        else
            notify-send -i link "Video URL copied to clipboard" -a "e-z-recorder.sh"
        fi
        if [[ "$save" == false ]]; then
            rm "$file"
        fi
    else
        notify-send "Error: File URL is null" -a "e-z-recorder.sh"
    fi
    rm $response_file
}

if [[ "$save" == true ]]; then
    mkdir -p "$(xdg-user-dir VIDEOS)"
    cd "$(xdg-user-dir VIDEOS)" || exit
else
    cd /tmp || exit
fi

if [[ "$1" == "--abort" ]]; then
    if [[ "$XDG_SESSION_TYPE" == "x11" ]]; then
        if pgrep ffmpeg > /dev/null; then
            notify-send "Recording Aborted" "The upload has been canceled." -a 'e-z-recorder.sh'
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
            notify-send "No Recording in Progress" "There is no recording to cancel." -a 'e-z-recorder.sh'
            exit 0
        fi
    else
        if pgrep wf-recorder > /dev/null; then
            notify-send "Recording Aborted" "The upload has been canceled." -a 'e-z-recorder.sh'
            pkill wf-recorder
            if [[ -f "$gif_pending_file" ]]; then
                rm "$gif_pending_file"
            fi
            if [[ "$save" == false ]]; then
                video_file=$(ls -t recording_*.mp4 | head -n 1)
                rm "$video_file"
            fi
            exit 0
        else
            notify-send "No Recording in Progress" "There is no recording to cancel." -a 'e-z-recorder.sh'
            exit 0
        fi
    fi
fi

if [[ "$XDG_SESSION_TYPE" == "x11" ]]; then
    if pgrep ffmpeg > /dev/null; then
        if [[ -f "$gif_pending_file" || "$1" == "--gif" ]]; then
            notify-send -t 5000 "Recording is being converted to GIF" "Please Wait.." -a 'e-z-recorder.sh' &
            pkill ffmpeg &
            wait
            sleep 1.5
            video_file=$(ls -t recording_*.mp4 | head -n 1)
            gif_file=$(gif "$video_file")
            upload "$gif_file" "--gif"
        else
            notify-send -t 2000 "Recording Stopped" "Stopped" -a 'e-z-recorder.sh' &
            pkill ffmpeg &
            wait
            sleep 1.5
            video_file=$(ls -t recording_*.mp4 | head -n 1)
            upload "$video_file"
        fi
    else
        if [[ "$1" == "--sound" ]]; then
            notify-send "Screen Snip Recording" "Select the region to Start" -a 'e-z-recorder.sh'
            region=$(slop -f "%x,%y %w,%h")
            if [[ -z "$region" ]]; then
                notify-send "Recording Canceling" 'Canceled' -a 'e-z-recorder.sh'
                exit 1
            fi
            IFS=', ' read -r x y width height <<< "$region"
            ffmpeg -video_size "${width}x${height}" -framerate $fps -f x11grab -i $DISPLAY+"${x},${y}" -f pulse -i "$(getaudiooutput)" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p -movflags +faststart -c:a aac -b:a 128k './recording_'"$(getdate)"'.mp4' & disown
        elif [[ "$1" == "--fullscreen-sound" ]]; then
            if [[ "$save" == true ]]; then
                notify-send "Starting Recording" 'recording_'"$(getdate)"'.mp4' -a 'e-z-recorder.sh'
            else
                notify-send "Starting Recording" 'Started' -a 'e-z-recorder.sh'
            fi
            ffmpeg -video_size $(xdpyinfo | grep dimensions | awk '{print $2}') -framerate $fps -f x11grab -i $DISPLAY -f pulse -i "$(getaudiooutput)" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p -movflags +faststart -c:a aac -b:a 128k './recording_'"$(getdate)"'.mp4' & disown
        elif [[ "$1" == "--fullscreen" ]]; then
            if [[ "$save" == true ]]; then
                notify-send "Starting Recording" 'recording_'"$(getdate)"'.mp4' -a 'e-z-recorder.sh'
            else
                notify-send "Starting Recording" 'Started' -a 'e-z-recorder.sh'
            fi
            ffmpeg -video_size $(xdpyinfo | grep dimensions | awk '{print $2}') -framerate $fps -f x11grab -i $DISPLAY -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p -movflags +faststart './recording_'"$(getdate)"'.mp4' & disown
        elif [[ "$1" == "--gif" ]]; then
            touch "$gif_pending_file"
            notify-send "GIF Screen Snip Recording" "Select the region to Start" -a 'e-z-recorder.sh'
            region=$(slop -f "%x,%y %w,%h")
            if [[ -z "$region" ]]; then
                notify-send "Recording Canceling" 'Canceled' -a 'e-z-recorder.sh'
                exit 1
            fi
            IFS=', ' read -r x y width height <<< "$region"
            ffmpeg -video_size "${width}x${height}" -framerate $fps -f x11grab -i $DISPLAY+"${x},${y}" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p -movflags +faststart './recording_'"$(getdate)"'.mp4' & disown
        else
            notify-send "Screen Snip Recording" "Select the region to Start" -a 'e-z-recorder.sh'
            region=$(slop -f "%x,%y %w,%h")
            if [[ -z "$region" ]]; then
                notify-send "Recording Canceling" 'Canceled' -a 'e-z-recorder.sh'
                exit 1
            fi
            IFS=', ' read -r x y width height <<< "$region"
            ffmpeg -video_size "${width}x${height}" -framerate $fps -f x11grab -i $DISPLAY+"${x},${y}" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p -movflags +faststart './recording_'"$(getdate)"'.mp4' & disown
        fi
    fi
else
    if pgrep wf-recorder > /dev/null; then
        if [[ -f "$gif_pending_file" || "$1" == "--gif" ]]; then
            notify-send -t 5000 "Recording is being converted to GIF" "Please Wait.." -a 'e-z-recorder.sh' &
            pkill wf-recorder &
            wait
            sleep 1.5
            video_file=$(ls -t recording_*.mp4 | head -n 1)
            gif_file=$(gif "$video_file")
            upload "$gif_file" "--gif"
        else
            notify-send -t 2000 "Recording Stopped" "Stopped" -a 'e-z-recorder.sh' &
            pkill wf-recorder &
            wait
            sleep 1.5
            video_file=$(ls -t recording_*.mp4 | head -n 1)
            upload "$video_file"
        fi
    else
        if [[ "$1" == "--sound" ]]; then
            notify-send "Screen Snip Recording" "Select the region to Start" -a 'e-z-recorder.sh'
            region=$(slurp)
            if [[ -z "$region" ]]; then
                notify-send "Recording Canceling" 'Canceled' -a 'e-z-recorder.sh'
                exit 1
            fi
            wf-recorder --pixel-format yuv420p -f './recording_'"$(getdate)"'.mp4' --geometry "$region" --audio="$(getaudiooutput)" -r $fps & disown
        elif [[ "$1" == "--fullscreen-sound" ]]; then
            if [[ "$save" == true ]]; then
                notify-send "Starting Recording" 'recording_'"$(getdate)"'.mp4' -a 'e-z-recorder.sh'
            else
                notify-send "Starting Recording" 'Started' -a 'e-z-recorder.sh'
            fi
            wf-recorder -o $(getactivemonitor) --pixel-format yuv420p -f './recording_'"$(getdate)"'.mp4' --audio="$(getaudiooutput)" -r $fps & disown
        elif [[ "$1" == "--fullscreen" ]]; then
            if [[ "$save" == true ]]; then
                notify-send "Starting Recording" 'recording_'"$(getdate)"'.mp4' -a 'e-z-recorder.sh'
            else
                notify-send "Starting Recording" 'Started' -a 'e-z-recorder.sh'
            fi
            wf-recorder -o $(getactivemonitor) --pixel-format yuv420p -f './recording_'"$(getdate)"'.mp4' -r $fps & disown
        elif [[ "$1" == "--gif" ]]; then
            touch "$gif_pending_file"
            notify-send "GIF Screen Snip Recording" "Select the region to Start" -a 'e-z-recorder.sh'
            region=$(slurp)
            if [[ -z "$region" ]]; then
                notify-send "Recording Canceling" 'Canceled' -a 'e-z-recorder.sh'
                exit 1
            fi
            wf-recorder --pixel-format yuv420p -f './recording_'"$(getdate)"'.mp4' --geometry "$region" -r $fps & disown
        else
            notify-send "Screen Snip Recording" "Select the region to Start" -a 'e-z-recorder.sh'
            region=$(slurp)
            if [[ -z "$region" ]]; then
                notify-send "Recording Canceling" 'Canceled' -a 'e-z-recorder.sh'
                exit 1
            fi
            wf-recorder --pixel-format yuv420p -f './recording_'"$(getdate)"'.mp4' --geometry "$region" -r $fps & disown
        fi
    fi
fi