# =============================================================================
#  Nushell config  —  ported from MiaSchionato/dotfiles (fish + foot)
#  Theme:  TokyoNight Night        (foot/themes/tokyonight_night.ini)
#  Prompt: two-line, from fish/functions/fish_prompt.fish
#  Keys:   vi mode                 (fish_variables: fish_vi_key_bindings)
# =============================================================================

# ---- fish_greeting (empty) -------------------------------------------------
$env.config.show_banner = false

# ---- general feel --------------------------------------------------------
$env.config.edit_mode = "vi"
$env.config.cursor_shape = { vi_insert: "line", vi_normal: "block", emacs: "line" }
$env.config.history.file_format = "sqlite"
$env.config.history.max_size = 1_000_000
$env.config.history.isolation = true
$env.config.completions.algorithm = "fuzzy"
$env.config.completions.case_sensitive = false
$env.config.completions.quick = true
$env.config.completions.partial = true
$env.config.rm.always_trash = true
$env.config.footer_mode = 25
$env.config.table.mode = "rounded"
$env.config.table.index_mode = "auto"
$env.config.render_right_prompt_on_last_line = false
$env.config.use_kitty_protocol = false
$env.config.bracketed_paste = true

# ---- TokyoNight Night palette --------------------------------------------
const tn = {
    bg:      "#1a1b26"
    bg_hl:   "#283457"
    fg:      "#c0caf5"
    fg_dark: "#a9b1d6"
    comment: "#565f89"
    sel:     "#283457"
    blue:    "#7aa2f7"
    cyan:    "#7dcfff"
    purple:  "#bb9af7"
    green:   "#9ece6a"
    yellow:  "#e0af68"
    orange:  "#ff9e64"
    red:     "#f7768e"
    teal:    "#73daca"
    magenta: "#c0a4f5"
}

# ---- syntax highlighting  (mirrors fish_color_*) -------------------------
$env.config.color_config = {
    separator: $tn.comment
    leading_trailing_space_bg: { attr: n }
    header: { fg: $tn.green attr: b }
    empty: $tn.blue
    bool: $tn.orange
    int: $tn.fg
    filesize: $tn.cyan
    duration: $tn.fg
    date: $tn.purple
    range: $tn.fg
    float: $tn.fg
    string: $tn.green
    nothing: $tn.comment
    binary: $tn.fg
    cell-path: $tn.fg
    row_index: { fg: $tn.comment attr: b }
    record: $tn.fg
    list: $tn.fg
    hints: $tn.comment
    search_result: { fg: $tn.fg bg: $tn.sel }

    shape_binary: $tn.purple
    shape_bool: $tn.orange
    shape_closure: { fg: $tn.teal attr: b }
    shape_custom: $tn.green
    shape_datetime: $tn.purple
    shape_directory: $tn.cyan
    shape_external: $tn.cyan
    shape_externalarg: $tn.fg
    shape_external_resolved: $tn.teal
    shape_filepath: $tn.cyan
    shape_flag: { fg: $tn.purple attr: b }
    shape_float: $tn.fg
    shape_glob_interpolation: $tn.cyan
    shape_globpattern: $tn.cyan
    shape_int: $tn.fg
    shape_internalcall: { fg: $tn.cyan attr: b }
    shape_keyword: { fg: $tn.purple attr: b }
    shape_list: $tn.fg
    shape_literal: $tn.blue
    shape_match_pattern: $tn.green
    shape_matching_brackets: { attr: u }
    shape_nothing: $tn.comment
    shape_operator: $tn.yellow
    shape_pipe: $tn.purple
    shape_range: $tn.yellow
    shape_record: $tn.fg
    shape_redirection: { fg: $tn.purple attr: b }
    shape_signature: { fg: $tn.teal attr: b }
    shape_string: $tn.green
    shape_string_interpolation: $tn.cyan
    shape_table: $tn.fg
    shape_variable: $tn.magenta
    shape_vardecl: $tn.magenta
    shape_garbage: { fg: $tn.fg bg: $tn.red attr: b }
    shape_comment: $tn.comment
}

# ---- completion menu look ------------------------------------------------
$env.config.menus = ($env.config.menus | each {|m|
    if ($m.name in ["completion_menu" "history_menu" "help_menu" "ide_completion_menu"]) {
        $m | upsert style {
            text: $tn.fg
            selected_text: { fg: $tn.fg bg: $tn.sel attr: b }
            description_text: $tn.comment
            match_text: { fg: $tn.cyan attr: b }
            selected_match_text: { fg: $tn.cyan bg: $tn.sel attr: b }
        }
    } else { $m }
})

# =============================================================================
#  Prompt  —  port of fish/functions/fish_prompt.fish
#    line 1:  user-host  <cwd>  (git)   [exit]
#    line 2:  ❯          (# when root / red on error)
# =============================================================================
def _git_segment [] {
    let head = (do -i { ^git rev-parse --abbrev-ref HEAD } | complete)
    if $head.exit_code != 0 { return "" }
    let name = ($head.stdout | str trim)
    if ($name | is-empty) { return "" }
    let porcelain = (do -i { ^git status --porcelain } | complete | get stdout | lines)
    let dirty = ($porcelain | any {|l| ($l | str substring 1..2 | str trim | is-not-empty) })
    let staged = ($porcelain | any {|l| ($l | str substring 0..1) not-in [" " "?"] })
    mut marks = ""
    if $staged { $marks = $marks + "+" }
    if $dirty  { $marks = $marks + "*" }
    let sfx = if ($marks | is-empty) { "" } else { $" ($marks)" }
    $" (ansi { fg: '#bb9af7' })\(($name)($sfx)\)(ansi reset)"
}

$env.PROMPT_COMMAND = {||
    let ok    = ($env.LAST_EXIT_CODE == 0)
    let id_c  = if $ok { "#7aa2f7" } else { "#f7768e" }
    let user  = ($env.USERNAME | str lowercase | split row ' ' | first)
    let id    = $"(ansi { fg: $id_c })($user)(ansi reset)"
    let home  = ($nu.home-dir | str replace --all '\' '/')
    let path  = ($env.PWD | str replace --all '\' '/' | str replace $home "~")
    let cwd   = $"(ansi green_bold)($path)(ansi reset)"
    let git   = (_git_segment)
    let stat  = if $ok { "" } else { $" (ansi { fg: '#f7768e' })[($env.LAST_EXIT_CODE)](ansi reset)" }
    $"($id) ($cwd)($git)($stat)"
}
$env.PROMPT_COMMAND_RIGHT = {|| "" }

def _indicator [] {
    let ok = ($env.LAST_EXIT_CODE == 0)
    let c  = if $ok { "#7aa2f7" } else { "#f7768e" }
    $"(ansi { fg: $c })❯(ansi reset) "
}
$env.PROMPT_INDICATOR         = {|| _indicator }
$env.PROMPT_INDICATOR_VI_INSERT = {|| _indicator }
$env.PROMPT_INDICATOR_VI_NORMAL = {|| $"(ansi { fg: '#e0af68' })❮(ansi reset) " }
$env.PROMPT_MULTILINE_INDICATOR = $"(ansi { fg: '#565f89' })::: (ansi reset)"

# =============================================================================
#  Environment  (fish/config.fish)
# =============================================================================
$env.EDITOR = "nvim"
$env.VISUAL = "nvim"
$env.TERM   = "xterm-256color"
# C.UTF-8 is built into perl/glibc and needs no installed locale files,
# so Git-for-Windows' perl stops warning while output stays UTF-8.
$env.LANG   = "C.UTF-8"
$env.LC_ALL = "C.UTF-8"
# Last-resort silencer: if some perl still can't set the locale, don't nag.
$env.PERL_BADLANG = "0"
$env.BAT_THEME = "tokyonight_night"
$env.FZF_DEFAULT_OPTS = ([
    "--height=60% --layout=reverse --border --info=inline"
    "--color=bg+:#283457,bg:#1a1b26,spinner:#7dcfff,hl:#7aa2f7"
    "--color=fg:#c0caf5,header:#7aa2f7,info:#bb9af7,pointer:#7dcfff"
    "--color=marker:#9ece6a,fg+:#c0caf5,prompt:#bb9af7,hl+:#7dcfff"
] | str join " ")

# =============================================================================
#  Aliases & functions  (fish/functions/*.fish)
# =============================================================================
alias cl = clear                       # cl.fish
alias ":q" = exit                      # :q.fish  (also works in vi normal mode)
alias vi = nvim
alias vim = nvim
alias lg = lazygit
alias y = yazi
alias cat = bat --paging=never
alias g = git
alias gs = git status
alias gd = git diff
alias ga = git add
alias gc = git commit
alias gp = git push
alias gl = git pull

# pls.fish  →  run elevated  (Sudo for Windows, else gsudo if present)
def --wrapped pls [...rest] {
    if (which sudo  | is-not-empty) { ^sudo  ...$rest } else if (which gsudo | is-not-empty) { ^gsudo ...$rest } else {
        print $"(ansi red)no sudo/gsudo found(ansi reset)"
    }
}

# n.fish  →  open the languages notebook dir in nvim
def --wrapped n [...rest] { ^nvim $"($nu.home-dir)/Documents/languages" ...$rest }

# quality-of-life
def ll [...args] { ls -la ...$args }
def la [...args] { ls -a  ...$args }
def mkcd [dir: string] { mkdir $dir; cd $dir }
def ".." [] { cd .. }
def "..." [] { cd ../.. }

# =============================================================================
#  Tools
# =============================================================================
# zoxide  (config.fish: `zoxide init fish | source`)  — also overrides `cd`
source ~/.cache/zoxide.nu

# =============================================================================
#  carapace  (completion bridge)
# =============================================================================
$env.CARAPACE_BRIDGES = 'zsh,fish,bash,inshellisense'
source ~/.cache/carapace/init.nu