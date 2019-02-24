" TODO: handle !has('signs')
" TODO: handle signs clearing when server exits
" https://github.com/vim/vim/pull/3652
let s:supports_signs = has('signs')
let s:supports_signs_api = exists('*sign_define')
let s:enabled = 0
let s:signs = {} " { server_name: { path: {} } }
let s:hlsources = {} " { server_name: { path: -1 } }
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
        let l:sign_string .= ' text=' . get(a:sign_options, 'text', a:sign_default_text)
        let l:sign_string .= ' texthl=' . a:sign_name . 'Sign'
        let l:sign_string .= ' linehl=' . a:sign_name . 'Line'
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
    if !s:supports_signs | return | endif
    if s:supports_signs_api
        let l:signs = sign_getplaced(a:bufnr, { 'group': '*' })
        return !empty(l:signs) ? l:signs[0]['signs'] : []
    else
        let l:signs = s:signs[b:server_name][expand("#" . a:bufnr . ":p")]
        return !empty(l:signs) ? l:signs : []
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

        if !has_key(s:signs, a:server_name)
            let s:signs[a:server_name] = {}
        endif

        if !has_key(s:signs[a:server_name], l:path)
            let s:signs[a:server_name][l:path] = []
        endif
    endif

    if !has_key(s:hlsources, a:server_name)
        let s:hlsources[a:server_name] = {}
    endif

    if !has_key(s:hlsources[a:server_name], l:path)
        let s:hlsources[a:server_name][l:path] = nvim_create_namespace('')
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
        if has_key(s:signs[a:server_name], a:path)
            for l:id in s:signs[a:server_name][a:path]
                execute ':sign unplace ' . l:id . ' file=' . a:path
            endfor
        endif
        if has_key(s:hlsources[a:server_name], a:path)
            let l:source = s:hlsources[a:server_name][a:path]
            call nvim_buf_clear_namespace(bufnr('%'), l:source, 0, -1)
        endif
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
                let l:sign_id = s:sign_place(l:sign_group, l:sign_name, a:server_name, a:path, l:line)
                call lsp#log('add signs', l:sign_id)

                call s:add_highlight(l:sign_name, a:server_name, a:path, l:line, l:item)
            endif
        endfor
    endif
endfunction

function! s:sign_place(sign_group, sign_name, server_name, path, line)
    let l:sign_id = 0
    if s:supports_signs_api
        " pass 0 and let vim generate sign id
        let l:sign_id = sign_place(0, a:sign_group, a:sign_name, a:path, { 'lnum': a:line })
    else
        let l:sign_id = g:lsp_next_sign_id
        execute ':sign place ' . l:sign_id . ' name=' . a:sign_name . ' line=' . a:line . ' file=' . a:path
        call add(s:signs[a:server_name][a:path], l:sign_id)
        call lsp#log('add signs', l:sign_id)
        let g:lsp_next_sign_id += 1
    endif
    return l:sign_id
endfunction

function! s:add_highlight(sign_name, server_name, path, line, item)
    let l:start = a:item['range']['start']['character']
    let l:end = a:item['range']['end']['character']
    let l:hlsource = s:hlsources[a:server_name][a:path]
    call nvim_buf_add_highlight(bufnr('%'), l:hlsource, a:sign_name . 'Text', a:line - 1, l:start, l:end)
endfunction
