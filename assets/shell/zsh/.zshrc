# Interactive profile for Debian 13. Try it with ZDOTDIR before linking it.
[[ -o interactive && -t 0 && -t 1 && ${TERM:-dumb} != dumb ]] || return 0

setopt autocd interactivecomments hist_ignore_space hist_ignore_dups hist_verify
setopt hist_expire_dups_first inc_append_history
unsetopt promptsubst
HISTFILE=${ZDOTDIR:-$HOME}/.zsh_history
HISTSIZE=20000
SAVEHIST=10000

bindkey -e
bindkey '^U' backward-kill-line
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word
bindkey '^[[A' history-beginning-search-backward
bindkey '^[[B' history-beginning-search-forward
bindkey '^[OA' history-beginning-search-backward
bindkey '^[OB' history-beginning-search-forward

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
autoload -Uz compinit add-zsh-hook vcs_info
# Keep the ownership checks and skip insecure completion directories silently.
compinit -i -d "${ZDOTDIR:-$HOME}/.zcompdump-postinstall-$ZSH_VERSION"

alias ll='ls -lhA'
alias la='ls -A'
if (( $+commands[eza] )); then
  alias ll='eza -la --group-directories-first --git'
  alias la='eza -A --group-directories-first'
  alias el='eza --tree --level=2 --group-directories-first'
fi
if (( $+commands[batcat] && ! $+commands[bat] )); then
  alias bat='batcat'
fi
if (( $+commands[fdfind] && ! $+commands[fd] )); then
  alias fd='fdfind'
fi

if (( $+commands[fzf] )); then
  export FZF_DEFAULT_OPTS=${FZF_DEFAULT_OPTS:---height=60% --layout=reverse --border=rounded}
  if (( $+commands[fdfind] )); then
    export FZF_CTRL_T_COMMAND=${FZF_CTRL_T_COMMAND-'fdfind --hidden --exclude .git --type f'}
    export FZF_ALT_C_COMMAND=${FZF_ALT_C_COMMAND-'fdfind --hidden --exclude .git --type d'}
  fi
  if (( $+commands[batcat] )); then
    export FZF_CTRL_T_OPTS=${FZF_CTRL_T_OPTS-'--preview "batcat --color=always --style=numbers --line-range=:80 -- {}" --preview-window=right:60%:hidden --bind=ctrl-/:toggle-preview'}
  fi
  source <(fzf --zsh)
fi
if (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh)"
fi
if (( $+commands[direnv] )); then
  eval "$(direnv hook zsh)"
fi

zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' formats ' on %b'
zstyle ':vcs_info:git:*' actionformats ' on %b (%a)'
VIRTUAL_ENV_DISABLE_PROMPT=1
typeset -g postinstall_prompt_net=''
typeset -gi postinstall_prompt_net_after=0

postinstall_precmd() {
  local route source_ip route_dev venv
  if (( $+commands[git] )); then
    vcs_info
  fi

  if [[ ${POSTINSTALL_PROMPT_IP:-0} == 1 ]] && (( $+commands[ip] )); then
    if (( SECONDS >= postinstall_prompt_net_after )); then
      postinstall_prompt_net_after=$(( SECONDS + 10 ))
      postinstall_prompt_net=''
      route=$(ip -4 -o route get 192.0.2.1 2>/dev/null)
      if [[ $route =~ ' src ([0-9.]+)( |$)' ]]; then
        source_ip=$match[1]
        if [[ $route =~ ' dev ((tun|tap|wg)[[:alnum:]_.-]*)( |$)' ]]; then
          route_dev=" via $match[1]"
        fi
        postinstall_prompt_net="─[$source_ip$route_dev]"
      fi
    fi
  else
    postinstall_prompt_net=''
    postinstall_prompt_net_after=0
  fi

  if [[ -n ${VIRTUAL_ENV:-} ]]; then
    venv=" (${(V)${VIRTUAL_ENV:t}})"
  fi
  psvar=("${vcs_info_msg_0_-}" "$postinstall_prompt_net" "$venv")
}

add-zsh-hook precmd postinstall_precmd
PROMPT=$'┌%F{%(#.red.green)}[%n]%f─%F{cyan}[%m]%f%F{blue}%2v%f─%F{cyan}[%~]%f%F{magenta}%1v%f%3v\n└─%(?..%F{red}[%?]%f )%(#.#.$) '
RPROMPT=''

if [[ -r /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
  source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

# Keep highlighting after completion, widgets and the other integrations.
if [[ -r /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets)
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
