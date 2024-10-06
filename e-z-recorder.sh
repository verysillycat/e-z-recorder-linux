#!/bin/bash

if [[ $EUID -eq 0 ]]; then
	echo -e "\e[31mThis script should not be run as root.\e[0m"
	sleep 1.8
	exit 1
fi

if [[ "$XDG_SESSION_TYPE" == "wayland" && ("$XDG_CURRENT_DESKTOP" == "GNOME" || "$XDG_CURRENT_DESKTOP" == "KDE" || "$XDG_CURRENT_DESKTOP" == "COSMIC") ]]; then
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

check_dependencies() {
	local missing_dependencies=()
	local dependencies=("jq" "curl")

	if [[ "$XDG_SESSION_TYPE" == "wayland" ]]; then
		if [[ "$XDG_CURRENT_DESKTOP" == "GNOME" || "$XDG_CURRENT_DESKTOP" == "KDE" || "$XDG_CURRENT_DESKTOP" == "COSMIC" ]]; then
			dependencies+=("wl-copy" "kooha")
		else
			dependencies+=("wl-copy" "slurp" "wlr-randr")
			if ! command -v "wf-recorder" &>/dev/null && ! command -v "wl-screenrec" &>/dev/null; then
				missing_dependencies+=("wf-recorder or wl-screenrec")
			fi
		fi
	else
		dependencies+=("xclip" "slop" "ffmpeg" "xdpyinfo")
	fi

	for dep in "${dependencies[@]}"; do
		if ! command -v "$dep" &>/dev/null; then
			missing_dependencies+=("$dep")
		fi
	done

	if [ ${#missing_dependencies[@]} -ne 0 ]; then
		local formatted_deps=$(
			IFS=,
			echo "${missing_dependencies[*]}"
		)
		formatted_deps=${formatted_deps//,/, }
		formatted_deps=${formatted_deps//wl-copy/wl-clipboard}
		formatted_deps=$(echo "$formatted_deps" | sed 's/, \([^,]*\)$/ \& \1/')
		echo -e "\e[31mMissing Dependencies: \033[37;7m${formatted_deps}\033[0m\e[0m"
		echo "These are the required dependencies, install them and try again."
		notify-send "Missing Dependencies" "${formatted_deps}" -a "E-Z Recorder"
		exit 1
	fi

}
check_dependencies
config_file="~/.config/e-z-recorder/config.conf"
default_config_content=$(
	cat <<EOL
# On Kooha, FPS, Encoder, Preset, CRF & Pixel Format don't work but you can change FPS on GUI Preferences.
## Aswell as the file extension, and directory in there.
auth=""
url="https://api.e-z.host/files"
fps=60
crf=20
preset=fast
pixelformat=yuv420p
encoder=libx264
save=false
failsave=true
colorworkaround=false
startnotif=true
endnotif=true

wlscreenrec=false
codec=auto
extpixelformat=nv12
bitrate="5 MB"

directory="~/Videos"
kooha_dir="~/Videos/Kooha"
gif_pending_file="/tmp/gif_pending"
kooha_last_time="~/.config/e-z-recorder/last_time"
EOL
)

if ! command -v "wf-recorder" &>/dev/null; then
	sed -i 's/^wlscreenrec=.*/wlscreenrec=true/' "$(eval echo $config_file)"
fi

create_default_config() {
	mkdir -p "$(dirname "$(eval echo $config_file)")"
	echo "$default_config_content" >"$(eval echo $config_file)"
	echo "Default Configuration file created."
	printf "\e[30m\e[46m $(eval echo $config_file) \e[0m\n"
	printf "\e[1;34mEdit the configuration file to set your E-Z API KEY.\e[0m\n"
	printf "\e[1;31mOtherwise, the script will not work.\e[0m\n"
}

update_config() {
	local config_path="$(eval echo $config_file)"
	local updated=false
	local new_config_content=""

	declare -A existing_config
	while IFS='=' read -r key value; do
		[[ "$key" =~ ^#.*$ || -z "$key" || -z "$value" ]] && continue
		existing_config["$key"]="$value"
	done < <(grep -v '^#' "$config_path")

	while IFS= read -r line; do
		if [[ "$line" =~ ^#.*$ || -z "$line" ]]; then
			new_config_content+="$line"$'\n'
			continue
		fi
		key=$(echo "$line" | cut -d '=' -f 1)
		if [[ -z "${existing_config[$key]}" ]]; then
			new_config_content+="$line"$'\n'
			updated=true
		else
			new_config_content+="$key=${existing_config[$key]}"$'\n'
			unset existing_config["$key"]
		fi
	done <<<"$default_config_content"

	for key in "${!existing_config[@]}"; do
		new_config_content+="$key=${existing_config[$key]}"$'\n'
	done

	new_config_content=$(echo -n "$new_config_content")
	if [[ "$new_config_content" != "$(cat "$config_path")" ]]; then
		echo "$new_config_content" >"$config_path"
		if [[ "$updated" == true ]]; then
			echo "Configuration updated."
			notify-send "Configuration updated" "New Options were added." -a "E-Z Recorder"
			exit 0
		fi
	fi
}

if [[ ! -f "$(eval echo $config_file)" ]]; then
	create_default_config
	exit 0
else
	update_config
fi

source "$(eval echo $config_file)"

if [[ "$1" == "--config" ]]; then
	if command -v xdg-open >/dev/null; then
		xdg-open "$(eval echo $config_file)"
	elif command -v open >/dev/null; then
		open "$(eval echo $config_file)"
	elif command -v nvim >/dev/null; then
		nvim "$(eval echo $config_file)"
	elif command -v nano >/dev/null; then
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

if [[ -z "$encoder" && ! ("$XDG_SESSION_TYPE" == "wayland" && ("$XDG_CURRENT_DESKTOP" == "GNOME" || "$XDG_CURRENT_DESKTOP" == "KDE" || "$XDG_CURRENT_DESKTOP" == "COSMIC")) ]]; then
	echo "Encoder is not set."
	echo "Edit the configuration file with --config to add the encoder."
	notify-send "Encoder is not set." 'Edit the config file to add the encoder.' -a "E-Z Recorder"
	exit 1
fi

if [[ -z "$pixelformat" && ! ("$XDG_SESSION_TYPE" == "wayland" && ("$XDG_CURRENT_DESKTOP" == "GNOME" || "$XDG_CURRENT_DESKTOP" == "KDE" || "$XDG_CURRENT_DESKTOP" == "COSMIC")) ]]; then
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
	elif [[ "$XDG_SESSION_TYPE" == "wayland" && "$XDG_CURRENT_DESKTOP" == "Hyprland" ]]; then
		active_monitor=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name')
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
	tput sc
	while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
		local temp=${spinstr#?}
		tput rc
		printf "\033[36;6m[${spinstr:0:1}]\033[0m"
		spinstr=$temp${spinstr%"$temp"}
		sleep $delay
	done
	tput rc
	tput el
	stty echo && tput cnorm
}

upload() {
	local file=$1
	local is_gif=$2
	response_file="/tmp/uploadvideo.json"
	upload_pid_file="$(eval echo $HOME/.config/e-z-recorder/.upload_pid)"

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

	if [[ -f "$upload_pid_file" ]]; then
		rm "$upload_pid_file"
	fi
	echo $$ >"$upload_pid_file"
	http_code=$(curl -X POST -F "file=@${file};type=${content_type}" -H "key: ${auth}" -w "%{http_code}" -o $response_file -s "${url}")

	if ! jq -e . >/dev/null 2>&1 <$response_file; then
		if [[ "$http_code" == "413" ]]; then
			notify-send "Recording too large." "Try a smaller recording or lower the settings." -a "E-Z Recorder"
		else
			notify-send "Error occurred on upload." "Status Code: $http_code Please try again later." -a "E-Z Recorder"
		fi
		rm $response_file
		[[ "$failsave" == true && "$1" != "--abort" && "$upload_mode" != true ]] && mkdir -p ~/Videos/e-zfailed && mv "$file" ~/Videos/e-zfailed/
		[[ "$is_gif" == "--gif" ]] && rm "$gif_pending_file"
		exit 1
	fi

	success=$(jq -r ".success" <$response_file)
	if [[ "$success" != "true" ]] || [[ "$success" == "null" ]]; then
		error=$(jq -r ".error" <$response_file)
		if [[ "$error" == "null" ]]; then
			if [[ "$http_code" == "413" ]]; then
				notify-send "Recording too large." "Try a smaller recording or lower the settings." -a "E-Z Recorder"
			else
				notify-send "Error occurred on upload." "Status Code: $http_code Please try again later." -a "E-Z Recorder"
			fi
		fi
		[[ "$failsave" == true && "$1" != "--abort" && "$upload_mode" != true ]] && mkdir -p ~/Videos/e-zfailed && mv "$file" ~/Videos/e-zfailed/
		[[ "$is_gif" == "--gif" ]] && rm "$gif_pending_file"
		[[ "$upload_mode" == true ]] && printf "\033[1;5;31mERROR:\033[0m Upload failed for file: \033[1;34m$filename\033[0m\n"
		rm $response_file
		if [[ -f "$upload_pid_file" ]]; then
			rm -f "$upload_pid_file"
		fi
		exit 1
	fi

	file_url=$(jq -r ".imageUrl" <$response_file)
	if [[ "$file_url" != "null" ]]; then
		if [[ "$save" == true && "$XDG_SESSION_TYPE" == "wayland" && ("$XDG_CURRENT_DESKTOP" == "GNOME" || "$XDG_CURRENT_DESKTOP" == "KDE" || "$XDG_CURRENT_DESKTOP" == "COSMIC") ]]; then
			echo $(date +%s) >"$(eval echo $kooha_last_time)"
		fi
		if [[ "$XDG_SESSION_TYPE" == "x11" ]]; then
			echo "$file_url" | xclip -selection clipboard
		else
			echo "$file_url" | wl-copy
		fi
		if [[ "$is_gif" == "--gif" || "$file" == *.gif ]]; then
			if [[ "$XDG_SESSION_TYPE" != "wayland" || ("$XDG_CURRENT_DESKTOP" != "GNOME" && "$XDG_CURRENT_DESKTOP" != "KDE") ]]; then
				notify-send "GIF URL copied to clipboard" -a "E-Z Recorder" -i link
			fi
			[[ "$is_gif" == "--gif" && "$1" != "-u" && "$1" != "upload" ]] && rm "$gif_pending_file"
		else
			if [[ "$XDG_SESSION_TYPE" != "wayland" || ("$XDG_CURRENT_DESKTOP" != "GNOME" && "$XDG_CURRENT_DESKTOP" != "KDE") ]]; then
				notify-send "Video URL copied to clipboard" -a "E-Z Recorder" -i link
			fi
		fi
		if [[ "$save" == false && "$upload_mode" != true ]]; then
			rm "$file"
		fi
	else
		notify-send "Error: File URL is null. HTTP Code: $http_code" -a "E-Z Recorder"
	fi
	if [[ "$upload_mode" != true ]]; then
		[[ -f $response_file ]] && rm $response_file
	fi
	if [[ -f "$upload_pid_file" ]]; then
		rm -f "$upload_pid_file"
	fi
}

abort_upload() {
	local check=false
	if [[ -f "$(eval echo $HOME/.config/e-z-recorder/.upload_pid)" ]]; then
		upload_pid=$(cat "$(eval echo $HOME/.config/e-z-recorder/.upload_pid)")
		if kill -0 "$upload_pid" 2>/dev/null; then
			pkill -P "$upload_pid"
			kill "$upload_pid"
			if [[ "$save" == false ]]; then
				if [[ "$XDG_SESSION_TYPE" == "wayland" && ("$XDG_CURRENT_DESKTOP" == "GNOME" || "$XDG_CURRENT_DESKTOP" == "KDE" || "$XDG_CURRENT_DESKTOP" == "COSMIC") ]]; then
					new_files=$(find "$(eval echo $kooha_dir)" -type f -newer "$(eval echo $kooha_last_time)" | sort -n)
					file_count=$(echo "$new_files" | wc -l)
					if ((file_count > 0)); then
						for file_path in $new_files; do
							rm "$file_path"
						done
					fi
				else
					video_file=$(ls -t recording_*.mp4 | head -n 1)
					rm "$video_file"
					gif_file=$(ls -t recording_*.gif | head -n 1)
					if [[ -f "$gif_pending_file" ]]; then
						rm "$gif_file"
					fi
				fi
			fi
			rm "$(eval echo $HOME/.config/e-z-recorder/.upload_pid)"
			[[ "$endnotif" == true ]] && notify-send "Recording Aborted" "The upload has been aborted." -a "E-Z Recorder"
			check=true
		fi
	elif [[ -f "$(eval echo $HOME/.config/e-z-recorder/.upload.lck)" ]]; then
		upload_lock_pid=$(cat "$(eval echo $HOME/.config/e-z-recorder/.upload.lck)")
		if kill -0 "$upload_lock_pid" 2>/dev/null; then
			pkill -P "$upload_lock_pid"
			kill "$upload_lock_pid"
			if [[ -f "$(eval echo $HOME/.config/e-z-recorder/.upload.lck)" ]]; then
				rm "$(eval echo $HOME/.config/e-z-recorder/.upload.lck)"
			fi
			notify-send "Recording(s) Aborted" "The upload has been aborted." -a "E-Z Recorder"
			check=true
		fi
	elif [[ -f "$gif_pending_file" ]]; then
		if pgrep -f "ffmpeg" >/dev/null; then
			gif_pid=$(pgrep -f "ffmpeg")
			kill "$gif_pid"
			[[ -f "$gif_pending_file" ]] && rm "$gif_pending_file"
			check=true
		fi
	fi
	if [[ "$check" == false ]]; then
		notify-send "No Recording in Progress" "There is no recording to abort." -a "E-Z Recorder"
		exit 0
	fi
}

if [[ "$1" == "upload" || "$1" == "-u" ]]; then
	upload_mode=true
	upload_lockfile="$(eval echo $HOME/.config/e-z-recorder/.upload.lck)"
	if [[ -f "$upload_lockfile" ]]; then
		other_pid=$(cat "$upload_lockfile")
		if kill -0 "$other_pid" 2>/dev/null; then
			echo "Another upload process is already running."
			read -p "Do you want to terminate the other upload process? (Y/N): " confirm
			if [[ "$confirm" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]; then
				kill "$other_pid"
			else
				echo "Waiting for the other upload process to finish..."
				while [[ -f "$upload_lockfile" ]] && kill -0 $(cat "$upload_lockfile") 2>/dev/null; do
					sleep 2.5
				done
			fi
		fi
	fi
	echo $$ >"$upload_lockfile"
	trap 'rm -f "$upload_lockfile"; exit' INT TERM EXIT

	shift
	files=("$@")
	if [[ ${#files[@]} -eq 0 ]]; then
		printf "\033[1m(?) \033[0mNo files specified for upload.\n"
		rm -f "$upload_lockfile"
		exit 1
	fi

	if [[ ${#files[@]} -ge 6 ]]; then
		printf "\033[1;5;31mERROR:\033[0m Too many files specified for upload. Please upload fewer than 6 files at a time.\n"
		rm -f "$upload_lockfile"
		exit 1
	fi

	valid_extensions=("mp4" "mkv" "webm" "gif")
	declare -A processed_files
	file_count=0

	for file in "${files[@]}"; do
		filename=$(basename "$file")
		extension="${filename##*.}"
		file_key="${file}:${filename}"

		if [[ -d "$file" || "$filename" == "$extension" ]]; then
			printf "\033[1;5;31mERROR:\033[0m \033[1;34m\033[7m$file\033[0m is a Directory or file that doesn't have a extension.\n"
			continue
		elif [[ ! " ${valid_extensions[@]} " =~ " ${extension} " ]]; then
			printf "\033[1;5;31mERROR:\033[0m Unsupported file type: \033[1;34m${filename%.*}\033[4m.${extension}\033[0m\n"
			continue
		fi

		if [[ -n "${processed_files[$file_key]}" ]]; then
			printf "\033[1;5;33m(!)\033[0m Skipping Duplicated Video: \033[1;34m\033[7m$filename\033[0m\n"
			continue
		fi

		if [[ ! -f "$file" ]]; then
			printf "\n\033[1m[1/4] \033[0mChecking if\033[1;34m $filename \033[0mexists\n"
			sleep 0.3
			printf "\033[1;5;31mERROR:\033[0m File not found:\033[1;34m $filename\033[0m\n"
			continue
		fi
		sleep 0.1
		printf "\n\033[1m[1/4] \033[0mChecking if\033[1;34m $filename \033[0mexists\n"
		sleep 0.2
		printf "\033[1m[2/4]\033[0m\033[1;34m $filename \033[0mfound\n"
		sleep 0.2
		printf "\033[1m[3/4]\033[0m Uploading:\033[1;34m $filename \033[0m"
		((file_count++))
		upload "$file" &
		spinner $!

		if [[ $? -eq 0 && -f /tmp/uploadvideo.json ]]; then
			upload_url=$(jq -r ".imageUrl" </tmp/uploadvideo.json)
			if [[ "$XDG_SESSION_TYPE" == "x11" ]]; then
				echo "$upload_url" | xclip -selection clipboard
			else
				echo "$upload_url" | wl-copy
			fi
			processed_files["$file_key"]=1
		fi
		if [[ $? -eq 0 && -n "$upload_url" ]]; then
			printf "\n\033[1m[4/4]\033[0m Upload successful: \033[1;32m%s\033[0m$upload_url\n\n"
			[[ -f /tmp/uploadvideo.json ]] && rm /tmp/uploadvideo.json
		else
			printf "\n\033[1;5;31mERROR:\033[0m Failed to upload file: \033[1;34m%s\033[0m$filename\n\n"
		fi
		if ((file_count % 3 == 0)); then
			sleep 3.8
		fi
	done

	rm -f "$upload_lockfile"
	trap - INT TERM EXIT
	exit 0
fi

if [[ "$save" == true && ! ("$XDG_SESSION_TYPE" == "wayland" && ("$XDG_CURRENT_DESKTOP" == "GNOME" || "$XDG_CURRENT_DESKTOP" == "KDE" || "$XDG_CURRENT_DESKTOP" == "COSMIC")) ]]; then
	mkdir -p "$(eval echo $directory)"
	cd "$(eval echo $directory)" || exit
else
	cd /tmp || exit
fi

if [[ "$1" == "--abort" ]]; then
	if [[ "$upload_mode" == true ]]; then
		abort_upload
	fi
	if [[ "$XDG_SESSION_TYPE" == "x11" ]]; then
		if pgrep ffmpeg >/dev/null; then
			[[ "$endnotif" == true ]] && notify-send "Recording Aborted" "The upload has been aborted." -a "E-Z Recorder"
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
			abort_upload
		fi
	else
		if pgrep wf-recorder >/dev/null; then
			[[ "$endnotif" == true ]] && notify-send "Recording Aborted" "The upload has been aborted." -a "E-Z Recorder"
			pkill wf-recorder
			if [[ -f "$gif_pending_file" ]]; then
				rm "$gif_pending_file"
			fi
			if [[ "$save" == false ]]; then
				video_file=$(ls -t recording_*.mp4 | head -n 1)
				rm "$video_file"
			fi
			exit 0
		elif pgrep wl-screenrec >/dev/null; then
			[[ "$endnotif" == true ]] && notify-send "Recording Aborted" "The upload has been aborted." -a "E-Z Recorder"
			pkill wl-screenrec
			if [[ -f "$gif_pending_file" ]]; then
				rm "$gif_pending_file"
			fi
			if [[ "$save" == false ]]; then
				video_file=$(ls -t recording_*.mp4 | head -n 1)
				rm "$video_file"
			fi
			exit 0
		elif pgrep kooha >/dev/null; then
			[[ "$endnotif" == true ]] && notify-send "Recording Aborted" "The upload has been aborted." -a "E-Z Recorder"
			parent_pid=$(pgrep -f "kooha" | xargs -I {} ps -o ppid= -p {})
			if [[ -n "$parent_pid" ]]; then
				if [[ -d "$(eval echo $kooha_dir)" ]]; then
					if [[ -f "$(eval echo $kooha_last_time)" ]]; then
						read_kooha_last_time=$(cat "$(eval echo $kooha_last_time)")
						find "$(eval echo $kooha_dir)" -type f \( -name "*.mp4" -o -name "*.mkv" -o -name "*.webm" \) -newer "$read_kooha_last_time" -exec rm {} \;
						rm "$(eval echo $kooha_last_time)"
					fi
				fi
				killall kooha && kill -KILL "$parent_pid"
			fi
			exit 0
		else
			abort_upload
		fi
	fi
fi

post_process_video() {
	local input_file=$1
	local output_file="${input_file%.mp4}_processed.mp4"
	ffmpeg -i "$input_file" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2,format=$pixelformat" -colorspace bt709 -color_primaries bt709 -color_trc bt709 -c:v $encoder -preset $preset -crf $crf -movflags +faststart -c:a copy "$output_file"
	mv "$output_file" "$input_file"
}

if [[ -z "$1" || "$1" == "--sound" || "$1" == "--fullscreen-sound" || "$1" == "--fullscreen" || "$1" == "--gif" ]]; then
	if [[ "$1" == "--sound" || "$1" == "--fullscreen-sound" || "$1" == "--fullscreen" ]]; then
		if [[ "$XDG_SESSION_TYPE" == "wayland" && ("$XDG_CURRENT_DESKTOP" == "GNOME" || "$XDG_CURRENT_DESKTOP" == "KDE" || "$XDG_CURRENT_DESKTOP" == "COSMIC") ]]; then
			printf "\e[30m\e[46m$1\e[0m"
			printf "\e[1;32m is only for X11 or wlroots Compositors as its not needed. \e[0m\n"
			notify-send "This Argument is only for X11 or wlroots Compositors" "As its not needed." -a "E-Z Recorder"
			sleep 2
			exit 1
		fi
	fi
else
	if [[ "$XDG_SESSION_TYPE" == "wayland" && ("$XDG_CURRENT_DESKTOP" == "GNOME" || "$XDG_CURRENT_DESKTOP" == "KDE" || "$XDG_CURRENT_DESKTOP" == "COSMIC") ]]; then
		echo "Invalid argument: $1"
		notify-send "Invalid argument: $1" -a "E-Z Recorder"
		exit 1
	fi
fi

if [[ "$1" == "--gif" ]]; then
	touch "$gif_pending_file"
fi

lockfile="$(eval echo $HOME/.config/e-z-recorder/.script.lck)"

acquire_lock() {
	if [[ -f "$lockfile" ]]; then
		other_pid=$(cat "$lockfile")
		if kill -0 "$other_pid" 2>/dev/null; then
			echo "Another instance of slurp or slop is already running."
			exit 1
		else
			echo $$ >"$lockfile"
		fi
	else
		echo $$ >"$lockfile"
	fi
}

release_lock() {
	rm -f "$lockfile"
}

get_recorder_command() {
	if [[ "$wlscreenrec" == true ]]; then
		echo "wl-screenrec"
	else
		echo "wf-recorder"
	fi
}

if [[ "$XDG_SESSION_TYPE" == "wayland" && ("$XDG_CURRENT_DESKTOP" == "GNOME" || "$XDG_CURRENT_DESKTOP" == "KDE" || "$XDG_CURRENT_DESKTOP" == "COSMIC") ]]; then
	if pgrep -x "kooha" >/dev/null; then
		echo "Kooha is already running."
		echo "For the Videos to Upload, Simply just Close the Window."
		notify-send "Kooha is already running." -a "E-Z Recorder"
		exit 1
	fi
	echo $(date +%s) >"$(eval echo $kooha_last_time)"
	mkdir -p "$(eval echo $kooha_dir)"
	kooha &
	kooha_pid=$!
	wait $kooha_pid
else
	if [[ "$XDG_SESSION_TYPE" == "x11" ]]; then
		if pgrep ffmpeg >/dev/null; then
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
				acquire_lock
				trap release_lock EXIT
				[[ "$startnotif" == true ]] && notify-send "Screen Snip Recording" "Select the region to Start" -a "E-Z Recorder"
				region=$(slop -f "%x,%y %w,%h")
				if [[ -z "$region" ]]; then
					notify-send "Recording Canceling" 'Canceled' -a "E-Z Recorder"
					exit 1
				fi
				IFS=', ' read -r x y width height <<<"$region"
				ffmpeg -video_size "${width}x${height}" -framerate $fps -f x11grab -i $DISPLAY+"${x},${y}" -f pulse -i "$(getaudiooutput)" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v $encoder -preset $preset -crf $crf -pix_fmt $pixelformat -movflags +faststart -c:a aac -b:a 128k './recording_'"$(getdate)"'.mp4' &
				disown
				release_lock
				trap - EXIT
			elif [[ "$1" == "--fullscreen-sound" ]]; then
				if [[ "$save" == true ]]; then
					[[ "$startnotif" == true ]] && notify-send "Starting Recording" 'recording_'"$(getdate)"'.mp4' -a "E-Z Recorder"
				else
					[[ "$startnotif" == true ]] && notify-send "Starting Recording" 'Started' -a "E-Z Recorder"
				fi
				ffmpeg -video_size $(getactivemonitor) -framerate $fps -f x11grab -i $DISPLAY -f pulse -i "$(getaudiooutput)" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v $encoder -preset $preset -crf $crf -pix_fmt $pixelformat -movflags +faststart -c:a aac -b:a 128k './recording_'"$(getdate)"'.mp4' &
				disown
			elif [[ "$1" == "--fullscreen" ]]; then
				if [[ "$save" == true ]]; then
					[[ "$startnotif" == true ]] && notify-send "Starting Recording" 'recording_'"$(getdate)"'.mp4' -a "E-Z Recorder"
				else
					[[ "$startnotif" == true ]] && notify-send "Starting Recording" 'Started' -a "E-Z Recorder"
				fi
				ffmpeg -video_size $(getactivemonitor) -framerate $fps -f x11grab -i $DISPLAY -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v $encoder -preset $preset -crf $crf -pix_fmt $pixelformat -movflags +faststart './recording_'"$(getdate)"'.mp4' &
				disown
			elif [[ "$1" == "--gif" ]]; then
				touch "$gif_pending_file"
				acquire_lock
				trap release_lock EXIT
				[[ "$startnotif" == true ]] && notify-send "GIF Screen Snip Recording" "Select the region to Start" -a "E-Z Recorder"
				region=$(slop -f "%x,%y %w,%h")
				if [[ -z "$region" ]]; then
					notify-send "Recording Canceling" 'Canceled' -a "E-Z Recorder"
					exit 1
				fi
				IFS=', ' read -r x y width height <<<"$region"
				ffmpeg -video_size "${width}x${height}" -framerate $fps -f x11grab -i $DISPLAY+"${x},${y}" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v $encoder -preset $preset -crf $crf -pix_fmt $pixelformat -movflags +faststart './recording_'"$(getdate)"'.mp4' &
				disown
				release_lock
				trap - EXIT
			else
				acquire_lock
				trap release_lock EXIT
				[[ "$startnotif" == true ]] && notify-send "Screen Snip Recording" "Select the region to Start" -a "E-Z Recorder"
				region=$(slop -f "%x,%y %w,%h")
				if [[ -z "$region" ]]; then
					notify-send "Recording Canceling" 'Canceled' -a "E-Z Recorder"
					exit 1
				fi
				IFS=', ' read -r x y width height <<<"$region"
				ffmpeg -video_size "${width}x${height}" -framerate $fps -f x11grab -i $DISPLAY+"${x},${y}" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v $encoder -preset $preset -crf $crf -pix_fmt $pixelformat -movflags +faststart './recording_'"$(getdate)"'.mp4' &
				disown
				release_lock
				trap - EXIT
			fi
		fi
	else
		recorder_command=$(get_recorder_command)
		if pgrep "$recorder_command" >/dev/null; then
			if [[ -f "$gif_pending_file" || "$1" == "--gif" ]]; then
				[[ "$endnotif" == true ]] && notify-send -t 5000 "Recording is being converted to GIF" "Please Wait.." -a "E-Z Recorder" &
				pkill "$recorder_command" &
				wait
				sleep 1.5
				video_file=$(ls -t recording_*.mp4 | head -n 1)
				gif_file=$(gif "$video_file")
				upload "$gif_file" "--gif"
			else
				[[ "$endnotif" == true ]] && notify-send -t 2000 "Recording Stopped" "Stopped" -a "E-Z Recorder" &
				pkill "$recorder_command" &
				wait
				sleep 1.5
				video_file=$(ls -t recording_*.mp4 | head -n 1)
				[[ "$colorworkaround" == true ]] && post_process_video "$video_file"
				upload "$video_file"
			fi
		else
			if [[ "$wlscreenrec" == true ]]; then
				if [[ "$1" == "--sound" ]]; then
					acquire_lock
					trap release_lock EXIT
					[[ "$startnotif" == true ]] && notify-send "Screen Snip Recording" "Select the region to Start" -a "E-Z Recorder"
					region=$(slurp)
					if [[ -z "$region" ]]; then
						notify-send "Recording Canceling" 'Canceled' -a "E-Z Recorder"
						exit 1
					fi
					command="$recorder_command --geometry \"$region\" --audio --audio-device \"$(getaudiooutput)\""
					if [[ "$extpixelformat" != "auto" ]]; then
						command+=" --encode-pixfmt \"$extpixelformat\""
					fi
					command+=" -f './recording_'"$(getdate)"'.mp4'"
					eval "$command" &
					disown
					release_lock
					trap - EXIT
				elif [[ "$1" == "--fullscreen-sound" ]]; then
					if [[ "$save" == true ]]; then
						[[ "$startnotif" == true ]] && notify-send "Starting Recording" 'recording_'"$(getdate)"'.mp4' -a "E-Z Recorder"
					else
						[[ "$startnotif" == true ]] && notify-send "Starting Recording" 'Started' -a "E-Z Recorder"
					fi
					command="$recorder_command --output $(getactivemonitor) --audio --audio-device \"$(getaudiooutput)\""
					if [[ "$extpixelformat" != "auto" ]]; then
						command+=" --encode-pixfmt \"$extpixelformat\""
					fi
					command+=" -f './recording_'"$(getdate)"'.mp4'"
					eval "$command" &
					disown
				elif [[ "$1" == "--fullscreen" ]]; then
					if [[ "$save" == true ]]; then
						[[ "$startnotif" == true ]] && notify-send "Starting Recording" 'recording_'"$(getdate)"'.mp4' -a "E-Z Recorder"
					else
						[[ "$startnotif" == true ]] && notify-send "Starting Recording" 'Started' -a "E-Z Recorder"
					fi
					command="$recorder_command --output $(getactivemonitor)"
					if [[ "$extpixelformat" != "auto" ]]; then
						command+=" --encode-pixfmt \"$extpixelformat\""
					fi
					command+=" -f './recording_'"$(getdate)"'.mp4'"
					eval "$command" &
					disown
				elif [[ "$1" == "--gif" ]]; then
					touch "$gif_pending_file"
					acquire_lock
					trap release_lock EXIT
					[[ "$startnotif" == true ]] && notify-send "GIF Screen Snip Recording" "Select the region to Start" -a "E-Z Recorder"
					region=$(slurp)
					if [[ -z "$region" ]]; then
						notify-send "Recording Canceling" 'Canceled' -a "E-Z Recorder"
						exit 1
					fi
					command="$recorder_command --geometry \"$region\""
					if [[ "$extpixelformat" != "auto" ]]; then
						command+=" --encode-pixfmt \"$extpixelformat\""
					fi
					command+=" -f './recording_'"$(getdate)"'.mp4'"
					eval "$command" &
					disown
					release_lock
					trap - EXIT
				else
					acquire_lock
					trap release_lock EXIT
					[[ "$startnotif" == true ]] && notify-send "Screen Snip Recording" "Select the region to Start" -a "E-Z Recorder"
					region=$(slurp)
					if [[ -z "$region" ]]; then
						notify-send "Recording Canceling" 'Canceled' -a "E-Z Recorder"
						exit 1
					fi
					command="$recorder_command --geometry \"$region\""
					if [[ "$extpixelformat" != "auto" ]]; then
						command+=" --encode-pixfmt \"$extpixelformat\""
					fi
					command+=" -f './recording_'"$(getdate)"'.mp4'"
					eval "$command" &
					disown
					release_lock
					trap - EXIT
				fi
			else
				if [[ "$1" == "--sound" ]]; then
					acquire_lock
					trap release_lock EXIT
					[[ "$startnotif" == true ]] && notify-send "Screen Snip Recording" "Select the region to Start" -a "E-Z Recorder"
					region=$(slurp)
					if [[ -z "$region" ]]; then
						notify-send "Recording Canceling" 'Canceled' -a "E-Z Recorder"
						exit 1
					fi
					"$recorder_command" --pixel-format $pixelformat -c "$encoder" -p preset=$preset -p crf=$crf -f './recording_'"$(getdate)"'.mp4' --geometry "$region" --audio="$(getaudiooutput)" -r $fps &
					disown
					release_lock
					trap - EXIT
				elif [[ "$1" == "--fullscreen-sound" ]]; then
					if [[ "$save" == true ]]; then
						[[ "$startnotif" == true ]] && notify-send "Starting Recording" 'recording_'"$(getdate)"'.mp4' -a "E-Z Recorder"
					else
						[[ "$startnotif" == true ]] && notify-send "Starting Recording" 'Started' -a "E-Z Recorder"
					fi
					"$recorder_command" -o $(getactivemonitor) --pixel-format $pixelformat -c "$encoder" -p preset=$preset -p crf=$crf -f './recording_'"$(getdate)"'.mp4' --audio="$(getaudiooutput)" -r $fps &
					disown
				elif [[ "$1" == "--fullscreen" ]]; then
					if [[ "$save" == true ]]; then
						[[ "$startnotif" == true ]] && notify-send "Starting Recording" 'recording_'"$(getdate)"'.mp4' -a "E-Z Recorder"
					else
						[[ "$startnotif" == true ]] && notify-send "Starting Recording" 'Started' -a "E-Z Recorder"
					fi
					"$recorder_command" -o $(getactivemonitor) --pixel-format $pixelformat -c "$encoder" -p preset=$preset -p crf=$crf -f './recording_'"$(getdate)"'.mp4' -r $fps &
					disown
				elif [[ "$1" == "--gif" ]]; then
					touch "$gif_pending_file"
					acquire_lock
					trap release_lock EXIT
					[[ "$startnotif" == true ]] && notify-send "GIF Screen Snip Recording" "Select the region to Start" -a "E-Z Recorder"
					region=$(slurp)
					if [[ -z "$region" ]]; then
						notify-send "Recording Canceling" 'Canceled' -a "E-Z Recorder"
						exit 1
					fi
					"$recorder_command" --pixel-format $pixelformat -c "$encoder" -p preset=$preset -p crf=$crf -f './recording_'"$(getdate)"'.mp4' --geometry "$region" -r $fps &
					disown
					release_lock
					trap - EXIT
				else
					acquire_lock
					trap release_lock EXIT
					[[ "$startnotif" == true ]] && notify-send "Screen Snip Recording" "Select the region to Start" -a "E-Z Recorder"
					region=$(slurp)
					if [[ -z "$region" ]]; then
						notify-send "Recording Canceling" 'Canceled' -a "E-Z Recorder"
						exit 1
					fi
					"$recorder_command" --pixel-format $pixelformat -c "$encoder" -p preset=$preset -p crf=$crf -f './recording_'"$(getdate)"'.mp4' --geometry "$region" -r $fps &
					disown
					release_lock
					trap - EXIT
				fi
			fi
		fi
	fi
fi

if [[ "$XDG_SESSION_TYPE" == "wayland" && ("$XDG_CURRENT_DESKTOP" == "GNOME" || "$XDG_CURRENT_DESKTOP" == "KDE" || "$XDG_CURRENT_DESKTOP" == "COSMIC") ]]; then
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
				if ((file_count % 2 == 0)); then
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
				if ((file_count % 2 == 0)); then
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
		if ((recording_count <= 1)); then
			rm -rf "$(eval echo $kooha_dir)"
		fi
	fi
fi

exit 0
