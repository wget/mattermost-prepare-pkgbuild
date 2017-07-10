#!/usr/bin/env bash

# shellcheck disable=SC1090
. "${0%/*}/utils.sh"
. "${0%/*}/argsparse/argsparse.sh"

set_colors
set_effects

require_deps 'sed' 'curl' 'po2i18n' 'git' || exit 1

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
    local missing=()
    local gitReturn
    local msg=()
    local dieMsg
    local solution=()
    local solutionMsg
    if [[ ! -d "$dir" ]]; then
        die "'$dir' is not a valid Mattermost directory. Aborted."
    fi

    if [[ ! -d "$dir/i18n" ]]; then
        missing+=($dir/i18n)
    fi
    
    if [[ ! -d "$dir/webapp" ]]; then
        missing+=($dir/webapp)
    fi

    if (( ${#missing} != 0 )); then
        if (( ${#missing} == 1 )); then
            die "'${missing[0]}' is not present in your mattermost directory. Aborted."
        else
            die "'${missing[0]}' and '${missing[1]}' are not present in your mattermost directory. Aborted."
        fi
    fi

    # src.: https://stackoverflow.com/a/5139672
    gitReturn=$(git diff --exit-code)
    if [[ -n "$gitReturn" ]]; then
        msg+=("local unstaged changes")
        solution+=("git reset --hard HEAD")
    fi

    gitReturn=$(git diff --cached --exit-code)
    if [[ -n "$gitReturn" ]]; then
        msg+=("staged but not committed changes")
        solution+=("git reset --hard HEAD")
    fi

    gitReturn=$(git ls-files --other --exclude-standard --directory)
    if [[ -n "$gitReturn" ]]; then
        msg+=("untracked files in your working tree")
        solution+=("git clean -fd")
    fi

    if (( ${#msg[@]} > 0 )); then
        if (( ${#msg[@]} == 1 )); then
            dieMsg="${msg[0]}"
        elif (( ${#msg[@]} == 2 )); then
            dieMsg="${msg[0]} and ${msg[1]}"
        else
            dieMsg="${msg[0]}, ${msg[1]} and ${msg[2]}"
        fi

        if (( ${#solution[@]} == 1 )); then
            solutionMsg="'${solution[0]}'"
        elif (( ${#solution[@]} == 2 )); then
            solutionMsg="'${solution[0]}' and '${solution[1]}' respectively"
        else
            solutionMsg="'${solution[0]}', '${solution[1]}' and '${solution[2]}' respectively"
        fi

        die "Your Mattermost git directory is not clean. Please remove $dieMsg." \
            "You can use $solutionMsg to achieve this. Aborted."
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
        info "Checking validity of pull request '$pr'..."
        if is_number_positive "$pr" && \
           strpos "$(curl -I --silent https://github.com/mattermost/platform/pull/"$pr")" " 200 OK"; then
            found+=($pr)
            continue
        fi

        warning "The PR code '${invalid[0]}' is invalid."
    done

    retval=("${found[@]}")
    return 0
}

#-------------------------------------------------------------------------------
## @fn get_valid_langs()
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
        info "Checking validity of language code '$lang'..."
        if strpos "$(curl -I --silent https://translate.mattermost.com/export/?path=/"$lang")" " 200 OK"; then
            found+=($lang)
            continue
        fi
        warning "The language code '$lang' is invalid..."
    done

    retval=("${found[@]}")
    return 0
}

function main() {

    local dest
    local prs
    local langs
    local lang
    local to_commit
    local msg

    argsparse_use_option source-folder "The folder containing the Mattermost sources"
    # The following lines can be set on the same line as the previous line.
    argsparse_set_option_property value source-folder
    argsparse_set_option_property short:d source-folder
    argsparse_set_option_property type:directory source-folder
    argsparse_set_option_property mandatory source-folder

    argsparse_use_option pull-requests "The pull request numbers separated with a comma from the Github page that will be applied on the existing Mattermost sources."
    argsparse_set_option_property value pull-requests
    argsparse_set_option_property short:p pull-requests
    # The type char is only for one char, there is no string type.
    # argsparse_set_option_property type:char pull-requests

    argsparse_use_option langs "The languages we want to download from the Pootle server in order to test the translation. The languages are specified using their language codes (as available on Pootle) and must be separated with a comma."
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

        for i in "${prs[@]}"; do
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
        get_valid_langs "$langs"
        langs=("${retval[@]}")

        # Update templates
        info "Downloading new en template for the web static content..."
        curl -L 'https://raw.githubusercontent.com/mattermost/platform/master/webapp/i18n/en.json' \
             -o 'template_web_static_en.json' --progress-bar
        info "Downloading new en template for the platform content..."
        curl -L 'https://raw.githubusercontent.com/mattermost/platform/master/i18n/en.json' \
             -o 'template_platform_en.json' --progress-bar

        for ((i = 0; i < ${#langs[@]}; i++)); do

            lang="${langs[i]}"

            info "Downloading new $lang translations for the web static content..."
            curl -L "https://translate.mattermost.com/export/?path=/$lang/mattermost/web_static.po" \
                 -o web_static.po --progress-bar
            info "Converting $lang web static translations from PO to JSON..."
            if ! po2i18n -t template_web_static_en.json -o new_web_static.json web_static.po; then
                warning "Unable to convert $lang web static translations from PO to JSON. Skipping..."
                continue
            fi
            if ! mv -v new_web_static.json ./webapp/i18n/"$lang".json 2>/dev/null; then
                warning "Unable to move new_web_static.json to ./webapp/i18n/$lang.json"
            else
                to_commit+=("./webapp/i18n/$lang.json")
            fi

            info "Downloading new $lang translations for the platform content..."
            curl -L "https://translate.mattermost.com/export/?path=/$lang/mattermost/platform.po" \
                 -o platform.po --progress-bar
            info "Converting $lang platform translations from PO to JSON..."
            if ! po2i18n -t template_platform_en.json -o new_platform.json platform.po; then
                warning "Unable to convert $lang platform translations from PO to JSON. Skipping..."
                continue
            fi
            if ! mv -v new_platform.json ./i18n/"$lang".json 2>/dev/null; then
                warning "Unable to move new_platform.json to ./i18n/$lang.json"
            else
                to_commit+=("./i18n/$lang.json")
            fi
        done
    fi

    if (( ${#to_commit[@]} > 0 )); then
        info "Adding ${to_commit[*]}..."
        git add "${to_commit[@]}"
        get_date
        msg="Test translation on $retval"
        info "Committing '$msg'..."
        git commit -m "$msg"
    else
        info "No file to commit. The repo can be reset to the previous state."
    fi
}

main "$@"
