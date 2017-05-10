#!/usr/bin/env bash

# shellcheck disable=SC1090
. "${0%/*}/utils.sh"
. "${0%/*}/argsparse/argsparse.sh"

set_colors
set_effects

require_deps 'sed' 'curl' 'po2i18n' || exit 1

#-------------------------------------------------------------------------------
## @fn check_value_of_source_folder()
## @details Called by argsparse. Checks the validity of the source-folder
## argument.
## @param $source-folder The dirctory passed to the program argument.
## @return N/A
## @retval N/A
#-------------------------------------------------------------------------------
function check_value_of_source_folder() {
    local dir=$1
    local msg=()
    if [[ ! -d "$dir" ]]; then
        die "'$dir' is not a valid Mattermost directory. Aborted."
    fi

    if [[ ! -d "$dir/i18n" ]]; then
        msg+=($dir/i18n)
    fi
    
    if [[ ! -d "$dir/webapp" ]]; then
        msg+=($dir/webapp)
    fi

    if (( ${#msg} != 0 )); then
        if (( ${#msg} == 1 )); then
            die "'${msg[0]}' is not present in your mattermost directory. Aborted."
        else
            die "'${msg[0]}' and '${msg[1]}' are not present in your mattermost directory. Aborted."
        fi
    fi
}

#-------------------------------------------------------------------------------
## @fn get_valid_pull_requests()
## @details Checks the validity of the pull-request argument (not called by
## argsparse).
## @param $pr The number passed to the program argument.
## @return N/A
## @retval N/A
#-------------------------------------------------------------------------------
function get_valid_pull_requests() {

    unset retval
    explode "," "$1"
    local prs=("${retval[@]}")
    unset retval
    local invalid=()
    local found=()
    local msg=""

    for pr in "${prs[@]}"; do
        echo "DEBUG '$pr'"

        if ! is_number_positive "$pr"; then
            invalid+=($pr)
            continue
        fi

        if strpos "$(curl -I --silent https://github.com/mattermost/platform/pull/"$pr")" " 200 OK"; then
            found+=($pr)
            continue
        fi

        invalid+=($pr)
    done

    if ((${#invalid[@]} == 1)); then
        msg="The PR code '${invalid[0]}' is invalid."
    elif ((${#invalid[@]} >= 2)); then
        msg='The PR codes '
        if ((${#invalid[@]} == 2)); then
            msg+="'${invalid[0]}' and '${invalid[1]}'"
        else
            for ((i = 0; i < ${#invalid} - 2; i++)); do
                msg+="'${invalid[i]}', "
            done
            msg+="'${invalid[$i]}' and "
            ((i++))
            msg+="'${invalid[$i]}' "
        fi
        msg+=" are invalid."
    fi

    if [[ -n "$msg" ]]; then
        warning "$msg"
    fi
    retval=("${found[@]}")
    return 0
}

#-------------------------------------------------------------------------------
## @fn check_value_of_langs()
## @details Checks the validity of the langs argument (not called by argsparse).
## @param $langs The string passed to the program argument.
## @return In $retval, valid language codes.
## @retval 0 Always returns 0.
#-------------------------------------------------------------------------------
function get_valid_langs() {
    unset retval
    explode "," "$1"
    local langs=("${retval[@]}")
    unset retval
    local invalid=()
    local found=()
    local msg=""

    for lang in "${langs[@]}"; do
        if strpos "$(curl -I --silent https://translate.mattermost.com/export/?path=/"$lang")" " 200 OK"; then
            found+=($lang)
            continue
        fi
        invalid+=($lang)
    done

    if ((${#invalid[@]} == 1)); then
        msg="The language code '${invalid[0]}' is invalid."
    elif ((${#invalid[@]} >= 2)); then
        msg='The language codes '
        if ((${#invalid[@]} == 2)); then
            msg+="'${invalid[0]}' and '${invalid[1]}'"
        else
            for ((i = 0; i < ${#invalid} - 2; i++)); do
                msg+="'${invalid[i]}', "
            done
            msg+="'${invalid[$i]}' and "
            ((i++))
            msg+="'${invalid[$i]}' "
        fi
        msg+=" are invalid."
    fi

    if [[ -n "$msg" ]]; then
        warning "$msg"
    fi
    retval=("${found[@]}")
    return 0
}

argsparse_use_option source-folder "The folder containing the Mattermost sources"
# The following lines can be set on the same line as the previous line.
argsparse_set_option_property value source-folder
argsparse_set_option_property short:d source-folder
argsparse_set_option_property type:directory source-folder
argsparse_set_option_property mandatory source-folder

argsparse_use_option pull-requests "The pull request number from the Github page that will be applied on the existing Mattermost sources"
argsparse_set_option_property value pull-requests
argsparse_set_option_property short:p pull-requests
# The type char is only for one char, there is no string type.
# argsparse_set_option_property type:char pull-requests

argsparse_use_option langs "The languages we want to download from the Pootle server in order to test the translation. The languages are specified using their language codes (as available on Pootle) and must be separated with a colon."
argsparse_set_option_property value langs
argsparse_set_option_property short:l langs

argsparse_parse_options "$@"

dest=${program_options["source-folder"]}
if ! cd "$dest"; then
    die "Unable to change dir to $dest. Aborted."
fi

if ! argsparse_is_option_set "pull-requests"; then
    warning "No pull request specified. Skipping..."
else
    prs=${program_options["pull-requests"]} 
    get_valid_pull_requests "$prs"
    prs=("${retval[@]}")

    for i in $prs; do
        # If you want to test a pull request, simply suffix the Github link by patch
        # and put it in the source array.
        # e.g. with https://github.com/mattermost/platform/pull/4005
        # simply use the following link:
        # https://github.com/mattermost/platform/pull/4005.patch
        curl -LO "https://github.com/mattermost/platform/pull/$i.patch"
        patch -Np1 -i "$i.patch"
    done
fi

if ! argsparse_is_option_set "langs"; then
    warning "No language specified. Skipping..."
else

    langs=${program_options["langs"]}
    # This function is actually called two times, the first one by argsparse
    # and the second one by this call. This is needed as we need the return
    # value of the function and with argsparse we have no way to get it.
    get_valid_langs "$langs"
    langs=("${retval[@]}")

    # Update templates
    info "Downloading new en template for the web static content..."
    curl -L https://raw.githubusercontent.com/mattermost/platform/master/webapp/i18n/en.json \
         -o template_web_static_en.json --progress-bar
    info "Downloading new en template for the platform content..."
    curl -L https://raw.githubusercontent.com/mattermost/platform/master/i18n/en.json \
         -o template_platform_en.json --progress-bar

    for i in $langs; do
        lang="$i"
        info "Downloading new $lang translations for the web static content..."
        curl -L "https://translate.mattermost.com/export/?path=/$i/mattermost/web_static.po" \
             -o web_static.po --progress-bar

        info "Converting $lang web static translations from PO to JSON (might take some time)..."
        if ! po2i18n -t web_static.json -o new_web_static.json web_static.po; then
            warning "Unable to convert $lang web static translations from PO to JSON"
        fi

        if ! mv -v new_web_static.json ./webapp/i18n/"$lang".json 2>/dev/null; then
            warning "Unable to move new_web_static.json to ./webapp/i18n/$lang.json"
        fi

        info "Downloading new $lang translations for the platform content..."
        curl -L "https://translate.mattermost.com/export/?path=/$lang/mattermost/platform.po" \
             -o platform.po --progress-bar

        info "Converting $lang platform translations from PO to JSON (might take some time)..."
        if ! po2i18n -t platform.json -o new_platform.json platform.po; then
            warning "Unable to convert $lang platform translations from PO to JSON"
        fi

        if ! mv -v new_platform.json ./i18n/"$lang".json 2>/dev/null; then
            warning "Unable to move new_platform.json to ./i18n/$lang.json"
        fi
    done
fi