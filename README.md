# Mattermost prepare PKGBUID

This script aims at automating the test of [Mattermost translations](https://translate.mattermost.com) and pull requests submitted against the [Mattermost source code base](https://github.com/mattermost/platform).

This script uses [shut, a Bash library I wrote, which mimicks useful fonctions from PHP](https://github.com/wget/shut) and [argsparse, a Bash library written by Anvil](https://github.com/Anvil/bash-argsparse).

The translation files are downloaded and converted in a format accepted by Mattermost thanks to mattermosti18n, [a tool written by rodcorsi](https://github.com/rodcorsi/mattermosti18n), used to convert translations between GNU gettext .po and JSON files.

## Usage


    mattermost_prepare_pkgbuild.sh [ --help ] --source-folder SOURCE-FOLDER \
            [ --langs LANGS ] [ --pull-requests PULL-REQUESTS ]

     -h | --help
        Show this help message
     -d | --source-folder
        The folder containing the Mattermost sources
     -l | --langs
        The languages we want to download from the Pootle server in order to test the translation. The languages are specified using their language codes (as available on Pootle) and must be separated with a colon.
     -p | --pull-requests
        The pull request number from the Github page that will be applied on the existing Mattermost sources

## License

This software is licensed under the terms of the GNU General Public License v3.0.

