" Copyright (c) 2017 Lucas Hoffmann
" Licenced under a BSD-2-clause licence.  See the LICENSE file.

augroup NvimPager
  autocmd!
augroup END

" Setup function to be called from --cmd.  Some early options for both pager
" and cat mode are set here.
function! pager#start() abort
  call s:fix_runtimepath()
  " Don't remember file names and positions
  set shada=
  " prevent messages when opening files (especially for the cat version)
  set shortmess+=F
endfunction

" Setup function for pager mode.  Called from -c.
function! pager#prepare_pager() abort
  call s:detect_file_type()
  call s:set_options()
  call s:set_maps()
  autocmd NvimPager BufWinEnter,VimEnter * call s:pager()
endfunction

" Set up an VimEnter autocmd to print the files to stdout with highlighting.
" Should be called from -c.
function! pager#prepare_cat() abort
  call s:detect_file_type()
  autocmd NvimPager VimEnter * call s:cat()
endfunction

" Setup function for the VimEnter autocmd.
function! s:pager() abort
  if pager#check_escape_sequences()
    " Try to highlight ansi escape sequences with the AnsiEsc plugin.
    AnsiEsc
  endif
  set nomodifiable
  set nomodified
endfunction

" Call the highlight function to write the highlighted version of all buffers
" to stdout and quit nvim.
function! s:cat() abort
  while bufnr('%') < bufnr('$')
    call cat#highlight()
    bdelete
  endwhile
  call cat#highlight()
  quitall!
endfunction

" Fix the runtimepath.  All user nvim folders are replaced by corresponding
" nvimpager folders.
function! s:fix_runtimepath() abort
  let runtimepath = nvim_list_runtime_paths()
  " Don't modify our custom entry!
  let runtimepath = filter(runtimepath, { item -> item != $RUNTIME })
  let original = (empty($XDG_CONFIG_HOME) ? $HOME.'/.config' : $XDG_CONFIG_HOME).'/nvim'
  let new = original.'pager'
  call s:replace_prefix_in_string_list(runtimepath, original, new)
  let original = (empty($XDG_DATA_HOME) ? $HOME.'/.local/share' : $XDG_DATA_HOME).'/nvim'
  let new = original.'pager'
  call s:replace_prefix_in_string_list(runtimepath, original, new)
  call insert(runtimepath, $RUNTIME)
  let &runtimepath = join(runtimepath, ',')
  let $NVIM_RPLUGIN_MANIFEST = new . '/rplugin.vim'
endfunction

" Replace a string prefix in all items in a list
function! s:replace_prefix_in_string_list(list, prefix, replace) abort
  let length = len(a:prefix)
  for index in range(0, len(a:list)-1)
    if stridx(a:list[index], a:prefix) == 0
      let item = a:replace . (a:list[index][length:-1])
      let a:list[index] = item
    endif
  endfor
endfunction

" Detect possible filetypes for the current buffer by looking at the pstree or
" ansi escape sequences or manpage sequences in the current buffer.
function! s:detect_file_type() abort
  let l:doc = s:detect_doc_viewer_from_pstree()
  if l:doc ==# 'none'
    if s:detect_man_page_in_current_buffer()
      setfiletype man
    endif
  else
    if l:doc ==# 'git'
      call s:strip_ansi_escape_sequences_from_current_buffer()
    elseif l:doc ==# 'pydoc'
      call s:strip_overstike_from_current_buffer()
      let l:doc = 'man'
    elseif l:doc ==# 'perldoc'
      call s:strip_ansi_escape_sequences_from_current_buffer()
      call s:strip_overstike_from_current_buffer()
      let l:doc = 'man'
    endif
    execute 'setfiletype ' l:doc
  endif
endfunction

" Set some global options for interactive paging of files.
function! s:set_options() abort
  set mouse=a
  set scrolloff=0
  set hlsearch
  set incsearch
  nohlsearch
  set nowrapscan
  " Inhibit screen updates while searching
  set lazyredraw
  set laststatus=0
endfunction

" Set up mappings to make nvim behave a little more like a pager.
function! s:set_maps() abort
  nnoremap q :quitall!<CR>
  nnoremap <Space> <PageDown>
  nnoremap <S-Space> <PageUp>
  nnoremap g gg
  nnoremap <Up> <C-Y>
  nnoremap <Down> <C-E>
endfunction

" Unset all mappings set in s:set_maps().
function! s:unset_maps() abort
  nunmap q
  nunmap <Space>
  nunmap <S-Space>
  nunmap g
  nunmap <Up>
  nunmap <Down>
endfunction

" Display some help text about mappings.
function! s:help() abort
  " TODO
endfunction

" Search the begining of the current buffer to detect if it contains a man
" page.
function! s:detect_man_page_in_current_buffer() abort
  let l:pattern = '\v\C^N(\b.)?A(\b.)?M(\b.)?E(\b.)?[ \t]*$'
  let l:pos = getpos('.')
  keepjumps call cursor(1, 1)
  let l:match = search(l:pattern, 'cnW', 12, 100)
  keepjumps call cursor(l:pos)
  return l:match != 0
endfunction

" Parse the command of the calling process to detect some common documentation
" programs (man, pydoc, perldoc, git, ...).  $PPID was exported by the calling
" bash script and points to the calling program.
function! s:detect_doc_viewer_from_pstree() abort
  let l:pslist = systemlist('ps -o comm= '.$PPID)
  if type(l:pslist) ==# type('') && l:pslist ==# ''
    return 0
  endif
  let l:cmd = substitute(l:pslist[0], '^.*/', '', '')
  if l:cmd =~# '^man'
    return 'man'
  elseif l:cmd =~# '\v\C^[Pp]y(thon|doc)?[0-9.]*'
    return 'pydoc'
  elseif l:cmd =~# '\v\C^[Rr](uby|i)[0-9.]*'
    return 'ri'
  elseif l:cmd =~# '\v\C^perl(doc)?'
    return 'perldoc'
  elseif l:cmd =~# '\C^git'
    return 'git'
  endif
  return 'none'
endfunction

" Remove ansi escape sequences from the current buffer.
function! s:strip_ansi_escape_sequences_from_current_buffer() abort
  let l:mod = &modifiable
  let l:position = getpos('.')
  set modifiable
  keepjumps silent %substitute/\v\e\[[;?]*[0-9.;]*[a-z]//egi
  call setpos('.', l:position)
  let &modifiable = l:mod
endfunction

" Remove "overstrike" (like used in man pages) from current buffer.
function! s:strip_overstike_from_current_buffer() abort
  let l:mod = &modifiable
  let l:position = getpos('.')
  set modifiable
  keepjumps silent %substitute/\v.\b//eg
  call setpos('.', l:position)
  let &modifiable = l:mod
endfunction

" Check if the begining of the current buffer contains ansi escape sequences.
function! pager#check_escape_sequences() abort
  let l:ansi_regex = '\e\[[;?]*[0-9.;]*[A-Za-z]'
  return (&filetype ==# '' || &filetype ==# 'text')
	\ && search(l:ansi_regex, 'cnW', 100) != 0
endfunction
