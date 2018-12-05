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
    let l:current_pos = getcurpos()[0:2]
    let l:diagnostic = lsp#ui#vim#diagnostics#get_diagnostics_under_cursor()
    if !empty(l:diagnostic) && has_key(l:diagnostic, 'message')
        call lsp#utils#echo_with_truncation('LSP: '. substitute(l:diagnostic['message'], '\n\+', ' ', 'g'))
        let s:last_message_pos = l:current_pos
    elseif exists('s:last_pos') && exists('s:last_message_pos') && s:last_pos == s:last_message_pos
        " Clear the message if the position we just left contained a message
        " but the current position does not
        call lsp#utils#echo_with_truncation('')
    endif
    let s:last_pos = l:current_pos
endfunction
