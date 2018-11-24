let s:cursor_moved_timer = -1

function! lsp#ui#vim#diagnostics#echo#cursor_moved() abort
    if !g:lsp_diagnostics_echo_cursor
        return
    endif

    if mode() isnot# 'n'
        " dont' show echo only in normal mode
        return
    endif

    call timer_stop(s:cursor_moved_timer)
    let s:cursor_moved_timer = timer_start(g:lsp_diagnostics_echo_delay, function('s:echo_diagnostics_under_cursor'))
endfunction

function! s:echo_diagnostics_under_cursor(...) abort
    let l:diagnostic = lsp#ui#vim#diagnostics#get_diagnostics_under_cursor()
    if !empty(l:diagnostic) && has_key(l:diagnostic, 'message')
        call lsp#utils#echo_with_truncation('LSP: '. substitute(l:diagnostic['message'], '\n\+', ' ', 'g'))
    endif
endfunction

function! s:stop_cursor_moved_timer() abort
    if exists('s:cursor_moved_timer')
        call timer_stop(s:cursor_moved_timer)
        unlet s:cursor_moved_timer
    endif
endfunction
