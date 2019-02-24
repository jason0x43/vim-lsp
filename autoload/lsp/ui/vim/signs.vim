" TODO: handle !has('signs')
" TODO: handle signs clearing when server exits
" https://github.com/vim/vim/pull/3652
let s:supports_signs = has('signs')
let s:supports_signs_api = exists('*sign_define')
let s:supports_nvim_highlight = exists('*nvim_buf_add_highlight')
let s:enabled = 0
let s:signs = {} " { path: { server_name: [] } }
let s:hlsources = {} " { path: { server_name: [] } }
let s:action_queue = []
let s:action_queue_timer = 0
let s:action_queue_delay = 10
let s:action_queue_batch_size = 10
let s:severity_sign_names_mapping = {
    \ 1: 'LspError',
    \ 2: 'LspWarning',
    \ 3: 'LspInformation',
    \ 4: 'LspHint',
    \ }

if !exists('g:lsp_next_sign_id')
    let g:lsp_next_sign_id = 6999
endif

if !hlexists('LspErrorText')
    highlight link LspErrorText Error
endif

if !hlexists('LspWarningText')
    highlight link LspWarningText Todo
endif

if !hlexists('LspInformationText')
    hi LspInformationText cterm=underline
endif

if !hlexists('LspHintText')
    hi LspHintText cterm=underline
endif

function! lsp#ui#vim#signs#enable() abort
    if !s:supports_signs
        call lsp#log('vim-lsp signs requires signs support')
        return
    endif
    if !s:enabled
        call s:define_signs()
        let s:enabled = 1
        call lsp#log('vim-lsp signs enabled')
    endif
endfunction

function! lsp#ui#vim#signs#next_error() abort
    let l:signs = s:get_signs(bufnr('%'))
    if empty(l:signs)
        return
    endif
    let l:view = winsaveview()
    let l:next_line = 0
    for l:sign in l:signs
        if l:sign['name'] ==# 'LspError' && l:sign['lnum'] > l:view['lnum']
            let l:next_line = l:sign['lnum']
            break
        endif
    endfor

    if l:next_line == 0
        return
    endif

    let l:view['lnum'] = l:next_line
    let l:view['topline'] = 1
    let l:height = winheight(0)
    let totalnum = line('$')
    if totalnum > l:height
        let l:half = l:height / 2
        if l:totalnum - l:half < l:view['lnum']
            let l:view['topline'] = l:totalnum - l:height + 1
        else
            let l:view['topline'] = l:view['lnum'] - l:half
        endif
    endif
    call winrestview(l:view)
endfunction

function! lsp#ui#vim#signs#previous_error() abort
    let l:signs = s:get_signs(bufnr('%'))
    if empty(l:signs)
        return
    endif
    let l:view = winsaveview()
    let l:next_line = 0
    let l:index = len(l:signs) - 1
    while l:index >= 0
        if l:signs[l:index]['lnum'] < l:view['lnum']
            let l:next_line = l:signs[l:index]['lnum']
            break
        endif
        let l:index = l:index - 1
    endwhile

    if l:next_line == 0
        return
    endif

    let l:view['lnum'] = l:next_line
    let l:view['topline'] = 1
    let l:height = winheight(0)
    let totalnum = line('$')
    if totalnum > l:height
        let l:half = l:height / 2
        if l:totalnum - l:half < l:view['lnum']
            let l:view['topline'] = l:totalnum - l:height + 1
        else
            let l:view['topline'] = l:view['lnum'] - l:half
        endif
    endif
    call winrestview(l:view)
endfunction

" Set default sign text to handle case when user provides empty dict
function! s:add_sign(sign_name, sign_default_text, sign_options) abort
    if !s:supports_signs | return | endif
    if s:supports_signs_api
        let l:options = {
            \ 'text': get(a:sign_options, 'text', a:sign_default_text),
            \ 'texthl': a:sign_name . 'Sign',
            \ 'linehl': a:sign_name . 'Line',
            \ }
        let l:sign_icon = get(a:sign_options, 'icon', '')
        if !empty(l:sign_icon)
            let l:options['icon'] = l:sign_icon
        endif
        call sign_define(a:sign_name, l:options)
    else
        let l:sign_string = 'sign define ' . a:sign_name
            \ . ' text=' . get(a:sign_options, 'text', a:sign_default_text)
            \ . ' texthl=' . a:sign_name . 'Sign'
            \ . ' linehl=' . a:sign_name . 'Line'
        let l:sign_icon = get(a:sign_options, 'icon', '')
        if !empty(l:sign_icon)
            let l:sign_string .= ' icon=' . l:sign_icon
        endif
        exec l:sign_string
    endif
endfunction

function! s:define_signs() abort
    if !s:supports_signs | return | endif
    " let vim handle errors/duplicate instead of us maintaining the state
    call s:add_sign('LspError', 'E>', g:lsp_signs_error)
    call s:add_sign('LspWarning', 'W>', g:lsp_signs_warning)
    call s:add_sign('LspInformation', 'I>', g:lsp_signs_information)
    call s:add_sign('LspHint', 'H>', g:lsp_signs_hint)
endfunction

function! s:get_signs(bufnr) abort
    if !s:supports_signs | return [] | endif
    if s:supports_signs_api
        let l:signs = sign_getplaced(a:bufnr, { 'group': '*' })
        return !empty(l:signs) ? l:signs[0]['signs'] : []
    else
        let l:path = expand('#' . a:bufnr . ':p')
        let l:signs = []
        for l:server_signs = items(s:signs[l:path])
        for l:entry in l:server_signs
            call add(l:signs, l:entry[1])
        endfor
        return l:signs
    endif
endfunction

function! lsp#ui#vim#signs#disable() abort
    if s:enabled
        " TODO: clear all vim_lsp signs
        call s:undefine_signs()
        let s:enabled = 0
        call lsp#log('vim-lsp signs disabled')
    endif
endfunction

function! s:undefine_signs() abort
    if !s:supports_signs | return | endif
    call sign_undefine('LspError')
    call sign_undefine('LspWarning')
    call sign_undefine('LspInformation')
    call sign_undefine('LspHint')
endfunction

function! lsp#ui#vim#signs#set(server_name, data) abort
    if !s:supports_signs | return | endif
    if !s:enabled | return | endif

    if lsp#client#is_error(a:data['response'])
        return
    endif

    let l:uri = a:data['response']['params']['uri']
    let l:diagnostics = a:data['response']['params']['diagnostics']

    let l:path = lsp#utils#uri_to_path(l:uri)

    if !s:supports_signs_api
        let b:server_name = a:server_name

        if !has_key(s:signs, l:path)
            let s:signs[l:path] = {}
        endif

        if !has_key(s:signs[l:path], a:server_name)
            let s:signs[l:path][a:server_name] = []
        endif
    endif

    if s:supports_nvim_highlight
        if !has_key(s:hlsources, l:path)
            let s:hlsources[l:path] = {}
        endif

        if !has_key(s:hlsources[l:path], a:server_name)
            let s:hlsources[l:path][a:server_name] = nvim_create_namespace('')
        endif
    endif

    " will always replace existing set
    call s:clear_signs(a:server_name, l:path)
    call s:place_signs(a:server_name, l:path, l:diagnostics)
endfunction

function! s:clear_signs(server_name, path) abort
    if !s:supports_signs | return | endif

    if s:supports_signs_api
        let l:sign_group = s:get_sign_group(a:server_name)
        call sign_unplace(l:sign_group, { 'buffer': a:path })
    else
        for l:sign in s:signs[a:path][a:server_name]
            call s:queue_action({
                \ 'type': 'remove',
                \ 'sign_id': l:sign['id'],
                \ 'path': a:path
                \ })
        endfor

        if s:supports_nvim_highlight
            call s:queue_action({
                \ 'type': 'remove_hl',
                \ 'hlsource': s:hlsources[a:path][a:server_name],
                \ 'bufnr': bufnr('%'),
                \ })
        endif

        let s:signs[a:path][a:server_name] = []
    endif
endfunction

function! s:get_sign_group(server_name) abort
    return 'vim_lsp_' . a:server_name
endfunction

function! s:place_signs(server_name, path, diagnostics) abort
    if !s:supports_signs | return | endif

    let l:sign_group = s:get_sign_group(a:server_name)

    if !empty(a:diagnostics) && bufnr(a:path) >= 0
        for l:item in a:diagnostics
            let l:line = l:item['range']['start']['line'] + 1

            if has_key(l:item, 'severity') && !empty(l:item['severity'])
                let l:sign_name = get(s:severity_sign_names_mapping, l:item['severity'], 'LspError')
                " pass 0 and let vim generate sign id
                let l:sign_id = s:sign_place(l:sign_group, l:sign_name, a:server_name, a:path, l:line, l:item)
                call lsp#log('add signs', l:sign_id)
            endif
        endfor
    endif
endfunction

function! s:sign_place(sign_group, sign_name, server_name, path, line, item)
    let l:sign_id = 0
    if s:supports_signs_api
        " pass 0 and let vim generate sign id
        let l:sign_id = sign_place(0, a:sign_group, a:sign_name, a:path, { 'lnum': a:line })
    else
        let l:sign_id = g:lsp_next_sign_id
        let g:lsp_next_sign_id += 1
        call s:queue_action({
            \ 'type': 'add',
            \ 'sign_id': l:sign_id,
            \ 'sign_name': a:sign_name,
            \ 'server_name': a:server_name,
            \ 'path': a:path,
            \ 'line': a:line,
            \ 'item': a:item,
            \ })
        call add(s:signs[a:path][a:server_name], { 'id': l:sign_id, 'lnum': a:line, 'name': a:sign_name })
        call lsp#log('add signs', l:sign_id)
    endif
    return l:sign_id
endfunction

function! s:queue_action(action)
    call add(s:action_queue, a:action)
    if s:action_queue_timer == 0
        let s:action_queue_timer = timer_start(s:action_queue_delay, function('s:process_actions'))
    endif
endfunction

function! s:process_actions(timer_id) abort
    let s:action_queue_timer = 0

    let l:i = 0
    while l:i < s:action_queue_batch_size && len(s:action_queue) > 0
        let l:entry = remove(s:action_queue, 0)
        let l:type = l:entry['type']

        if l:type ==# 'add'
            let l:sign_name = l:entry['sign_name']
            let l:path = l:entry['path']
            let l:line = l:entry['line']
            execute ':sign place ' . l:entry['sign_id'] . ' name=' . l:sign_name . ' line=' . l:line . ' file=' . l:path

            if s:supports_nvim_highlight
                let l:item = l:entry['item']
                let l:start = l:item['range']['start']['character']
                let l:end = l:item['range']['end']['character']
                let l:hlsource = s:hlsources[l:path][l:entry['server_name']]
                call nvim_buf_add_highlight(bufnr('%'), l:hlsource, l:sign_name . 'Text', l:line - 1, l:start, l:end)
            endif
        elseif l:type ==# 'remove'
            execute ':sign unplace ' . l:entry['sign_id'] . ' file=' . l:entry['path']
        elseif l:type ==# 'remove_hl'
            call nvim_buf_clear_namespace(l:entry['bufnr'], l:entry['hlsource'], 0, -1)
        endif

        let l:i += 1
    endwhile

    if len(s:action_queue) > 0
        let s:action_queue_timer = timer_start(s:action_queue_delay, function('s:process_actions'))
    endif
endfunction
