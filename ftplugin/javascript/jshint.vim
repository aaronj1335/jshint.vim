
" Global Options
"
" Enable/Disable highlighting of errors in source.
" Default is Enable
" To disable the highlighting put the line
" let g:JSHintHighlightErrorLine = 0
" in your .vimrc
"
if exists("b:did_jshint_plugin")
  finish
else
  let b:did_jshint_plugin = 1
endif

let s:install_dir = expand('<sfile>:p:h')

au BufLeave <buffer> call s:JSHintClear()

au BufEnter <buffer> call s:JSHint()
au InsertLeave <buffer> call s:JSHint()
"au InsertEnter <buffer> call s:JSHint()
au BufWritePost <buffer> call s:JSHint()

" due to http://tech.groups.yahoo.com/group/vimdev/message/52115
if(!has("win32") || v:version>702)
  au CursorHold <buffer> call s:JSHint()
  au CursorHoldI <buffer> call s:JSHint()

  au CursorHold <buffer> call s:GetJSHintMessage()
endif

au CursorMoved <buffer> call s:GetJSHintMessage()

if !exists("g:JSHintHighlightErrorLine")
  let g:JSHintHighlightErrorLine = 1
endif

if !exists("*s:JSHintUpdate")
  function s:JSHintUpdate()
    silent call s:JSHint()
    call s:GetJSHintMessage()
  endfunction
endif

if !exists(":JSHintUpdate")
  command JSHintUpdate :call s:JSHintUpdate()
endif
if !exists(":JSHintToggle")
  command JSHintToggle :let b:jshint_disabled = exists('b:jshint_disabled') ? b:jshint_disabled ? 0 : 1 : 1
endif

noremap <buffer><silent> dd dd:JSHintUpdate<CR>
noremap <buffer><silent> dw dw:JSHintUpdate<CR>
noremap <buffer><silent> u u:JSHintUpdate<CR>
noremap <buffer><silent> <C-R> <C-R>:JSHintUpdate<CR>

" Set up command and parameters

let s:plugin_path = s:install_dir . "/jshint/"
if has('win32')
  let s:plugin_path = substitute(s:plugin_path, '/', '\', 'g')
endif
let s:cmd = "jshint"

let s:jshintrc_file = expand('~/.jshintrc')
if filereadable(s:jshintrc_file)
  let s:jshintrc = readfile(s:jshintrc_file)
else
  let s:jshintrc = []
end

" WideMsg() prints [long] message up to (&columns-1) length
" guaranteed without "Press Enter" prompt.
if !exists("*s:WideMsg")
  function s:WideMsg(msg)
    let x=&ruler | let y=&showcmd
    set noruler noshowcmd
    redraw
    echo a:msg
    let &ruler=x | let &showcmd=y
  endfun
endif


function! s:JSHintClear()
  if exists("b:jshint_disabled") && b:jshint_disabled == 1
    return
  endif
    
  " Delete previous matches
  let s:matches = getmatches()
  for s:matchId in s:matches
    if s:matchId['group'] == 'JSHintError'
      call matchdelete(s:matchId['id'])
    endif
  endfor
  let b:matched = []
  let b:matchedlines = {}
  let b:cleared = 1
endfunction

function! s:JSHint()
  if exists("b:jshint_disabled") && b:jshint_disabled == 1
    return
  endif

  highlight link JSHintError SpellBad

  if exists("b:cleared")
    if b:cleared == 0
      call s:JSHintClear()
    endif
    let b:cleared = 1
  endif

  let b:matched = []
  let b:matchedlines = {}

  " Detect range
  if a:firstline == a:lastline
    " Skip a possible shebang line, e.g. for node.js script.
    if getline(1)[0:1] == "#!"
      let b:firstline = 2
    else
      let b:firstline = 1
    endif
    let b:lastline = '$'
  else
    let b:firstline = a:firstline
    let b:lastline = a:lastline
  endif

  let b:qf_list = []
  let b:qf_window_count = -1

  silent write! /tmp/jshint_temp.js

  let b:jshint_output = system(s:cmd . " /tmp/jshint_temp.js")
  if !v:shell_error
    return
  elseif v:shell_error == 127
    echoerr 'could not invoke JSHint!'
    let b:jshint_disabled = 1
  end

  for error in split(b:jshint_output, "\n")
    " Match {line}:{char}:{message}
    let b:parts = matchlist(error, '\v.*: line (\d+), col \d+, (.*)$')
    if !empty(b:parts)
      let l:line = b:parts[1] + 0
      let l:errorMessage = b:parts[2]

      " Store the error for an error under the cursor
      let s:matchDict = {}
      let s:matchDict['lineNum'] = l:line
      let s:matchDict['message'] = l:errorMessage
      let b:matchedlines[l:line] = s:matchDict
      let l:errorType = 'W'
      if g:JSHintHighlightErrorLine == 1
        let s:mID = matchadd('JSHintError', '\v%' . l:line . 'l\S.*(\S|$)')
      endif
      " Add line to match list
      call add(b:matched, s:matchDict)

      " Store the error for the quickfix window
      let l:qf_item = {}
      let l:qf_item.bufnr = bufnr('%')
      let l:qf_item.filename = expand('%')
      let l:qf_item.lnum = l:line
      let l:qf_item.text = l:errorMessage
      let l:qf_item.type = l:errorType

      " Add line to quickfix list
      call add(b:qf_list, l:qf_item)
    endif
  endfor

  if exists("s:jshint_qf")
    " if jshint quickfix window is already created, reuse it
    call s:ActivateJSHintQuickFixWindow()
    call setqflist(b:qf_list, 'r')
  else
    " one jshint quickfix window for all buffers
    call setqflist(b:qf_list, '')
    let s:jshint_qf = s:GetQuickFixStackCount()
  endif
  let b:cleared = 0
endfunction

let b:showing_message = 0

if !exists("*s:GetJSHintMessage")
  function s:GetJSHintMessage()
    let s:cursorPos = getpos(".")

    " Bail if RunJSHint hasn't been called yet
    if !exists('b:matchedlines')
      return
    endif

    if has_key(b:matchedlines, s:cursorPos[1])
      let s:jshintMatch = get(b:matchedlines, s:cursorPos[1])
      call s:WideMsg(s:jshintMatch['message'])
      let b:showing_message = 1
      return
    endif

    if b:showing_message == 1
      echo
      let b:showing_message = 0
    endif
  endfunction
endif

if !exists("*s:GetQuickFixStackCount")
    function s:GetQuickFixStackCount()
        let l:stack_count = 0
        try
            silent colder 9
        catch /E380:/
        endtry

        try
            for i in range(9)
                silent cnewer
                let l:stack_count = l:stack_count + 1
            endfor
        catch /E381:/
            return l:stack_count
        endtry
    endfunction
endif

if !exists("*s:ActivateJSHintQuickFixWindow")
    function s:ActivateJSHintQuickFixWindow()
        try
            silent colder 9 " go to the bottom of quickfix stack
        catch /E380:/
        endtry

        if s:jshint_qf > 0
            try
                exe "silent cnewer " . s:jshint_qf
            catch /E381:/
                echoerr "Could not activate JSHint Quickfix Window."
            endtry
        endif
    endfunction
endif


