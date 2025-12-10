
main() {
    cd "$PROJECT_ROOT" || exit 1
    dosbox \
    -c "mount c WORK" \
    -c "mount a MASM" \
    -c "keyb br275" \


}



SCRIPT_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")") && source "$SCRIPT_DIR/util.bash"
main "$@"