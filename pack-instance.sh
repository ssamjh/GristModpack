#!/bin/bash
if [[ $@ == "-h" ]] || [[ $@ == "--help" ]]; then
  echo "usage: ./pack-instance.sh [output]"
  echo "Creates a Prism Launcher compatible instance .zip file from your pack.toml."
  echo "If 'include' directory exists, its contents are copied to the minecraft folder."
  echo "If 'icon.png' exists, it's added to the pack and its instance config."
  echo "Output defaults to '<name>_v<version>.zip' in the current directory."
  exit 0
fi

if ! type zip &> /dev/null; then echo "error: zip is not available on your system."; exit 1; fi
if [[ ! -f "pack.toml"          ]]; then echo "error: Could not find 'pack.toml'. Not in a packwiz project directory?"; exit 1; fi
if [[ ! -f "pack-instance.toml" ]]; then echo "error: Could not find 'pack-instance.toml'."; exit 1; fi

output="$@"
start_dir=$PWD
bootstrap_jar="packwiz-installer-bootstrap.jar"
bootstrap_url="https://github.com/packwiz/packwiz-installer-bootstrap/releases/latest/download/$bootstrap_jar"

key_string_regex='^([a-zA-Z-]+) ?= ?"(.+)"$'    # To read key = "string" lines.
key_integer_regex='^([a-zA-Z-]+) ?= ?([0-9]+)$' # To read key = integer lines.

# Read the pack.toml file and parse it in a super simplified way.
# Ideally we'd use a proper TOML parser but this should probably work.
while IFS= read -r line; do
  if [[ $line =~ $key_string_regex ]]; then
    case ${BASH_REMATCH[1]} in
      name) name=${BASH_REMATCH[2]} ;;
      version) version=${BASH_REMATCH[2]} ;;
      minecraft) mc_version=${BASH_REMATCH[2]} ;;
      forge) loader="net.minecraftforge"; loader_version=${BASH_REMATCH[2]} ;;
      quilt) loader="org.quiltmc.quilt-loader"; loader_version=${BASH_REMATCH[2]} ;;
      fabric) loader="net.fabricmc.fabric-loader"; loader_version=${BASH_REMATCH[2]} ;;
    esac
  fi
done < pack.toml

if [[ -z $name       ]]; then echo "error: 'name' not found in pack.toml."; exit 1; fi
if [[ -z $version    ]]; then echo "error: 'version' not found in pack.toml."; exit 1; fi
if [[ -z $mc_version ]]; then echo "error: 'minecraft' not found in pack.toml."; exit 1; fi
if [[ -z $loader     ]]; then echo "error: 'forge', 'fabric or 'quilt' not found in pack.toml."; exit 1; fi

# Do the same for pack-instance.toml.
while IFS= read -r line; do
  if [[ $line =~ $key_string_regex ]]; then
    case ${BASH_REMATCH[1]} in
      url) url=${BASH_REMATCH[2]} ;;
    esac
  elif [[ $line =~ $key_integer_regex ]]; then
    case ${BASH_REMATCH[1]} in
      memory) memory=${BASH_REMATCH[2]} ;;
    esac
  fi
done < pack-instance.toml

if [[ -z $url ]]; then echo "error: 'url' not found in pack-instance.toml."; exit 1; fi

# If no output was specified, use a default filename.
if [[ -z $output ]]; then output="${name}_v${version}.zip"; fi

# Create a temporary directory and move into it.
tmp_dir=$(mktemp -d)
if [[ ! -e $tmp_dir ]]; then echo "error: Failed to create temporary folder '$tmp_dir'."; exit 1; fi
pushd $tmp_dir &> /dev/null

# Download the latest packwiz bootstrapper.
mkdir minecraft
# -s: Silent, don't print output.
# -L: Follow HTTP redirects.
curl -sL -o "minecraft/$bootstrap_jar" "$bootstrap_url"

# If include directory exists, copy its contents to the minecraft directory recursively.
if [[ -e "$start_dir/include" ]]; then
  cp -r "$start_dir/include/." "minecraft"
fi

# Create an instance.cfg file with the necessary information for a Prism Launcher pack.
cat > instance.cfg << EOF
name=$name
InstanceType=OneSix
MCLaunchMethod=LauncherPart
OverrideCommands=true
PreLaunchCommand="\$INST_JAVA" -jar "$bootstrap_jar" "$url/pack.toml"
EOF

# If icon.png exists, append iconKey to the instance.cfg and include the icon file.
if [[ -e "$start_dir/icon.png" ]]; then
  echo "iconKey=$name" >> instance.cfg
  cp "$start_dir/icon.png" "$name.png"
fi

# If memory is specified, append it to the instance.cfg.
if [[ -n $memory ]]; then
  echo "MinMemAlloc=$memory" >> instance.cfg
  echo "MaxMemAlloc=$memory" >> instance.cfg
fi

# Create a minimal mmc-pack.json file.
# Other dependencies should be auto-filled on first launch.
cat > mmc-pack.json << EOF
{
  "formatVersion": 1,
  "components": [
    { "uid": "net.minecraft", "version": "$mc_version", "important": true },
    { "uid": "$loader", "version": "$loader_version" }
  ]
}
EOF

# Zip up everything from the temp directory.
# -q: Quiet, don't print output.
# -r: Add files recursively, Such as from minecraft/.
zip -qr modpack.zip *

popd &> /dev/null                   # Return to the starting directory.
mv "$tmp_dir/modpack.zip" "$output" # Move .zip file to desired location.
rm -rf $tmp_dir                     # Remove the temp directory.
