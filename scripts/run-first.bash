main() {
    cd "$PROJECT_ROOT" && dosbox -conf "dosbox-first.conf"
}

SCRIPT_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")") && source "$SCRIPT_DIR/util.bash"
main "$@"