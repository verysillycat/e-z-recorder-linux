#!/bin/bash

auth=""
url="https://api.e-z.host/files"
save=false

gif_pending_file="/tmp/gif_pending"

if [[ -z "$url" ]]; then
    notify-send "URL is not set." 'Did you copy the Script Correctly?' -a "e-z-recorder.sh"
    exit 1
fi

if [ "$XDG_SESSION_TYPE" = "x11" ]; then
    echo "Error: wf-recorder is Wayland Only."
    notify-send "This script is not compatible with X11." -a "e-z-recorder.sh"
    exit 1
fi

getdate() {
    date '+%Y-%m-%d_%H.%M.%S'
}
getaudiooutput() {
    pactl list sources | grep 'Name' | grep 'monitor' | cut -d ' ' -f2
}
getactivemonitor() {
    active_monitor=$(wlr-randr --json | jq -r '.[] | select(.enabled == true) | .name')
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
    curl -X POST -F "file=@${file}" -H "key: ${auth}" -v "${url}" 2>/dev/null > $response_file

    cat $response_file

    if ! jq -e . >/dev/null 2>&1 < $response_file; then
        notify-send "Error occurred while uploading. Please try again later." -a "e-z-recorder.sh"
        rm $response_file
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
        rm $response_file
        exit 1
    fi

    file_url=$(jq -r ".imageUrl" < $response_file)
    if [[ "$file_url" != "null" ]]; then
        echo "$file_url" | wl-copy
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
        notify-send "Screen Snip Recording" "Select the region to record" -a 'e-z-recorder.sh'
        region=$(slurp)
        if [[ -z "$region" ]]; then
            notify-send "Recording Aborted" 'Aborted' -a 'e-z-recorder.sh'
            exit 1
        fi
        wf-recorder --pixel-format yuv420p -f './recording_'"$(getdate)"'.mp4' --geometry "$region" --audio="$(getaudiooutput)" & disown
    elif [[ "$1" == "--fullscreen-sound" ]]; then
        if [[ "$save" == true ]]; then
            notify-send "Starting Recording" 'recording_'"$(getdate)"'.mp4' -a 'e-z-recorder.sh'
        else
            notify-send "Starting Recording" 'Started' -a 'e-z-recorder.sh'
        fi
        wf-recorder -o $(getactivemonitor) --pixel-format yuv420p -f './recording_'"$(getdate)"'.mp4' --audio="$(getaudiooutput)" & disown
    elif [[ "$1" == "--fullscreen" ]]; then
        if [[ "$save" == true ]]; then
            notify-send "Starting Recording" 'recording_'"$(getdate)"'.mp4' -a 'e-z-recorder.sh'
        else
            notify-send "Starting Recording" 'Started' -a 'e-z-recorder.sh'
        fi
        wf-recorder -o $(getactivemonitor) --pixel-format yuv420p -f './recording_'"$(getdate)"'.mp4' & disown
    elif [[ "$1" == "--gif" ]]; then
        touch "$gif_pending_file"
        notify-send "GIF Screen Snip Recording" "Select the region to record" -a 'e-z-recorder.sh'
        region=$(slurp)
        if [[ -z "$region" ]]; then
            notify-send "Recording Aborted" 'Aborted' -a 'e-z-recorder.sh'
            exit 1
        fi
        wf-recorder --pixel-format yuv420p -f './recording_'"$(getdate)"'.mp4' --geometry "$region" & disown
    else
        notify-send "Screen Snip Recording" "Select the region to record" -a 'e-z-recorder.sh'
        region=$(slurp)
        if [[ -z "$region" ]]; then
            notify-send "Recording Aborted" 'Aborted' -a 'e-z-recorder.sh'
            exit 1
        fi
        wf-recorder --pixel-format yuv420p -f './recording_'"$(getdate)"'.mp4' --geometry "$region" & disown
    fi
fi