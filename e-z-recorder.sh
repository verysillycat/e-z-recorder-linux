#!/bin/bash

auth=""
url="https://api.e-z.host/files"
save=false

getdate() {
    date '+%Y-%m-%d_%H.%M.%S'
}
getaudiooutput() {
    pactl list sources | grep 'Name' | grep 'monitor' | cut -d ' ' -f2
}
getactivemonitor() {
    window=$(xdotool getactivewindow)
    active_monitor=$(xrandr --listmonitors | grep "$(xdotool getwindowgeometry --shell $window | grep SCREEN | cut -d '=' -f2)" | awk '{print $4}')
    echo $active_monitor
}

upload() {
    local video_file=$1
    response_file="/tmp/uploadvideo.json"

    if [[ ! -f "$video_file" ]]; then
        notify-send "Error: Video file not found: $video_file" -a "record-script.sh"
        exit 1
    fi
    curl -X POST -F "file=@${video_file}" -H "key: ${auth}" -v "${url}" 2>/dev/null > $response_file

    echo "Server response:"
    cat $response_file

    if ! jq -e . >/dev/null 2>&1 < $response_file; then
        notify-send "Error occurred while uploading. Please try again later." -a "record-script.sh"
        rm $response_file
        exit 1
    fi

    success=$(jq -r ".success" < $response_file)
    if [[ "$success" != "true" ]] || [[ "$success" == "null" ]]; then
        error=$(jq -r ".error" < $response_file)
        if [[ "$error" == "null" ]]; then
            notify-send "Error occurred while uploading. Please try again later." -a "record-script.sh"
        else
            notify-send "Error: $error" -a "record-script.sh"
        fi
        rm $response_file
        exit 1
    fi

    file_url=$(jq -r ".imageUrl" < $response_file)
    if [[ "$file_url" != "null" ]]; then
        echo "$file_url" | xclip -sel c
        notify-send "Video URL copied to clipboard" -a "record-script.sh"
        if [[ "$save" == false ]]; then
            rm "$video_file"
        fi
    else
        notify-send "Error: File URL is null" -a "record-script.sh"
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
    notify-send -t 2000 "Recording Stopped" "Stopped" -a 'record-script.sh' &
    pkill wf-recorder &
    wait
    sleep 1.5
    video_file=$(ls -t recording_*.mp4 | head -n 1)
    upload "$video_file"
else
    if [[ "$save" == true ]]; then
        notify-send "Starting recording" 'recording_'"$(getdate)"'.mp4' -a 'record-script.sh'
    else
        notify-send "Starting recording" 'Started' -a 'record-script.sh'
    fi
    if [[ "$1" == "--sound" ]]; then
        wf-recorder --pixel-format yuv420p -f './recording_'"$(getdate)"'.mp4' --geometry "$(slurp)" --audio="$(getaudiooutput)" & disown
    elif [[ "$1" == "--fullscreen-sound" ]]; then
        wf-recorder -o $(getactivemonitor) --pixel-format yuv420p -f './recording_'"$(getdate)"'.mp4' --audio="$(getaudiooutput)" & disown
    elif [[ "$1" == "--fullscreen" ]]; then
        wf-recorder -o $(getactivemonitor) --pixel-format yuv420p -f './recording_'"$(getdate)"'.mp4' & disown
    else
        wf-recorder --pixel-format yuv420p -f './recording_'"$(getdate)"'.mp4' --geometry "$(slurp)" & disown
    fi
fi